import createClient from 'openapi-fetch';
import type {components, paths} from './generated/schema';
export type Realm = 'consumer' | 'merchant' | 'admin';
export type Tokens = components['schemas']['Tokens'];
export type Principal = components['schemas']['Principal'];
export type Store = components['schemas']['Store'];
export type Audit = components['schemas']['Audit'];
export type Session = components['schemas']['Session'];
export type Reverify = components['schemas']['Reverify'];
export type Proof = components['schemas']['Proof'];
export type {components, paths};

export class ApiError extends Error {
  constructor(public status:number, public code:string, public requestId:string, public retryable=false, public details:unknown={}) {super(code);this.name='ApiError';}
  get versionConflict(){return this.status===409;}
  get forbidden(){return this.status===403;}
}
export function safeReturnTo(value:unknown, fallback='/dashboard'):string {
  if(typeof value!=='string'||!value.startsWith('/')||value.startsWith('//')||/[\\\u0000-\u001f]/.test(value))return fallback;
  try {const decoded=decodeURIComponent(value);if(decoded.startsWith('//')||/[\\\u0000-\u001f]/.test(decoded))return fallback;}catch{return fallback;}
  if(value.startsWith('/auth/')||value.startsWith('/login'))return fallback;
  return value;
}
export const mutationHeaders=(key:string,proof?:string,version?:number)=>({
  'Idempotency-Key':key,...(proof?{'X-Reverify-Token':proof}:{}),...(version!==undefined?{'If-Match':String(version)}:{}),
});
export function unwrap<T>(result:{data?:T;error?:unknown;response:Response}):T {
  if(result.data===undefined)throw new ApiError(result.response.status,'EMPTY_RESPONSE',result.response.headers.get('X-Request-ID')??'');
  return result.data;
}

