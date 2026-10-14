<script setup lang="ts">
import {computed,onUnmounted,ref,watch} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {explainError,StaffSession} from './auth';
import {quotationPlot} from './price-history';
const props=defineProps<{offerId:string;realm:'merchant'|'admin';session:StaffSession}>();
const days=ref<30|90>(30),data=ref<components['schemas']['OfferPriceHistory']>(),loading=ref(false),error=ref('');
let generation=0;
const sale=computed(()=>quotationPlot(data.value?.points??[])),member=computed(()=>quotationPlot(data.value?.points??[],true));
const money=(n:number|null)=>n===null?'未采集':`¥${(n/100).toFixed(2)}`;
async function load(){
 const g=++generation;data.value=undefined;error.value='';loading.value=true;
 try{
  const params={path:{id:props.offerId},query:{days:days.value}};
  const result=props.realm==='merchant'?unwrap(await props.session.client.api.GET('/merchant/offers/{id}/price-history',{params})):unwrap(await props.session.client.api.GET('/admin/offers/{id}/price-history',{params}));
  if(g===generation)data.value=result.data;
 }catch(e){if(g===generation)error.value=explainError(e);}finally{if(g===generation)loading.value=false;}
}
watch(()=>[props.offerId,days.value,props.session.state.principal?.session_id,props.session.state.storeId],load,{immediate:true});
onUnmounted(()=>generation++);
</script>
<template>
 <article aria-label="价格记录" class="price-history-panel" style="margin-top:24px">
  <div class="page-heading"><div><p class="eyebrow">PRICE RECORDS</p><h2>价格记录</h2></div><label>查看范围<select v-model="days"><option :value="30">30 天</option><option :value="90">90 天</option></select></label></div>
  <p class="muted">同一商家、门店和规格的上海日历日末商品报价。不含运费、优惠券或结账实付。管理端包含未上架记录，销售状态另行标明。</p>
  <p v-if="loading" role="status">正在加载价格记录…</p>
  <p v-if="error" role="alert" class="error">{{ error }}</p><button v-if="error" class="secondary" @click="load">重试价格记录</button>
  <template v-if="data">
   <p>{{ data.from_date }} — {{ data.to_date }} · 已记录 {{ data.observed_days }} / {{ data.days }} 天</p>
   <p v-if="data.observed_days<2">价格记录不足，暂不足以形成趋势。未采集的日期留空。</p>
   <p>已记录日末最低 {{ money(data.lowest_recorded_daily_sale_price_fen) }} · 最高 {{ money(data.highest_recorded_daily_sale_price_fen) }}</p>
   <svg v-if="data.observed_days" viewBox="0 0 600 180" role="img" aria-label="报价曲线，详细数值可通过查看逐日记录读取" style="display:block;width:100%;max-height:200px">
    <title>日末商品报价，缺失时不连线</title><path v-for="n in [10,60,110,170]" :key="n" :d="`M10,${n} L590,${n}`" stroke="#e8e5dc" />
    <g fill="none" stroke="#466a50" stroke-width="2"><path v-for="(path,i) in sale.paths" :key="i" :d="path" /></g><circle v-for="(dot,i) in sale.dots" :key="`s${i}`" :cx="dot.x" :cy="dot.y" r="3" fill="#466a50" />
    <g fill="none" stroke="#d7784f" stroke-width="2"><path v-for="(path,i) in member.paths" :key="i" :d="path" /></g><circle v-for="(dot,i) in member.dots" :key="`m${i}`" :cx="dot.x" :cy="dot.y" r="3" fill="#d7784f" />
   </svg>
   <p class="muted">绿色：普通商品标价 · 橙色：会员标价。会员标价需符合会员资格。</p>
   <details><summary>查看逐日记录</summary><div class="table-wrap"><table><thead><tr><th>上海日期</th><th>普通标价</th><th>会员标价</th><th>当时状态</th><th>当时公开</th><th>实际记录时间</th></tr></thead><tbody><tr v-for="p in [...data.points].reverse()" :key="p.date"><td>{{ p.date }}</td><td>{{ money(p.sale_price_fen) }}</td><td>{{ p.member_price_fen===null?'无会员标价':money(p.member_price_fen) }}</td><td>{{ p.sale_status??'未采集' }}</td><td>{{ p.publicly_recorded===null?'未采集':p.publicly_recorded?'是':'否' }}</td><td>{{ p.recorded_at??'—' }}</td></tr></tbody></table></div></details>
  </template>
 </article>
</template>
