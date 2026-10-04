import {reactive} from 'vue';
import {ApiError,PawdayClient,unwrap,type Principal,type Store} from '../../api-client/src';
export class StaffSession {
  readonly state=reactive({principal:null as Principal|null,stores:[] as Store[],storeId:'',loading:false,error:''});
  constructor(readonly client:PawdayClient){}
  can(permission?:string){return !!this.state.principal&&(!permission||this.state.principal.permissions.includes(permission));}
  async login(name:string,password:string,totp:string,deviceId:string){
    this.state.loading=true;this.state.error='';
    try{this.state.principal=await this.client.staffLogin({login_name:name,password,device_id:deviceId,...(totp?{totp_code:totp}:{})});await this.loadScope();}
    catch(error){this.client.clearSession();this.clear();throw error;}finally{this.state.loading=false;}
  }
  async loadScope(){
    const selected=this.state.storeId;
    this.state.stores=[];this.state.storeId='';
    if(this.client.realm!=='merchant'||!this.can('store.read'))return;
    const sessionId=this.state.principal?.session_id;
    const stores=unwrap(await this.client.api.GET('/merchant/stores')).data;
    if(!this.client.authenticated||sessionId!==this.state.principal?.session_id)throw new ApiError(401,'SESSION_CHANGED','');
    if(stores.some(s=>s.merchant_id!==this.state.principal?.merchant_id))throw new ApiError(403,'STORE_SCOPE_MISMATCH','');
    this.state.stores=stores;this.state.storeId=stores.some(s=>s.id===selected)?selected:stores[0]?.id??'';
  }
  selectStore(id:string){if(!this.state.stores.some(s=>s.id===id))throw new ApiError(403,'STORE_SCOPE_MISMATCH','');this.state.storeId=id;}
  async refreshIdentity(){this.state.principal=await this.client.me();await this.loadScope();}
  clear(){this.state.principal=null;this.state.stores=[];this.state.storeId='';}
}
export function explainError(error:unknown):string {
  if(error instanceof ApiError){
    const reason=error.versionConflict?'内容已更新，请重新读取后确认。':error.forbidden?'当前账号没有此操作权限。':error.code==='INVALID_CREDENTIALS'?'验证未通过，请检查密码和验证码。':error.status===401?'会话已失效，请重新登录。':error.status===0?'网络连接失败，请检查连接后重试。':`请求失败（${error.code}）`;
    return reason+(error.requestId?` 请求编号：${error.requestId}`:'');
  }
  return '操作失败，请稍后重试。';
}
