<script setup lang="ts">
import {onMounted,onBeforeUnmount,ref,watch} from 'vue';
import {unwrap,mutationHeaders,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
type Request=components['schemas']['PurchaseRequest'];
const props=defineProps<{session:StaffSession}>();
const rows=ref<Request[]>([]),selected=ref<Request|null>(null),busy=ref(false),error=ref(''),password=ref(''),response=ref(''),decision=ref<'REVIEWING'|'RESOLVED'|'REJECTED'>('REVIEWING'),status=ref<Request['status']|''>(''),cursor=ref<string|null>(null);
const labels={OPEN:'待查看',REVIEWING:'处理中',RESOLVED:'已答复',REJECTED:'暂不受理',CANCELLED:'已撤回'};
let generation=0;const keys=new Map<string,string>();
function stamp(){const g=generation,s=props.session.state.principal?.session_id;return ()=>g===generation&&s===props.session.state.principal?.session_id;}
function clear(){generation++;rows.value=[];selected.value=null;password.value='';response.value='';cursor.value=null;error.value='';busy.value=false;keys.clear();}
async function load(more=false){if(busy.value||!props.session.can('purchase-request.read'))return;const current=stamp();busy.value=true;error.value='';try{const r=unwrap(await props.session.client.api.GET('/admin/purchase-requests',{params:{query:{limit:50,...(status.value?{status:status.value}:{}),...(more&&cursor.value?{cursor:cursor.value}:{})}}}));if(current()){rows.value=more?[...rows.value,...r.data]:r.data;cursor.value=r.page.next_cursor;}}catch(e){if(current())error.value=explainError(e);}finally{if(current())busy.value=false;}}
async function detail(row:Request){generation++;const current=stamp();selected.value=null;password.value='';response.value='';error.value='';try{const r=unwrap(await props.session.client.api.GET('/admin/purchase-requests/{id}',{params:{path:{id:row.id}}}));if(current()){selected.value=r.data;decision.value=row.status==='REVIEWING'?'RESOLVED':'REVIEWING';}}catch(e){if(current())error.value=explainError(e);}}
async function handle(){const row=selected.value;if(!row||busy.value)return;busy.value=true;error.value='';const current=stamp(),body={status:decision.value,response:response.value.trim()},fingerprint=JSON.stringify([row.id,row.version,body]),key=keys.get(fingerprint)??crypto.randomUUID();keys.set(fingerprint,key);try{const proof=await props.session.client.reverify({action:'purchase-request.manage',password:password.value});password.value='';if(!current())return;unwrap(await props.session.client.api.POST('/admin/purchase-requests/{id}/decision',{params:{path:{id:row.id},header:mutationHeaders(key,proof.reverify_token,row.version)},body}));if(current()){keys.delete(fingerprint);selected.value=null;response.value='';busy.value=false;await load();}}catch(e){if(current())error.value=explainError(e);}finally{password.value='';if(current())busy.value=false;}}
watch(()=>props.session.state.principal?.session_id,()=>{clear();void load();});onMounted(()=>void load());onBeforeUnmount(clear);
</script>
<template>
<section>
<div class="page-header"><h1>用户求购</h1><button class="secondary" :disabled="busy" @click="load()">刷新</button></div><p>查看和答复用户找不到的商品需求。求购不构成采购、到货或价格承诺；运营通知暂留白，用户在自己的求购页查看进度。</p>
<label class="request-filter">处理状态<select v-model="status" :disabled="busy" @change="selected=null;load()"><option value="">全部</option><option v-for="(label,value) in labels" :key="value" :value="value">{{ label }}</option></select></label><p v-if="error" role="alert" class="error">{{ error }}</p><p v-if="busy" role="status">处理中…</p><p v-if="!busy&&!rows.length">暂无符合条件的求购。</p>
<div class="cards"><article v-for="row in rows" :key="row.id"><h2>{{ row.title }}</h2><p>{{ labels[row.status] }}</p><p>{{ row.created_at.slice(0,10) }}</p><button class="secondary" @click="detail(row)">查看求购</button></article></div><button v-if="cursor" class="secondary" :disabled="busy" @click="load(true)">加载更多</button>
<article v-if="selected" class="request-detail">
<h2>{{ selected.title }}</h2><p>{{ labels[selected.status] }}</p><p class="request-text">{{ selected.description||'没有补充需求' }}</p><h3>原搜索条件</h3><dl><template v-for="(value,key) in selected.search_context" :key="key"><dt>{{ key }}</dt><dd>{{ value }}</dd></template></dl><p v-if="selected.response" class="request-text">平台答复：{{ selected.response }}</p>
<form v-if="session.can('purchase-request.manage')&&['OPEN','REVIEWING'].includes(selected.status)" @submit.prevent="handle"><label>处理结果<select v-model="decision" :disabled="busy"><option v-if="selected.status==='OPEN'" value="REVIEWING">开始处理</option><option value="RESOLVED">完成答复</option><option value="REJECTED">暂不受理</option></select></label><label>给用户的答复<textarea v-model="response" required maxlength="500" :disabled="busy" /></label><label>确认账号密码<input v-model="password" type="password" autocomplete="current-password" required :disabled="busy"></label><button :disabled="busy">确认处理</button></form>
</article>
</section>
</template>
<style scoped>.request-detail{margin-top:24px;padding:24px;border:1px solid var(--line);border-radius:20px}.request-text{white-space:pre-wrap;overflow-wrap:anywhere}dl{display:grid;grid-template-columns:minmax(96px,1fr) minmax(0,2fr);gap:16px}dt,dd{margin:0;overflow-wrap:anywhere}form{max-width:560px;display:grid;gap:20px;margin-top:24px}label{display:grid;gap:8px}.request-filter{max-width:320px;margin-block:24px}textarea{min-height:112px}</style>
