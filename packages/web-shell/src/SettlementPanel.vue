<script setup lang="ts">
import {ref,onMounted,watch} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
const props=defineProps<{session:StaffSession}>();
type Batch=components['schemas']['SettlementSummary'];
type Track=components['schemas']['SettlementTrack'];
type Reconciliation=components['schemas']['ReconciliationReport'];
const batches=ref<Batch[]>([]),tracks=ref<Track[]>([]),reconciliation=ref<Reconciliation>(),trackStatus=ref(''),merchantId=ref(''),password=ref(''),totp=ref(''),busy=ref(false),error=ref(''),notice=ref('');let generation=0;const keys=new Map<string,string>();
function keyFor(payload:string){const existing=keys.get(payload);if(existing)return existing;const created=crypto.randomUUID();keys.set(payload,created);return created;}
function money(fen:number){return `¥${(fen/100).toFixed(2)}`;}
function batchState(value:string){return ({PROCESSING:'出账处理中',SETTLED:'已结算',FAILED_RETRYABLE:'出账失败待重试'} as Record<string,string>)[value]??'状态未知';}
function trackState(value:string){return ({WAITING_RECEIPT:'等待收货',BUFFERING:'售后缓冲中',FROZEN:'售后冻结',ELIGIBLE:'可结算',PROCESSING:'结算处理中',SETTLED:'已结算',ADJUSTED:'已冲正'} as Record<string,string>)[value]??'状态未知';}
async function load(){const epoch=++generation,identity=props.session.state.principal?.session_id;busy.value=true;error.value='';
 try{const query:{limit:number;status?:'PROCESSING'|'SETTLED'|'FAILED_RETRYABLE'}={limit:20};const batchRows=unwrap(await props.session.client.api.GET('/admin/settlements',{params:{query}})).data;
  const trackQuery:{limit:number;status?:'WAITING_RECEIPT'|'BUFFERING'|'FROZEN'|'ELIGIBLE'|'PROCESSING'|'SETTLED'|'ADJUSTED'}={limit:20};if(trackStatus.value)trackQuery.status=trackStatus.value as never;
  const trackRows=unwrap(await props.session.client.api.GET('/admin/settlement-tracks',{params:{query:trackQuery}})).data;
  const report=unwrap(await props.session.client.api.GET('/admin/finance/reconciliation')).data;
  if(epoch===generation&&identity===props.session.state.principal?.session_id){batches.value=batchRows;tracks.value=trackRows;reconciliation.value=report;}}catch(e){if(epoch===generation)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}}
async function withReverify(action:'settlement.execute',work:(proof:string)=>Promise<void>){if(busy.value)return;busy.value=true;error.value='';notice.value='';
 try{const proof=await props.session.client.reverify({action,password:password.value,totp_code:totp.value});await work(proof.reverify_token);await load();}catch(e){error.value=explainError(e);}finally{password.value='';totp.value='';busy.value=false;}}
async function initiate(){const id=merchantId.value.trim();await withReverify('settlement.execute',async proof=>{await unwrap(await props.session.client.api.POST('/admin/merchants/{id}/settlements',{params:{path:{id},header:{'Idempotency-Key':keyFor(`initiate:${id}`),'X-Reverify-Token':proof}},body:{}}));notice.value='结算批次已创建并出账。';});}
async function retry(id:string){await withReverify('settlement.execute',async proof=>{await unwrap(await props.session.client.api.POST('/admin/settlements/{id}/retry',{params:{path:{id},header:{'Idempotency-Key':keyFor(`retry:${id}`),'X-Reverify-Token':proof}},body:{}}));notice.value='已重新发起出账。';});}
watch(()=>props.session.state.principal?.session_id,()=>{generation++;batches.value=[];tracks.value=[];reconciliation.value=undefined;merchantId.value='';password.value='';totp.value='';keys.clear();busy.value=false;error.value='';notice.value='';});onMounted(load);
</script>
<template>
<section>
<h3>结算批次</h3><p v-if="error" role="alert">{{ error }}</p><p v-if="notice" role="status">{{ notice }}</p>
<p v-if="reconciliation">对账门禁：<strong :class="reconciliation.consistent?'ok':'error'">{{ reconciliation.consistent?'一致':'存在差异' }}</strong><template v-for="check in reconciliation.checks" :key="check.name"> · {{ check.name }} {{ check.mismatches===0?'✓':`差异 ${check.mismatches}` }}</template></p>
<table v-if="batches.length"><thead><tr><th>结算单号</th><th>金额</th><th>状态</th><th>时间</th><th></th></tr></thead><tbody><tr v-for="b in batches" :key="b.id"><td>{{ b.settlement_no }}</td><td>{{ money(b.amount_fen) }}</td><td>{{ batchState(b.status) }}<template v-if="b.last_error_code"> · {{ b.last_error_code }}</template></td><td>{{ b.settled_at??b.created_at }}</td><td><button v-if="b.status==='FAILED_RETRYABLE'" class="secondary" :disabled="busy" @click="retry(b.id)">重试出账</button></td></tr></tbody></table><p v-else-if="!busy">暂无结算批次</p>
<form class="confirm-card" @submit.prevent="initiate"><h4>发起商家结算</h4><label>商家编号<input v-model="merchantId" required minlength="36" maxlength="36" :disabled="busy" /></label><label>再次输入密码<input v-model="password" type="password" autocomplete="current-password" :disabled="busy" required /></label><label>新的动态验证码<input v-model="totp" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" :disabled="busy" required /></label><button :disabled="busy" type="submit">验证并发起结算</button></form>
<h3>结算轨道</h3><label>状态筛选<select v-model="trackStatus" @change="load()"><option value="">全部</option><option value="BUFFERING">售后缓冲中</option><option value="FROZEN">售后冻结</option><option value="ELIGIBLE">可结算</option><option value="SETTLED">已结算</option><option value="ADJUSTED">已冲正</option></select></label><button class="secondary" :disabled="busy" @click="load()">刷新</button>
<table v-if="tracks.length"><thead><tr><th>子订单</th><th>状态</th><th>净额</th><th>缓冲天数</th><th>可结算时间</th></tr></thead><tbody><tr v-for="t in tracks" :key="t.id"><td>{{ t.suborder_id }}</td><td>{{ trackState(t.status) }}</td><td>{{ money(t.net_fen) }}</td><td>{{ t.buffer_days??'—' }}</td><td>{{ t.eligible_at??'—' }}</td></tr></tbody></table><p v-else-if="!busy">暂无结算轨道</p>
</section>
</template>
