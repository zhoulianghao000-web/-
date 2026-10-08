<script setup lang="ts">
import {ref,watch} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
const props=defineProps<{session:StaffSession;paymentId:string}>();
const payment=ref<components['schemas']['PaymentDetail']>(),busy=ref(false),error=ref(''),password=ref(''),totp=ref(''),notice=ref('');let generation=0,key='';
function status(value:string){return ({PENDING:'待付款',PROCESSING:'支付结果确认中',SUCCEEDED:'已付款',CLOSED:'已关闭'} as Record<string,string>)[value]??'结果未知';}
async function load(){if(busy.value)return;const epoch=++generation,identity=props.session.state.principal?.session_id,id=props.paymentId;busy.value=true;error.value='';try{const value=unwrap(await props.session.client.api.GET('/admin/payments/{id}',{params:{path:{id}}})).data;if(epoch===generation&&identity===props.session.state.principal?.session_id)payment.value=value;}catch(e){if(epoch===generation)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}}
async function requery(){if(busy.value)return;const epoch=++generation,identity=props.session.state.principal?.session_id,id=props.paymentId;busy.value=true;error.value='';notice.value='';if(!key)key=crypto.randomUUID();try{const proof=await props.session.client.reverify({action:'payment.requery',password:password.value,totp_code:totp.value});if(epoch!==generation||identity!==props.session.state.principal?.session_id)return;const value=unwrap(await props.session.client.api.POST('/admin/payments/{id}/requery',{params:{path:{id},header:{'Idempotency-Key':key,'X-Reverify-Token':proof.reverify_token}}})).data;if(epoch===generation&&identity===props.session.state.principal?.session_id){payment.value=value;notice.value='已核查支付并恢复待人工处理的退款，请刷新退款台账查看结果';key='';}}catch(e){if(epoch===generation)error.value=explainError(e);}finally{password.value='';totp.value='';if(epoch===generation)busy.value=false;}}
watch(()=>[props.paymentId,props.session.state.principal?.session_id],()=>{generation++;payment.value=undefined;error.value='';notice.value='';password.value='';totp.value='';busy.value=false;key='';if(props.session.state.principal?.session_id)load();},{immediate:true});
</script>
<template>
 <section>
  <h3>支付核对</h3><p v-if="error" role="alert">{{ error }}</p><p v-if="notice" role="status">{{ notice }}</p><p v-if="busy">正在查询支付事实…</p>
  <template v-if="payment"><p>{{ status(payment.status) }} · {{ payment.simulation?'开发环境模拟支付':'渠道支付' }} · 应付 ¥{{ (payment.amount_fen/100).toFixed(2) }}</p><p v-if="payment.final_channel">成功渠道 {{ payment.final_channel==='WECHAT'?'微信':'支付宝' }}</p><p v-for="a in payment.attempts" :key="a.id">{{ a.channel==='WECHAT'?'微信':'支付宝' }} · {{ a.status==='CHANNEL_SUCCEEDED'?'渠道确认成功':a.status==='CANCELLED'?'已安全关闭':a.status==='CHANNEL_FAILED'?'渠道失败':a.status==='UNKNOWN'?'结果未知':'等待渠道结果' }}</p><p v-for="c in payment.cases" :key="c.id">异常收款 · {{ c.status==='REFUNDED'?'已原路补偿':c.status==='NEEDS_REVIEW'?'超限待人工核查':'补偿处理中' }}</p></template>
  <button :disabled="busy" @click="load">刷新支付记录</button>
  <form v-if="session.can('payment.requery')" @submit.prevent="requery"><p>核对渠道结果、恢复待人工处理的退款和异常补偿，需要再次验证。</p><label>核查密码<input v-model="password" type="password" autocomplete="current-password" required /></label><label>核查动态验证码<input v-model="totp" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" required /></label><button :disabled="busy">验证并核查支付</button></form>
 </section>
</template>
