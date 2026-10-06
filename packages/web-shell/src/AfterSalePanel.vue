<script setup lang="ts">
import {ref,watch} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
const props=defineProps<{session:StaffSession;realm:'merchant'|'admin';suborderId:string;itemNames?:Record<string,string>}>();
type AfterSale=components['schemas']['AfterSale'];
const rows=ref<AfterSale[]>([]),busy=ref(false),error=ref(''),notice=ref(''),reasons=ref<Record<string,string>>({}),actions=ref<Record<string,string>>({}),password=ref(''),totp=ref('');let generation=0;const keys:Record<string,string>={};const fingerprints:Record<string,string>={};
function money(fen:number){return `¥${(fen/100).toFixed(2)}`;}
function state(value:string){return ({PENDING_MERCHANT:'待商家处理',WAITING_RETURN:'待消费者寄回',RETURN_IN_TRANSIT:'退货在途',WAITING_INSPECTION:'待商家验收',REFUND_PENDING:'退款处理中',PLATFORM_ESCALATED:'平台介入中',COMPLETED:'已完成',REJECTED:'已拒绝',CANCELLED:'已撤销'} as Record<string,string>)[value]??'状态未知';}
function refundState(a:AfterSale){if(!a.refund)return a.refund_amount_fen>0?'退款待登记':'无退款';return ({CREATED:'退款待发起',PROCESSING:'退款处理中',SUCCEEDED:`退款成功 ${a.refund.refund_no}`,FAILED_RETRYABLE:'退款重试中',FAILED_FINAL:'退款待人工处理',CANCELLED:'退款已作废'} as Record<string,string>)[a.refund.status]??'退款状态未知';}
async function load(){if(busy.value)return;const epoch=++generation,identity=props.session.state.principal?.session_id;busy.value=true;error.value='';try{const value=unwrap(await props.session.client.api.GET(props.realm==='merchant'?'/merchant/suborders/{id}/aftersales':'/admin/suborders/{id}/aftersales',{params:{path:{id:props.suborderId}}})).data;if(epoch===generation&&identity===props.session.state.principal?.session_id)rows.value=value;}catch(e){if(epoch===generation)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}}
function keyFor(a:AfterSale,action:string,extra:unknown){const scope=`${a.id}:${action}`,next=JSON.stringify([scope,a.version,extra]);if(fingerprints[scope]!==next){fingerprints[scope]=next;keys[scope]=crypto.randomUUID();}return keys[scope]!;}
async function run(a:AfterSale,action:string,extra:unknown,call:(key:string)=>Promise<AfterSale>){if(busy.value)return;const epoch=++generation,identity=props.session.state.principal?.session_id;busy.value=true;error.value='';notice.value='';try{const value=await call(keyFor(a,action,extra));if(epoch===generation&&identity===props.session.state.principal?.session_id){rows.value=rows.value.map(r=>r.id===value.id?value:r);delete keys[`${a.id}:${action}`];notice.value='售后处理已完成';}}catch(e){if(epoch===generation)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}}
function decide(a:AfterSale){const action=actions.value[a.id]??'',reason=reasons.value[a.id]??'';run(a,'decide',{action,reason},key=>props.session.client.api.POST('/merchant/aftersales/{id}/decide',{params:{path:{id:a.id},header:{'If-Match':`"${a.version}"`,'Idempotency-Key':key}},body:{action:action as 'APPROVE_REFUND'|'APPROVE_RETURN'|'REJECT',reason}}).then(r=>unwrap(r).data));}
function arrival(a:AfterSale){run(a,'arrival',{},key=>props.session.client.api.POST('/merchant/aftersales/{id}/confirm-arrival',{params:{path:{id:a.id},header:{'If-Match':`"${a.version}"`,'Idempotency-Key':key}},body:{}}).then(r=>unwrap(r).data));}
function inspect(a:AfterSale){const action=actions.value[a.id]??'',reason=reasons.value[a.id]??'';run(a,'inspect',{action,reason},key=>props.session.client.api.POST('/merchant/aftersales/{id}/inspect',{params:{path:{id:a.id},header:{'If-Match':`"${a.version}"`,'Idempotency-Key':key}},body:{action:action as 'ACCEPT'|'REJECT',reason}}).then(r=>unwrap(r).data));}
function arbitrate(a:AfterSale){const decision=actions.value[a.id]??'',reason=reasons.value[a.id]??'';run(a,'arbitrate',{decision,reason},async key=>{const proof=await props.session.client.reverify({action:'aftersale.arbitrate',password:password.value,totp_code:totp.value});return props.session.client.api.POST('/admin/aftersales/{id}/decide',{params:{path:{id:a.id},header:{'If-Match':`"${a.version}"`,'Idempotency-Key':key,'X-Reverify-Token':proof.reverify_token}},body:{decision:decision as 'REFUND_APPROVED'|'REJECTED',reason}}).then(r=>unwrap(r).data);});password.value='';totp.value='';}
watch(()=>[props.suborderId,props.session.state.principal?.session_id],()=>{generation++;rows.value=[];error.value='';notice.value='';reasons.value={};actions.value={};password.value='';totp.value='';busy.value=false;if(props.session.state.principal?.session_id)load();},{immediate:true});
</script>
<template>
<section>
<h3>售后与平台介入</h3><p v-if="error" role="alert">{{ error }}</p><p v-if="notice" role="status">{{ notice }}</p><button :disabled="busy" @click="load">刷新售后记录</button>
<p v-if="!busy&&!rows.length">暂无售后申请</p>
<article v-for="a in rows" :key="a.id">
<p>{{ a.type==='REFUND_ONLY'?'仅退款':'退货退款' }} · {{ state(a.status) }} · 退款 {{ money(a.refund_amount_fen) }} · {{ refundState(a) }}</p>
<p>原因 {{ a.reason_code }} · {{ a.reason_text }}</p>
<p v-for="i in a.items" :key="i.id">{{ itemNames?.[i.order_item_id]??'商品' }} × {{ i.quantity }}</p>
<p v-for="e in a.evidence" :key="e.id">凭证：{{ e.content }}</p>
<p v-if="a.return_tracking_no">退货运单 {{ a.return_carrier_code }} · {{ a.return_tracking_no }}</p>
<p v-for="d in a.decisions" :key="d.id">平台裁决 {{ d.decision==='REFUND_APPROVED'?'支持退款':'驳回售后' }} · {{ money(d.amount_fen) }} · {{ d.reason }}</p>
<form v-if="realm==='merchant'&&session.can('aftersale.handle')&&a.status==='PENDING_MERCHANT'" @submit.prevent="decide(a)"><label>处理决定<select v-model="actions[a.id]" required><option value="" disabled>请选择</option><option v-if="a.type==='REFUND_ONLY'" value="APPROVE_REFUND">同意退款</option><option v-if="a.type==='RETURN_REFUND'" value="APPROVE_RETURN">同意退货</option><option value="REJECT">拒绝</option></select></label><label>处理说明<input v-model="reasons[a.id]" required maxlength="500" /></label><button :disabled="busy">提交决定</button></form>
<button v-if="realm==='merchant'&&session.can('aftersale.handle')&&a.status==='RETURN_IN_TRANSIT'" :disabled="busy" @click="arrival(a)">确认收到退货</button>
<form v-if="realm==='merchant'&&session.can('aftersale.handle')&&a.status==='WAITING_INSPECTION'" @submit.prevent="inspect(a)"><label>验收结论<select v-model="actions[a.id]" required><option value="" disabled>请选择</option><option value="ACCEPT">验收通过并退款</option><option value="REJECT">验收不通过</option></select></label><label>验收说明<input v-model="reasons[a.id]" required maxlength="500" /></label><button :disabled="busy">提交验收</button></form>
<form v-if="realm==='admin'&&session.can('aftersale.arbitrate')&&a.status==='PLATFORM_ESCALATED'" @submit.prevent="arbitrate(a)"><p>平台裁决需要再次验证，裁决后不可改判。</p><label>裁决<select v-model="actions[a.id]" required><option value="" disabled>请选择</option><option value="REFUND_APPROVED">支持退款</option><option value="REJECTED">驳回售后</option></select></label><label>裁决理由<input v-model="reasons[a.id]" required maxlength="500" /></label><label>核查密码<input v-model="password" type="password" autocomplete="current-password" required /></label><label>核查动态验证码<input v-model="totp" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" required /></label><button :disabled="busy">验证并裁决</button></form>
</article>
</section>
</template>