/** Tokens stay in memory on web. Reload requires login; rotation is fenced by session generation. */
export class PawdayClient {
  private tokens:Tokens|null=null;
  private epoch=0;
  private refreshFlight:Promise<void>|null=null;
  readonly api;
  constructor(readonly realm:Realm, readonly baseUrl:string, private readonly network:typeof fetch=fetch, private readonly onExpired:()=>void=()=>{}) {
    this.api=createClient<paths>({baseUrl,fetch:this.transport});
  }
  get authenticated(){return this.tokens!==null;}
  setSession(tokens:Tokens){this.epoch++;this.tokens=tokens;}
  clearSession(){this.epoch++;this.tokens=null;this.onExpired();}
  private failure=async(response:Response):Promise<never>=>{
    let payload:components['schemas']['ErrorEnvelope']|undefined;
    try{payload=await response.clone().json();}catch{/* Proxies can return non-JSON errors. */}
    throw new ApiError(response.status,payload?.error?.code??'HTTP_ERROR',payload?.meta?.request_id??response.headers.get('X-Request-ID')??'',payload?.error?.retryable??false,payload?.error?.details);
  };
  private transport=async(input:Request):Promise<Response>=>{
    const base=new URL(this.baseUrl,globalThis.location?.origin??'http://localhost');
    const url=new URL(input.url);
    if(url.origin!==base.origin||!url.pathname.startsWith(base.pathname.replace(/\/$/,'')+'/'))throw new ApiError(0,'INVALID_API_DESTINATION','');
    const relative=url.pathname.slice(base.pathname.replace(/\/$/,'').length);
    const pathRealm=relative.split('/')[1];
    if(['consumer','merchant','admin'].includes(pathRealm??'')&&pathRealm!==this.realm)throw new ApiError(403,'REALM_MISMATCH','');
    let publicAuth=/\/auth\/(login|refresh|phone\/request-code|phone\/verify)$/.test(relative);
    if(relative.endsWith('/phone/request-code')){
      const body=await input.clone().json() as components['schemas']['CodeRequest'];
      publicAuth=body.purpose==='LOGIN';
    }
    const original=input.clone();
    const send=()=>{
      const request=original.clone();request.headers.set('X-Request-ID',crypto.randomUUID());
      if(!publicAuth&&this.tokens)request.headers.set('Authorization',`Bearer ${this.tokens.access_token}`);
      else request.headers.delete('Authorization');
      return this.network.call(globalThis,request);
    };
    const epoch=this.epoch;const access=this.tokens?.access_token;
    let response:Response;
    try{response=await send();}catch{throw new ApiError(0,'NETWORK_UNAVAILABLE','',true);}
    if(!publicAuth&&epoch!==this.epoch)throw new ApiError(401,'SESSION_CHANGED','');
    if(response.status===401&&!publicAuth&&this.tokens&&(input.method==='GET'||input.headers.has('Idempotency-Key'))) {
      // Another concurrent request may already have rotated the same access token.
      if(epoch===this.epoch&&access===this.tokens.access_token)await this.refresh();
      if(!this.tokens)await this.failure(response);
      try{response=await send();}catch{throw new ApiError(0,'NETWORK_UNAVAILABLE','',true);}
      if(epoch!==this.epoch)throw new ApiError(401,'SESSION_CHANGED','');
    }
    if(!response.ok) {
      if(response.status===401&&!publicAuth&&epoch===this.epoch)this.clearSession();
      await this.failure(response);
    }
    return response;
  };
  async refresh():Promise<void>{
    if(this.refreshFlight)return this.refreshFlight;
    const epoch=this.epoch;const refreshToken=this.tokens?.refresh_token;
    if(!refreshToken)throw new ApiError(401,'SESSION_EXPIRED','');
    this.refreshFlight=(async()=>{
      try {
        const response=await this.network.call(globalThis,new Request(`${this.baseUrl}/${this.realm}/auth/refresh`,{method:'POST',headers:{'Content-Type':'application/json','X-Request-ID':crypto.randomUUID()},body:JSON.stringify({refresh_token:refreshToken})}));
        if(!response.ok)await this.failure(response);
        const value=await response.json() as components['schemas']['TokensEnvelope'];
        if(epoch!==this.epoch)throw new ApiError(401,'SESSION_CHANGED','');
        this.tokens=value.data;
      } catch(error) {if(epoch===this.epoch)this.clearSession();throw error;}
      finally{this.refreshFlight=null;}
    })();
    return this.refreshFlight;
  }
  async staffLogin(body:components['schemas']['StaffLogin']):Promise<Principal>{
    const epoch=this.epoch;
    if(this.realm==='consumer')throw new ApiError(403,'REALM_MISMATCH','');
    let tokens:Tokens;
    if(this.realm==='admin'){
      if(!body.totp_code)throw new ApiError(400,'MFA_REQUIRED','');
      tokens=unwrap(await this.api.POST('/admin/auth/login',{body:{...body,totp_code:body.totp_code}})).data;
    } else tokens=unwrap(await this.api.POST('/merchant/auth/login',{body})).data;
    if(epoch!==this.epoch)throw new ApiError(401,'SESSION_CHANGED','');
    this.setSession(tokens);
    const acceptedEpoch=this.epoch;
    try{return await this.me();}catch(error){if(acceptedEpoch===this.epoch)this.clearSession();throw error;}
  }
  async me():Promise<Principal>{
    const epoch=this.epoch;
    const result=this.realm==='merchant'?await this.api.GET('/merchant/me'):this.realm==='admin'?await this.api.GET('/admin/me'):await this.api.GET('/consumer/me');
    const principal=unwrap(result).data;
    if(epoch!==this.epoch)throw new ApiError(401,'SESSION_CHANGED','');
    if(principal.realm!==this.realm.toUpperCase()){this.clearSession();throw new ApiError(403,'REALM_MISMATCH','');}
    return principal;
  }
  async reverify(body:Reverify):Promise<Proof>{
    const result=this.realm==='admin'?await this.api.POST('/admin/auth/reverify',{body}):this.realm==='merchant'?await this.api.POST('/merchant/auth/reverify',{body}):await this.api.POST('/consumer/auth/reverify',{body});
    return unwrap(result).data;
  }
  async sessions():Promise<Session[]>{
    return unwrap(this.realm==='admin'?await this.api.GET('/admin/auth/sessions'):this.realm==='merchant'?await this.api.GET('/merchant/auth/sessions'):await this.api.GET('/consumer/auth/sessions')).data;
  }
  async revokeOthers(proof:string):Promise<void>{
    const options={params:{header:{'X-Reverify-Token':proof}}};
    unwrap(this.realm==='admin'?await this.api.POST('/admin/auth/sessions/revoke-others',options):this.realm==='merchant'?await this.api.POST('/merchant/auth/sessions/revoke-others',options):await this.api.POST('/consumer/auth/sessions/revoke-others',options));
  }
  async logout():Promise<void>{
    try {unwrap(this.realm==='admin'?await this.api.POST('/admin/auth/logout'):this.realm==='merchant'?await this.api.POST('/merchant/auth/logout'):await this.api.POST('/consumer/auth/logout'));}finally{this.clearSession();}
  }
}
