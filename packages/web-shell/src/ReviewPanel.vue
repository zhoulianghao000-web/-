<script setup lang="ts">
import {ref,onMounted,watch} from 'vue';
import {unwrap,mutationHeaders,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
import PublicationMedia from './PublicationMedia.vue';
const props=defineProps<{session:StaffSession;realm:'merchant'|'admin'}>();
type Review=components['schemas']['ReviewDetail']|components['schemas']['PublicReview'];
const rows=ref<Review[]>([]),selected=ref<components['schemas']['ReviewDetail']|null>(null),policies=ref<components['schemas']['ReviewRewardPolicy'][]>([]);
const busy=ref(false),error=ref(''),notice=ref(''),reason=ref(''),password=ref(''),totp=ref(''),cursor=ref<string|null>(null),base=ref(10),bonus=ref(5),strategy=ref<'PROPORTIONAL_GOODS'|'NONE'>('PROPORTIONAL_GOODS');
let generation=0;const keys=new Map<string,string>();
function key(payload:string){let value=keys.get(payload);if(!value){value=crypto.randomUUID();keys.set(payload,value);}return value;}
function fence(){const gen=generation,id=props.session.state.principal?.session_id,store=props.session.state.storeId;return ()=>gen===generation&&id===props.session.state.principal?.session_id&&store===props.session.state.storeId;}
async function load(more=false){if(busy.value)return;const current=fence();busy.value=true;error.value='';try{
 const query={limit:20,...(more&&cursor.value?{cursor:cursor.value}:{})};const api=props.session.client.api;
 if(props.realm==='merchant'&&!props.session.state.storeId){rows.value=[];return;}
 const result=props.realm==='admin'?unwrap(await api.GET('/admin/reviews',{params:{query}})):unwrap(await api.GET('/merchant/reviews',{params:{query:{...query,store_id:props.session.state.storeId}}}));
 if(current()){rows.value=more?[...rows.value,...result.data]:result.data;cursor.value=result.page.next_cursor??null;}
 if(props.realm==='admin'){const p=unwrap(await api.GET('/admin/review-reward-policies')).data;if(current())policies.value=p;}
 }catch(e){if(current())error.value=explainError(e);}finally{if(current())busy.value=false;}}
async function select(id:string){const current=fence();try{const value=unwrap(await props.session.client.api.GET('/admin/reviews/{id}',{params:{path:{id}}})).data;if(current()){selected.value=value;reason.value='';}}catch(e){if(current())error.value=explainError(e);}}
async function moderate(decision:'APPROVE'|'REJECT'|'HIDE'){if(!selected.value||busy.value||!reason.value.trim())return;const r=selected.value,current=fence(),body={decision,reason:reason.value};busy.value=true;error.value='';try{
 const proof=await props.session.client.reverify({action:'review.moderate',password:password.value,totp_code:totp.value});if(!current())return;
 const result=unwrap(await props.session.client.api.POST('/admin/reviews/{id}/moderation',{params:{path:{id:r.id},header:mutationHeaders(key(`${r.id}:${r.version}:${JSON.stringify(body)}`),proof.reverify_token,r.version)},body})).data;
 if(current()){selected.value=result;notice.value='审核结果已保存';}
 }catch(e){if(current())error.value=explainError(e);}finally{if(current()){password.value='';totp.value='';busy.value=false;}}}
async function publishPolicy(){if(busy.value)return;const current=fence(),body={base_points:base.value,media_bonus_points:bonus.value,refund_strategy:strategy.value};busy.value=true;error.value='';try{
 const proof=await props.session.client.reverify({action:'review.policy.manage',password:password.value,totp_code:totp.value});if(!current())return;
 const p=unwrap(await props.session.client.api.POST('/admin/review-reward-policies',{params:{header:mutationHeaders(key(`policy:${JSON.stringify(body)}`),proof.reverify_token)},body})).data;if(current()){policies.value=[p,...policies.value];notice.value='新规则已发布，已领取订单的规则保持冻结';}
 }catch(e){if(current())error.value=explainError(e);}finally{if(current()){password.value='';totp.value='';busy.value=false;}}}
watch(()=>[props.session.state.principal?.session_id,props.session.state.storeId],()=>{generation++;rows.value=[];selected.value=null;policies.value=[];cursor.value=null;password.value='';totp.value='';keys.clear();busy.value=false;error.value='';notice.value='';if(props.session.state.principal)void load();});onMounted(load);
</script>
<template>
<section>
<div class="page-heading"><div><p class="eyebrow">PURCHASE REVIEWS</p><h1>{{ realm==='admin'?'评价审核':'商品与服务评价' }}</h1><p>真实已收货订单的商品评价与履约服务评分</p></div><button :disabled="busy" @click="load()">刷新评价</button></div>
<p v-if="error" role="alert">{{ error }}</p><p v-if="notice" role="status">{{ notice }}</p><p v-if="!rows.length&&!busy">暂无评价</p>
<article v-for="r in rows" :key="r.id" class="confirm-card"><strong>商品 {{ r.rating }} / 5 · 服务 {{ r.service_rating??'未评分' }} / 5</strong><p style="white-space:pre-wrap">{{ r.body }}</p><small>已验证购买 · {{ r.created_at }}</small><p v-if="r.pet_label">{{ r.pet_label.species_name }} · {{ r.pet_label.breed_name??'品种未填写' }} · {{ r.pet_label.age_label??'年龄未填写' }}</p><PublicationMedia v-for="m in r.media" :key="m.asset_id" :client="session.client" :media="m" /><button v-if="realm==='admin'" class="secondary" @click="select(r.id)">读取评价审核详情</button></article>
<button v-if="cursor" :disabled="busy" @click="load(true)">更多评价</button>
<form v-if="selected" class="confirm-card" @submit.prevent="moderate('APPROVE')"><h2>评价审核详情</h2><p>{{ selected.body }}</p><p>{{ selected.draft_status }} · 版本 {{ selected.version }} · {{ selected.visibility }}</p><ul><li v-for="(m,i) in selected.moderation" :key="i">{{ m.decision }} · {{ m.reason }} · {{ m.created_at }}</li></ul><template v-if="session.can('review.moderate')"><label>处理原因<textarea v-model="reason" maxlength="1000" required :disabled="busy" /></label><label>再次输入密码<input v-model="password" type="password" autocomplete="current-password" required :disabled="busy" /></label><label>新的动态验证码<input v-model="totp" pattern="[0-9]{6}" maxlength="6" required :disabled="busy" /></label><button v-if="selected.draft_status==='PENDING'" :disabled="busy" type="submit">验证并通过评价</button><button v-if="selected.draft_status==='PENDING'" :disabled="busy||!reason||!password||!totp" type="button" @click="moderate('REJECT')">验证并驳回评价</button><button v-if="selected.visibility==='PUBLIC'" :disabled="busy||!reason||!password||!totp" type="button" @click="moderate('HIDE')">验证并隐藏评价</button></template></form>
<template v-if="realm==='admin'"><h2>评价奖励规则</h2><ul><li v-for="p in policies" :key="p.id">v{{ p.policy_version }} · 评价 {{ p.base_points }} 分 · 媒体增量 {{ p.media_bonus_points }} 分 · {{ p.refund_strategy==='NONE'?'退款不追回评价奖励':'按实付商品金额累计追回' }}</li></ul><form v-if="session.can('review.policy.manage')" class="confirm-card" @submit.prevent="publishPolicy"><label>评价奖励<input v-model.number="base" type="number" min="0" max="10000" required /></label><label>媒体加奖<input v-model.number="bonus" type="number" min="0" max="10000" required /></label><label>退款规则<select v-model="strategy"><option value="PROPORTIONAL_GOODS">按商品金额追回</option><option value="NONE">不追回评价奖励</option></select></label><label>再次输入密码<input v-model="password" type="password" required /></label><label>新的动态验证码<input v-model="totp" pattern="[0-9]{6}" maxlength="6" required /></label><button :disabled="busy">验证并发布评价规则</button></form></template>
</section>
</template>
