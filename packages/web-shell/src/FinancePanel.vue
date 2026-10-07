<script setup lang="ts">
import {ref,onMounted,watch} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
const props=defineProps<{session:StaffSession}>();
type Summary=components['schemas']['FinanceSummary'];
type Entry=components['schemas']['LedgerEntry'];
type Batch=components['schemas']['SettlementSummary'];
type Track=components['schemas']['SettlementTrack'];
const summary=ref<Summary>(),entries=ref<Entry[]>([]),batches=ref<Batch[]>([]),tracks=ref<Track[]>([]),busy=ref(false),error=ref('');let generation=0;
function money(fen:number){return `¥${(fen/100).toFixed(2)}`;}
function entryLabel(value:string){return ({SALE_CREDIT:'销售入账',COMMISSION_DEBIT:'佣金扣减',REFUND_DEBIT:'退款冲销',COMMISSION_REVERSAL:'佣金返还',SHIPPING_ADJUSTMENT:'运费调整',SETTLEMENT_DEBIT:'结算出账',SETTLEMENT_ADJUSTMENT:'结算调整',MANUAL_ADJUSTMENT:'人工调整'} as Record<string,string>)[value]??value;}
function trackState(value:string){return ({WAITING_RECEIPT:'等待收货',BUFFERING:'售后缓冲中',FROZEN:'售后冻结',ELIGIBLE:'可结算',PROCESSING:'结算处理中',SETTLED:'已结算',ADJUSTED:'已冲正'} as Record<string,string>)[value]??'状态未知';}
function batchState(value:string){return ({PROCESSING:'出账处理中',SETTLED:'已结算',FAILED_RETRYABLE:'出账失败待重试'} as Record<string,string>)[value]??'状态未知';}
async function load(){const epoch=++generation,identity=props.session.state.principal?.session_id;busy.value=true;error.value='';
 try{const sum=unwrap(await props.session.client.api.GET('/merchant/finance-summary')).data;const entryRows=unwrap(await props.session.client.api.GET('/merchant/ledger',{params:{query:{limit:30}}})).data;const batchRows=unwrap(await props.session.client.api.GET('/merchant/settlements',{params:{query:{limit:20}}})).data;const trackRows=unwrap(await props.session.client.api.GET('/merchant/settlement-tracks',{params:{query:{limit:20}}})).data;
  if(epoch===generation&&identity===props.session.state.principal?.session_id){summary.value=sum;entries.value=entryRows;batches.value=batchRows;tracks.value=trackRows;}}catch(e){if(epoch===generation)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}}
watch(()=>props.session.state.principal?.session_id,()=>{generation++;summary.value=undefined;entries.value=[];batches.value=[];tracks.value=[];busy.value=false;error.value='';if(props.session.state.principal?.session_id)load();});onMounted(()=>{if(props.session.state.principal)load();});
</script>
<template>
<section>
<h3>资金概览</h3><p v-if="error" role="alert">{{ error }}</p><button class="secondary" :disabled="busy" @click="load()">刷新</button>
<div v-if="summary" class="cards"><article><h4>账面余额</h4><p class="large">{{ money(summary.balance_fen) }}</p></article><article><h4>可结算</h4><p class="large">{{ money(summary.eligible_fen) }}</p></article><article><h4>售后缓冲中</h4><p class="large">{{ money(summary.buffering_fen) }}</p></article><article><h4>结算在途</h4><p class="large">{{ money(summary.in_flight_fen) }}</p></article><article><h4>累计已结算</h4><p class="large">{{ money(summary.settled_total_fen) }}</p></article><article v-if="summary.receivable_fen>0"><h4>待补缴平台</h4><p class="large error">{{ money(summary.receivable_fen) }}</p></article></div>
<h3>结算批次</h3><table v-if="batches.length"><thead><tr><th>结算单号</th><th>金额</th><th>状态</th><th>到账时间</th></tr></thead><tbody><tr v-for="b in batches" :key="b.id"><td>{{ b.settlement_no }}</td><td>{{ money(b.amount_fen) }}</td><td>{{ batchState(b.status) }}</td><td>{{ b.settled_at??'—' }}</td></tr></tbody></table><p v-else-if="!busy">暂无结算批次</p>
<h3>结算轨道</h3><table v-if="tracks.length"><thead><tr><th>子订单</th><th>状态</th><th>净额</th><th>可结算时间</th></tr></thead><tbody><tr v-for="t in tracks" :key="t.id"><td>{{ t.suborder_id }}</td><td>{{ trackState(t.status) }}</td><td>{{ money(t.net_fen) }}</td><td>{{ t.eligible_at??'—' }}</td></tr></tbody></table><p v-else-if="!busy">暂无结算轨道</p>
<h3>账本明细</h3><table v-if="entries.length"><thead><tr><th>类型</th><th>方向</th><th>金额</th><th>原因</th><th>时间</th></tr></thead><tbody><tr v-for="e in entries" :key="e.id"><td>{{ entryLabel(e.entry_type) }}<template v-if="!e.affects_balance">（凭证）</template></td><td>{{ e.direction==='CREDIT'?'入账':'扣减' }}</td><td>{{ money(e.amount_fen) }}</td><td>{{ e.reason??'—' }}</td><td>{{ e.created_at }}</td></tr></tbody></table><p v-else-if="!busy">暂无账本条目</p>
</section>
</template>
