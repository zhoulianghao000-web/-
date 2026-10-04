<script setup lang="ts">
import {computed,onMounted,ref,watch} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
type Offer=components['schemas']['ManagedOffer'];
type Adjustment=components['schemas']['InventoryAdjustmentRecord'];
type Changes=components['schemas']['OfferPriceChanges'];
const props=defineProps<{realm:'merchant'|'admin';session:StaffSession}>();
const offers=ref<Offer[]>([]),selected=ref<Offer>(),history=ref<Adjustment[]>([]);
const skus=ref<components['schemas']['CatalogSku'][]>([]);
class InputError extends Error {}
function failure(e:unknown){return e instanceof InputError?e.message:explainError(e);}
const loading=ref(false),busy=ref(false),error=ref(''),notice=ref('');
const sku=ref(''),sale=ref(''),member=ref(''),sla=ref(''),reason=ref('');
const delta=ref(''),reasonCode=ref<'RESTOCK'|'COUNT_CORRECTION'|'DAMAGE'>('RESTOCK');
const password=ref(''),totp=ref(''),defaultScope=ref(false);
const store=computed(()=>defaultScope.value?null:props.session.state.storeId);
const canWrite=computed(()=>props.realm==='merchant'&&props.session.can('offer.write'));
const canAdjust=computed(()=>props.realm==='merchant'&&props.session.can('inventory.adjust'));
const canManage=computed(()=>props.realm==='admin'&&props.session.can('offer.admin.manage'));
let generation=0;
const keys=new Map<string,string>();
function identity(){return props.session.state.principal?.session_id;}
function integer(raw:string,min:number,max=1000000000){if(!/^-?\d+$/.test(raw))throw new InputError('请输入整数。');const n=Number(raw);if(!Number.isSafeInteger(n)||n<min||n>max)throw new InputError('数值超出允许范围。');return n;}
function prices():Changes{return {sale_price_fen:integer(sale.value,1),member_price_fen:member.value===''?null:integer(member.value,1),fulfillment_sla:sla.value.trim()};}
function fill(offer:Offer){selected.value=offer;sale.value=String(offer.sale_price_fen);member.value=offer.member_price_fen===null?'':String(offer.member_price_fen);sla.value=offer.fulfillment_sla;delta.value='';reason.value='';}
async function load(){
 const g=++generation,s=identity(),sc=store.value;loading.value=true;selected.value=undefined;history.value=[];offers.value=[];password.value='';totp.value='';
 const valid=()=>g===generation&&s===identity()&&sc===store.value;
 try {const rows:Offer[]=[];let cursor:string|null=null;
  do {const q:{limit:number;cursor?:string;store_id?:string}={limit:100,...(cursor?{cursor}:{}),...(props.realm==='merchant'&&sc?{store_id:sc}:{})};
   const result=props.realm==='merchant'?unwrap(await props.session.client.api.GET('/merchant/offers',{params:{query:q}})):unwrap(await props.session.client.api.GET('/admin/offers',{params:{query:q}}));
   rows.push(...result.data);cursor=result.page.has_more?result.page.next_cursor:null;
  }while(cursor&&valid());
  if(props.realm==='merchant'&&canWrite.value&&props.session.can('catalog.standard.read')){const choices:components['schemas']['CatalogSku'][]=[];let after:string|null=null;do{const q:{limit:number;cursor?:string}={limit:100,...(after?{cursor:after}:{})};const result=unwrap(await props.session.client.api.GET('/merchant/catalog/search',{params:{query:q}}));choices.push(...result.data);after=result.page.has_more?result.page.next_cursor:null;}while(after&&valid());if(valid())skus.value=choices;}
  if(valid())offers.value=props.realm==='merchant'&&defaultScope.value?rows.filter(x=>x.store_id===null):rows;
 }catch(e){if(valid())error.value=explainError(e);}finally{if(valid())loading.value=false;}
}
async function view(offer:Offer){
 const g=++generation,s=identity(),sc=store.value;loading.value=true;error.value='';history.value=[];
 const valid=()=>g===generation&&s===identity()&&sc===store.value;
 try {const params={path:{id:offer.id}};const result=props.realm==='merchant'?unwrap(await props.session.client.api.GET('/merchant/offers/{id}',{params})):unwrap(await props.session.client.api.GET('/admin/offers/{id}',{params}));
  const rows:Adjustment[]=[];let cursor:string|null=null;
  do {const p:{path:{id:string};query:{limit:number;cursor?:string}}={path:{id:offer.id},query:{limit:100,...(cursor?{cursor}:{})}};const h=props.realm==='merchant'?unwrap(await props.session.client.api.GET('/merchant/offers/{id}/inventory-adjustments',{params:p})):unwrap(await props.session.client.api.GET('/admin/offers/{id}/inventory-adjustments',{params:p}));rows.push(...h.data);cursor=h.page.has_more?h.page.next_cursor:null;}while(cursor&&valid());
  if(valid()){fill(result.data);history.value=rows;}
 }catch(e){if(valid())error.value=explainError(e);}finally{if(valid())loading.value=false;}
}
async function command(name:string,payload:unknown,send:(key:string,proof?:string)=>Promise<unknown>,admin=false){
 if(busy.value||loading.value)return;const s=identity(),sc=store.value;busy.value=true;error.value='';notice.value='';
 const fingerprint=JSON.stringify([s,name,payload]);let key=keys.get(fingerprint);if(!key){key=crypto.randomUUID();keys.set(fingerprint,key);}
 try {let proof:string|undefined;if(admin){const p=await props.session.client.reverify({action:'offer.admin.manage',password:password.value,totp_code:totp.value});proof=p.reverify_token;}
  await send(key,proof);if(s!==identity()||sc!==store.value)return;keys.delete(fingerprint);const target=selected.value?.id;await load();if(target){const row=offers.value.find(x=>x.id===target);if(row)await view(row);}notice.value='已保存，操作已记录。';
 }catch(e){if(s===identity()&&sc===store.value)error.value=explainError(e);}finally{password.value='';totp.value='';busy.value=false;}
}
async function create(){try{if(!store.value&&!defaultScope.value)throw new InputError('请选择授权门店。');const body={store_id:store.value,sku_id:sku.value.trim(),...prices()} as components['schemas']['OfferCreateInput'];await command('create',body,async key=>unwrap(await props.session.client.api.POST('/merchant/offers',{body,params:{header:{'Idempotency-Key':key}}})));}catch(e){error.value=failure(e);}}
async function save(){if(!selected.value)return;try{const offer=selected.value,body=prices();await command('patch',[offer.id,offer.version,body],async key=>unwrap(await props.session.client.api.PATCH('/merchant/offers/{id}',{body,params:{path:{id:offer.id},header:{'If-Match':`"${offer.version}"`,'Idempotency-Key':key}}})));}catch(e){error.value=failure(e);}}
async function adjust(){if(!selected.value)return;try{const offer=selected.value,qty=integer(delta.value,-1000000000);if(qty===0)throw new InputError('调整数量不能为 0。');const body={delta_qty:qty,reason_code:reasonCode.value,expected_version:offer.inventory.version};await command('adjust',[offer.id,body],async key=>unwrap(await props.session.client.api.POST('/merchant/offers/{id}/inventory-adjustments',{body,params:{path:{id:offer.id},header:{'Idempotency-Key':key}}})));}catch(e){error.value=failure(e);}}
async function state(action:'activate'|'pause'|'freeze'|'unfreeze'|'delist'){
 if(!selected.value)return;const offer=selected.value,body={reason:reason.value.trim()};if(!body.reason){error.value='请填写操作原因。';return;}
 await command(action,[offer.id,offer.version,body],async(key,proof)=>{
  const params={path:{id:offer.id},header:{'If-Match':`"${offer.version}"`,'Idempotency-Key':key,'X-Reverify-Token':proof??''}};
  if(action==='activate'||action==='pause')return unwrap(await props.session.client.api.POST(`/merchant/offers/{id}/${action}`,{body,params}));
  return unwrap(await props.session.client.api.POST(`/admin/offers/{id}/${action}`,{body,params}));
 },props.realm==='admin');
}
watch(()=>[identity(),props.session.state.storeId,defaultScope.value],()=>{keys.clear();notice.value='';error.value='';void load();});onMounted(load);
</script>
<template>
 <div :inert="busy||loading">
  <div class="page-heading"><div><p class="eyebrow">OFFERS & INVENTORY</p><h1>{{ realm==='merchant'?'报价与库存':'报价风控' }}</h1><p class="muted">库存调整保留流水，平台标准资料由来源版本管理。</p></div><button class="secondary" @click="load">刷新</button></div>
  <p v-if="error" role="alert" class="error">{{ error }}</p><p v-if="notice" role="status" class="notice">{{ notice }}</p>
  <label v-if="realm==='merchant'&&session.can('offer.default-scope')"><input v-model="defaultScope" type="checkbox" />商户默认履约范围</label>
  <div class="cards"><article v-for="offer in offers" :key="offer.id"><h2>{{ offer.sku_code }}</h2><p>{{ offer.merchant_name }} · {{ offer.store_name??'默认履约范围' }}</p><p>{{ offer.sale_status }} · {{ offer.sale_price_fen }} 分</p><p>可用 {{ offer.inventory.available_qty }} / 实物 {{ offer.inventory.on_hand_qty }} / 预占 {{ offer.inventory.reserved_qty }}</p><button class="secondary" @click="view(offer)">查看报价与流水</button></article></div>
  <p v-if="!loading&&!offers.length">当前范围暂无报价。</p>
  <div class="cards" style="margin-top:24px">
   <form v-if="canWrite&&!selected&&session.can('catalog.standard.read')" @submit.prevent="create"><h2>创建报价</h2><p>选择已发布标准资料的规格。初始库存为 0，请另行登记入库。</p><label>标准规格<select v-model="sku" required><option value="" disabled>请选择规格</option><option v-for="item in skus" :key="item.id" :value="item.id">{{ item.sku_code }} · {{ item.weight_g }} 克 / {{ item.package_unit }}</option></select></label><label>售价（分）<input v-model="sale" inputmode="numeric" required /></label><label>会员价（分，可空）<input v-model="member" inputmode="numeric" /></label><label>履约承诺<input v-model="sla" required maxlength="500" /></label><button>创建草稿报价</button></form>
   <article v-if="selected"><h2>报价详情</h2><p>{{ selected.sku_code }} · {{ selected.store_name??'默认履约范围' }}</p><p>状态 {{ selected.sale_status }}</p><p>售价 {{ selected.sale_price_fen }} 分 · 会员价 {{ selected.member_price_fen??'未设置' }} · {{ selected.fulfillment_sla }}</p><p>实物 {{ selected.inventory.on_hand_qty }} · 预占 {{ selected.inventory.reserved_qty }} · 可用 {{ selected.inventory.available_qty }}</p><button v-if="canWrite" class="secondary" @click="selected=undefined;history=[];sale='';member='';sla=''">返回创建报价</button></article>
   <form v-if="canWrite&&selected&&!['FROZEN','DELISTED'].includes(selected.sale_status)" @submit.prevent="save"><h2>修改报价</h2><label>售价（分）<input v-model="sale" inputmode="numeric" required /></label><label>会员价（分，可空）<input v-model="member" inputmode="numeric" /></label><label>履约承诺<input v-model="sla" required maxlength="500" /></label><button>保存报价</button></form>
   <form v-if="canAdjust&&selected&&selected.sale_status!=='DELISTED'" @submit.prevent="adjust"><h2>库存调整</h2><label>增减数量<input v-model="delta" inputmode="numeric" required placeholder="入库填正数，损耗填负数" /></label><label>调整原因<select v-model="reasonCode"><option value="RESTOCK">补货</option><option value="COUNT_CORRECTION">盘点纠正</option><option value="DAMAGE">损耗</option></select></label><button>提交库存调整</button></form>
   <article v-if="selected&&(canWrite||canManage)"><h2>销售状态</h2><label>操作原因<textarea v-model="reason" maxlength="2000" /></label><template v-if="canManage"><label>再次输入密码<input v-model="password" type="password" autocomplete="current-password" /></label><label>新的动态验证码<input v-model="totp" inputmode="numeric" maxlength="6" autocomplete="one-time-code" /></label><button v-if="!['FROZEN','DELISTED'].includes(selected.sale_status)" @click="state('freeze')">冻结报价</button><button v-if="selected.sale_status==='FROZEN'" @click="state('unfreeze')">解冻为暂停</button><button v-if="selected.sale_status!=='DELISTED'" @click="state('delist')">永久下架此报价</button></template><template v-else><button v-if="['DRAFT','PAUSED'].includes(selected.sale_status)" @click="state('activate')">上架报价</button><button v-if="selected.sale_status==='ACTIVE'" @click="state('pause')">暂停销售</button></template></article>
  </div>
  <article v-if="selected" style="margin-top:24px"><h2>库存调整流水</h2><div class="table-wrap"><table><thead><tr><th>原因</th><th>数量变化</th><th>调整后实物</th><th>预占</th><th>库存版本</th></tr></thead><tbody><tr v-for="item in history" :key="item.id"><td>{{ item.reason_code }}</td><td>{{ item.delta_qty }}</td><td>{{ item.resulting_on_hand_qty }}</td><td>{{ item.resulting_reserved_qty }}</td><td>{{ item.resulting_version }}</td></tr></tbody></table></div></article>
 </div><p v-if="busy||loading" role="status">正在处理…</p>
</template>
