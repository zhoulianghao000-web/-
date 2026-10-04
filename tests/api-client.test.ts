import {describe,it,expect,vi} from 'vitest';
import {ApiError,PawdayClient,safeReturnTo,mutationHeaders,type Tokens} from '../packages/api-client/src';
import {StaffSession} from '../packages/web-shell/src/auth';
const meta={request_id:'00000000-0000-0000-0000-000000000001',correlation_id:'00000000-0000-0000-0000-000000000002'};
const tokens:Tokens={access_token:'a'.repeat(43),refresh_token:'b'.repeat(43),expires_in:900,session_id:meta.request_id,user_id:null};
const principal={id:meta.request_id,realm:'MERCHANT' as const,merchant_id:meta.request_id,user_id:null,session_id:meta.request_id,permissions:['store.read']};
const json=(data:unknown,status=200)=>new Response(JSON.stringify({data,meta}),{status,headers:{'Content-Type':'application/json'}});
const denied=(status:number,code:string)=>new Response(JSON.stringify({error:{code,message:code,retryable:false,details:{}},meta}),{status,headers:{'Content-Type':'application/json'}});
describe('realm-bound generated API transport',()=>{
  it('wrong reverify credentials do not rotate or discard a valid session',async()=>{
    const network=vi.fn<typeof fetch>(async()=>denied(401,'INVALID_CREDENTIALS'));const client=new PawdayClient('admin','http://localhost/api/v1',network);client.setSession(tokens);await expect(client.reverify({action:'session.revoke-others',password:'wrong',totp_code:'123456'})).rejects.toMatchObject({code:'INVALID_CREDENTIALS'});expect(network).toHaveBeenCalledTimes(1);expect(client.authenticated).toBe(true);
  });
  it('discards a late successful principal after logout',async()=>{
    let resolve:((r:Response)=>void)|undefined;const client=new PawdayClient('merchant','http://localhost/api/v1',async()=>new Promise(r=>{resolve=r;}));client.setSession(tokens);const pending=client.me();client.clearSession();resolve?.(json(principal));await expect(pending).rejects.toMatchObject({code:'SESSION_CHANGED'});expect(client.authenticated).toBe(false);
  });
  it('discards a late login after the session generation changes',async()=>{
    let resolve:((r:Response)=>void)|undefined;const client=new PawdayClient('merchant','http://localhost/api/v1',async()=>new Promise(r=>{resolve=r;}));const pending=client.staffLogin({login_name:'staff',password:'secret',device_id:'device'});client.clearSession();resolve?.(json(tokens));await expect(pending).rejects.toMatchObject({code:'SESSION_CHANGED'});expect(client.authenticated).toBe(false);
  });
  it('includes bearer for reverify OTP but omits it for anonymous login OTP',async()=>{
    const captured:Request[]=[];const client=new PawdayClient('consumer','http://localhost/api/v1',async input=>{captured.push(input as Request);return json({id:meta.request_id,version:1,accepted_at:'2026-10-04T00:00:00Z'});});client.setSession(tokens);
    await client.api.POST('/consumer/auth/phone/request-code',{body:{phone_e164:'+8613800000000',purpose:'REVERIFY'}});await client.api.POST('/consumer/auth/phone/request-code',{body:{phone_e164:'+8613800000000',purpose:'LOGIN'}});expect(captured[0]?.headers.get('Authorization')).toBe(`Bearer ${tokens.access_token}`);expect(captured[1]?.headers.get('Authorization')).toBeNull();
  });
  it('rejects another realm before sending credentials',async()=>{
    const network=vi.fn<typeof fetch>();const client=new PawdayClient('merchant','http://localhost/api/v1',network);client.setSession(tokens);
    await expect(client.api.GET('/admin/me')).rejects.toMatchObject({code:'REALM_MISMATCH'});expect(network).not.toHaveBeenCalled();
  });
  it('single-flights concurrent 401 refresh and retries with rotated tokens',async()=>{
    let refreshes=0;const requests:Request[]=[];
    const network:typeof fetch=async input=>{const r=input as Request;requests.push(r);if(r.url.endsWith('/refresh')){refreshes++;await new Promise(resolve=>setTimeout(resolve,20));return json({...tokens,access_token:'c'.repeat(43)});}return r.headers.get('Authorization')===`Bearer ${tokens.access_token}`?denied(401,'SESSION_EXPIRED'):json(principal);};
    const client=new PawdayClient('merchant','http://localhost/api/v1',network);client.setSession(tokens);
    await Promise.all([client.me(),client.me()]);expect(refreshes).toBe(1);expect(requests.filter(r=>r.url.endsWith('/me'))).toHaveLength(4);expect(requests.every(r=>r.headers.get('X-Request-ID'))).toBe(true);
  });
  it('cannot restore a session after logout while refresh is in flight',async()=>{
    let resolve:((r:Response)=>void)|undefined;const network:typeof fetch=async()=>new Promise(r=>{resolve=r;});
    const client=new PawdayClient('merchant','http://localhost/api/v1',network);client.setSession(tokens);const pending=client.refresh();client.clearSession();resolve?.(json(tokens));
    await expect(pending).rejects.toMatchObject({code:'SESSION_CHANGED'});expect(client.authenticated).toBe(false);
  });
  it('clears session when the refresh token is revoked',async()=>{
    const client=new PawdayClient('merchant','http://localhost/api/v1',async()=>denied(401,'REFRESH_REVOKED'));client.setSession(tokens);
    await expect(client.me()).rejects.toMatchObject({code:'REFRESH_REVOKED'});expect(client.authenticated).toBe(false);
  });
  it('does not attach bearer to public login, or log credentials',async()=>{
    let loginAuth:string|null='unexpected';const network:typeof fetch=async input=>{const r=input as Request;if(r.url.endsWith('/login')){loginAuth=r.headers.get('Authorization');return json(tokens);}return json(principal);};
    const client=new PawdayClient('merchant','http://localhost/api/v1',network);client.setSession(tokens);await client.staffLogin({login_name:'staff',password:'private',device_id:'device'});expect(loginAuth).toBeNull();
  });
  it('requires administrator MFA before issuing a login request',async()=>{
    const network=vi.fn<typeof fetch>();const client=new PawdayClient('admin','http://localhost/api/v1',network);
    await expect(client.staffLogin({login_name:'admin',password:'private',device_id:'device'})).rejects.toMatchObject({code:'MFA_REQUIRED'});expect(network).not.toHaveBeenCalled();
  });
  it('preserves version-conflict detail and request ID without replaying a mutation',async()=>{
    const network=vi.fn<typeof fetch>(async()=>denied(409,'VERSION_CONFLICT'));const client=new PawdayClient('admin','http://localhost/api/v1',network);client.setSession(tokens);
    const promise=client.api.GET('/admin/me');await expect(promise).rejects.toMatchObject({status:409,code:'VERSION_CONFLICT',requestId:meta.request_id,versionConflict:true});expect(network).toHaveBeenCalledTimes(1);
  });
  it('never automatically repeats a proof-consuming mutation without an idempotency contract',async()=>{
    const network=vi.fn<typeof fetch>(async()=>denied(401,'SESSION_EXPIRED'));const client=new PawdayClient('merchant','http://localhost/api/v1',network);client.setSession(tokens);
    await expect(client.revokeOthers('proof')).rejects.toMatchObject({status:401});expect(network).toHaveBeenCalledTimes(1);expect(client.authenticated).toBe(false);
  });
  it('returns a retryable network error instead of a fabricated successful result',async()=>{
    const client=new PawdayClient('merchant','http://localhost/api/v1',async()=>{throw new TypeError('offline');});client.setSession(tokens);await expect(client.me()).rejects.toMatchObject({code:'NETWORK_UNAVAILABLE',retryable:true});
  });
  it('maps malformed upstream failures to structured errors',async()=>{
    const client=new PawdayClient('merchant','http://localhost/api/v1',async()=>new Response('<html>offline</html>',{status:503}));client.setSession(tokens);await expect(client.me()).rejects.toBeInstanceOf(ApiError);
  });
  it('validates server principal realm before exposing a session',async()=>{
    const client=new PawdayClient('merchant','http://localhost/api/v1',async input=>(input as Request).url.endsWith('/login')?json(tokens):json({...principal,realm:'ADMIN'}));await expect(client.staffLogin({login_name:'x',password:'x',device_id:'x'})).rejects.toMatchObject({code:'REALM_MISMATCH'});expect(client.authenticated).toBe(false);
  });
});
describe('scope, intent and mutation handling',()=>{
  it.each(['https://bad.example','//bad.example','/\\bad','/%2f%2fbad','/%5cbad','/login','/auth/login','/%ZZ'])('rejects unsafe returnTo %s',value=>{expect(safeReturnTo(value)).toBe('/dashboard');});
  it('preserves internal returnTo and its query',()=>{expect(safeReturnTo('/audit?limit=20')).toBe('/audit?limit=20');});
  it('keeps the exact caller-owned idempotency key and version',()=>{expect(mutationHeaders('stable-key','one-use-proof',4)).toEqual({'Idempotency-Key':'stable-key','X-Reverify-Token':'one-use-proof','If-Match':'"4"'});});
  it('rejects a store belonging to another merchant and clears session',async()=>{
    const network:typeof fetch=async input=>{const path=(input as Request).url;return path.endsWith('/login')?json(tokens):path.endsWith('/me')?json(principal):json([{id:meta.request_id,name:'wrong store',merchant_id:meta.correlation_id}]);};
    const client=new PawdayClient('merchant','http://localhost/api/v1',network);const session=new StaffSession(client);await expect(session.login('x','x','','device')).rejects.toMatchObject({code:'STORE_SCOPE_MISMATCH'});expect(session.state.principal).toBeNull();expect(client.authenticated).toBe(false);
  });
  it('cannot choose a store outside the server-authorized list',()=>{
    const session=new StaffSession(new PawdayClient('merchant','http://localhost/api/v1'));session.state.stores=[{id:'a',name:'A',merchant_id:'merchant'}];expect(()=>session.selectStore('b')).toThrow(ApiError);session.selectStore('a');expect(session.state.storeId).toBe('a');
  });
  it('permission hiding follows actual current permissions',()=>{
    const session=new StaffSession(new PawdayClient('merchant','http://localhost/api/v1'));expect(session.can()).toBe(false);session.state.principal=principal;expect(session.can('store.read')).toBe(true);expect(session.can('audit.read')).toBe(false);
  });
});
