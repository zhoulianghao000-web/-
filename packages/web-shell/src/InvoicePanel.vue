<script setup lang="ts">
import {onMounted,onBeforeUnmount,ref,watch} from 'vue';
import {unwrap,mutationHeaders,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
type Invoice=components['schemas']['InvoiceApplication'];
const props=defineProps<{session:StaffSession;realm:'merchant'|'admin'}>();
const rows=ref<Invoice[]>([]),selected=ref<Invoice|null>(null),error=ref(''),busy=ref(false),password=ref(''),reason=ref(''),decision=ref<'ACCEPTED'|'REJECTED'>('ACCEPTED'),cursor=ref<string|null>(null);
const labels={REQUESTED:'待商家处理',ACCEPTED:'商家已受理',REJECTED:'商家已拒绝'};
let generation=0;const keys=new Map<string,string>();
function stamp(){const g=generation,s=props.session.state.principal?.session_id,store=props.session.state.storeId;return ()=>g===generation&&s===props.session.state.principal?.session_id&&store===props.session.state.storeId;}
function clear(){generation++;rows.value=[];selected.value=null;password.value='';reason.value='';error.value='';busy.value=false;cursor.value=null;keys.clear();}
async function load(more=false){if(busy.value)return;const current=stamp();busy.value=true;error.value='';try{const r=unwrap(await props.session.client.api.GET(`/${props.realm}/invoices`,{params:{query:{limit:50,...(more&&cursor.value?{cursor:cursor.value}:{})}}}));if(current()){rows.value=more?[...rows.value,...r.data]:r.data;cursor.value=r.page.next_cursor;}}catch(e){if(current())error.value=explainError(e);}finally{if(current())busy.value=false;}}
async function detail(row:Invoice){generation++;const current=stamp();selected.value=null;password.value='';reason.value='';error.value='';try{const r=unwrap(await props.session.client.api.GET(`/${props.realm}/invoices/{application}`,{params:{path:{application:row.id}}}));if(current())selected.value=r.data;}catch(e){if(current())error.value=explainError(e);}}
async function handle(){const row=selected.value;if(!row||props.realm!=='merchant'||busy.value)return;busy.value=true;error.value='';const current=stamp();const body={status:decision.value,reason:reason.value.trim()};const fingerprint=JSON.stringify([row.id,row.version,body]);const key=keys.get(fingerprint)??crypto.randomUUID();keys.set(fingerprint,key);try{const proof=await props.session.client.reverify({action:'invoice.handle',password:password.value});password.value='';if(!current())return;const result=unwrap(await props.session.client.api.POST('/merchant/invoices/{application}/decision',{params:{path:{application:row.id},header:mutationHeaders(key,proof.reverify_token,row.version)},body}));if(current()){selected.value=result.data;keys.delete(fingerprint);rows.value=rows.value.map(r=>r.id===row.id?result.data:r);reason.value='';}}catch(e){if(current())error.value=explainError(e);}finally{password.value='';if(current())busy.value=false;}}
watch(()=>[props.session.state.principal?.session_id,props.session.state.storeId],()=>{clear();void load();});onMounted(()=>void load());onBeforeUnmount(clear);
</script>
<template>
<section>
<div class="page-header"><h1>发票申请</h1><button class="secondary" :disabled="busy" @click="load()">刷新</button></div><p>申请按子订单交给对应商家。受理不代表已开具税务发票；当前模拟环境不会开票或发送邮件。</p><p v-if="error" role="alert" class="error">{{ error }}</p><p v-if="busy" role="status">处理中…</p><p v-if="!busy&&!rows.length">暂无可访问的申请。</p>
<div class="cards"><article v-for="row in rows" :key="row.id"><h2>{{ row.merchant_name }}</h2><p>子订单 {{ row.suborder_no }}</p><p>{{ labels[row.status] }}</p><button class="secondary" @click="detail(row)">查看申请</button></article></div><button v-if="cursor" class="secondary" :disabled="busy" @click="load(true)">加载更多</button>
<article v-if="selected" class="invoice-detail">
<h2>申请详情</h2><p>{{ selected.issuer_notice }}</p><dl><dt>状态</dt><dd>{{ labels[selected.status] }}</dd><dt>类型</dt><dd>{{ selected.title_type==='PERSONAL'?'个人':'企业' }}</dd><template v-if="selected.title"><dt>抬头</dt><dd>{{ selected.title }}</dd><dt>税号</dt><dd>{{ selected.tax_number??'不适用' }}</dd><dt>邮箱</dt><dd>{{ selected.email }}</dd></template><dt>处理说明</dt><dd>{{ selected.reason??'待处理' }}</dd></dl>
<form v-if="realm==='merchant'&&session.can('invoice.handle')&&selected.status==='REQUESTED'" @submit.prevent="handle"><label>处理结果<select v-model="decision" :disabled="busy"><option value="ACCEPTED">受理申请</option><option value="REJECTED">拒绝申请</option></select></label><label>处理说明<textarea v-model="reason" required maxlength="500" :disabled="busy" /></label><label>确认账号密码<input v-model="password" type="password" autocomplete="current-password" required :disabled="busy"></label><button :disabled="busy">确认处理</button></form>
</article>
</section>
</template>
<style scoped>.invoice-detail{margin-top:24px;padding:24px;border:1px solid var(--line,#ddd);border-radius:20px}dl{display:grid;grid-template-columns:96px minmax(0,1fr);gap:16px}dd{margin:0;overflow-wrap:anywhere}form{max-width:560px;display:grid;gap:20px;margin-top:24px}label{display:grid;gap:8px}textarea{min-height:96px}</style>
