<script setup lang="ts">
import {onBeforeUnmount,onMounted,ref,watch} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
import {analyticsMoney as money} from './business-analytics';
const props=defineProps<{session:StaffSession;realm:'merchant'|'admin'}>();
type Overview=components['schemas']['BusinessAnalytics'];
const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const from=ref(today),to=ref(today),merchant=ref(''),store=ref(''),result=ref<Overview>(),busy=ref(false),error=ref('');let generation=0;
function clear(){generation++;result.value=undefined;busy.value=false;error.value='';}
async function load(){
 clear();const epoch=generation,identity=props.session.state.principal?.session_id;
 if(!identity)return;
 if(props.realm==='admin'&&!/^[0-9a-f-]{36}$/i.test(merchant.value)){error.value='请选择商户，填写有效商户编号。';return;}
 busy.value=true;
 try{
  // Refresh identity and store scope before each query; the server applies both permissions again.
  await props.session.refreshIdentity();if(epoch!==generation||identity!==props.session.state.principal?.session_id)return;
  const query={from:from.value,to:to.value,...(store.value?{store_id:store.value}:{})};
  const data=props.realm==='merchant'?unwrap(await props.session.client.api.GET('/merchant/business-analytics',{params:{query}})).data:unwrap(await props.session.client.api.GET('/admin/merchants/{id}/business-analytics',{params:{path:{id:merchant.value},query}})).data;
  if(epoch===generation&&identity===props.session.state.principal?.session_id)result.value=data;
 }catch(e){if(epoch===generation&&identity===props.session.state.principal?.session_id)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}
}
watch([from,to,merchant,store,()=>props.session.state.principal?.session_id],clear,{flush:'sync'});
watch(()=>props.session.state.stores.map(x=>x.id).join(','),()=>{if(store.value&&!props.session.state.stores.some(x=>x.id===store.value)){store.value='';clear();}});
onBeforeUnmount(clear);onMounted(()=>{if(props.realm==='merchant')void load();});
</script>
<template>
 <section class="business-analytics">
<h1>经营分析</h1><p>按上海日期统计已记账事实，退款在发生日回冲。金额包含运费与优惠后的支付入账，不代表利润或可提余额。</p>
 <form class="analytics-filters" @submit.prevent="load"><label v-if="realm==='admin'">商户编号<input v-model.trim="merchant" autocomplete="off" /></label><label>开始日期<input v-model="from" type="date" :max="today" required /></label><label>结束日期<input v-model="to" type="date" :max="today" required /></label><label v-if="realm==='merchant'">统计门店<select v-model="store"><option value="">全部授权范围</option><option v-for="s in session.state.stores" :key="s.id" :value="s.id">{{ s.name }}</option></select></label><label v-else>门店编号（可选）<input v-model.trim="store" autocomplete="off" /></label><button :disabled="busy">{{ busy?'查询中…':'查询经营分析' }}</button></form>
 <p role="note">最多90天；仅计完整授权的子订单。单店查询不包含混店子订单，避免重复统计或推定运费分摊。</p><p v-if="error" role="alert">{{ error }}</p>
 <template v-if="result">
<p v-if="result.simulated" class="pilot-banner">模拟经营数据 · 不发生真实交易</p><p>统计截至 {{ result.as_of }} · {{ result.timezone }}</p>
 <div class="cards"><article><h2>支付入账</h2><p class="large">{{ money(result.totals.paid_fen) }}</p><small>{{ result.totals.paid_suborders }} 笔子订单</small></article><article><h2>成功退款</h2><p class="large">{{ money(result.totals.refund_fen) }}</p><small>{{ result.totals.refund_count }} 笔退款</small></article><article><h2>收退款净额</h2><p class="large">{{ money(result.totals.net_fen) }}</p></article><article><h2>佣金净扣减</h2><p class="large">{{ money(result.totals.commission_net_fen) }}</p></article><article><h2>扣佣后经营净额</h2><p class="large">{{ money(result.totals.merchant_net_fen) }}</p></article></div>
 <p v-if="result.totals.paid_suborders===0&&result.totals.refund_count===0">所选范围暂无支付或退款记账事实。</p>
 <div class="analytics-table"><table><caption>逐日经营记账（元）</caption><thead><tr><th scope="col">日期</th><th scope="col">子订单</th><th scope="col">支付</th><th scope="col">退款</th><th scope="col">净额</th><th scope="col">净佣金</th></tr></thead><tbody><tr v-for="day in result.days" :key="day.date"><th scope="row">{{ day.date }}</th><td>{{ day.metrics.paid_suborders }}</td><td>{{ money(day.metrics.paid_fen) }}</td><td>{{ money(day.metrics.refund_fen) }}</td><td>{{ money(day.metrics.net_fen) }}</td><td>{{ money(day.metrics.commission_net_fen) }}</td></tr></tbody></table></div>
 </template>
</section>
</template>
<style scoped>
.analytics-filters{display:flex;flex-wrap:wrap;gap:16px;align-items:end;margin:24px 0}.analytics-filters label{display:grid;gap:8px;min-width:160px}.analytics-filters input,.analytics-filters select{min-height:44px}.analytics-table{overflow-x:auto;margin-top:24px}.analytics-table table{min-width:640px}.business-analytics .cards{margin-top:20px}
</style>
