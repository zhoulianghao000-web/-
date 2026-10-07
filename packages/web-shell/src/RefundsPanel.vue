<script setup lang="ts">
import {ref,watch,onMounted} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
const props=defineProps<{session:StaffSession}>();
type Refund=components['schemas']['RefundAdmin'];
const rows=ref<Refund[]>([]),cursor=ref<string>(),status=ref(''),busy=ref(false),error=ref('');let generation=0;
function money(fen:number){return `¥${(fen/100).toFixed(2)}`;}
function state(value:string){return ({CREATED:'待发起',PROCESSING:'退款处理中',SUCCEEDED:'退款成功',FAILED_RETRYABLE:'重试中',FAILED_FINAL:'待人工处理',CANCELLED:'已作废'} as Record<string,string>)[value]??'状态未知';}
async function load(more=false){if(busy.value)return;const epoch=++generation,identity=props.session.state.principal?.session_id;busy.value=true;error.value='';if(!more)rows.value=[];try{const query:{limit:number;cursor?:string;status?:'CREATED'|'PROCESSING'|'SUCCEEDED'|'FAILED_RETRYABLE'|'FAILED_FINAL'|'CANCELLED'}={limit:20,...(more&&cursor.value?{cursor:cursor.value}:{})};if(status.value)query.status=status.value as never;const result=unwrap(await props.session.client.api.GET('/admin/refunds',{params:{query}}));if(epoch===generation&&identity===props.session.state.principal?.session_id){rows.value.push(...result.data);cursor.value=result.page.next_cursor??undefined;}}catch(e){if(epoch===generation)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}}
watch(()=>props.session.state.principal?.session_id,()=>{generation++;rows.value=[];cursor.value=undefined;error.value='';busy.value=false;if(props.session.state.principal?.session_id)load();});onMounted(()=>{if(props.session.state.principal)load();});
</script>
<template>
<section>
<h3>退款台账</h3><p v-if="error" role="alert">{{ error }}</p>
<label>状态筛选<select v-model="status" @change="load()"><option value="">全部</option><option value="SUCCEEDED">退款成功</option><option value="PROCESSING">退款处理中</option><option value="FAILED_RETRYABLE">重试中</option><option value="FAILED_FINAL">待人工处理</option></select></label><button :disabled="busy" @click="load()">刷新退款</button>
<p v-if="!busy&&!rows.length">暂无退款记录</p>
<table v-if="rows.length"><thead><tr><th>退款单号</th><th>金额</th><th>状态</th><th>渠道凭证</th></tr></thead><tbody><tr v-for="r in rows" :key="r.id"><td>{{ r.refund_no }}</td><td>{{ money(r.amount_fen) }} {{ r.currency }}</td><td>{{ state(r.status) }}<template v-if="r.last_error_code"> · {{ r.last_error_code }}</template></td><td>{{ r.channel_refund_no??'—' }}</td></tr></tbody></table>
<button v-if="cursor" :disabled="busy" @click="load(true)">加载更多</button>
</section>
</template>
