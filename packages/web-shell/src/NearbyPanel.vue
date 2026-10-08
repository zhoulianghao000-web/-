<script setup lang="ts">
import {ref,watch,onMounted,onBeforeUnmount} from 'vue';
import {ApiError,unwrap,mutationHeaders,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
type Profile=components['schemas']['NearbyProfile'];
type Input=components['schemas']['NearbyProfileInput'];
const props=defineProps<{session:StaffSession;realm:'merchant'|'admin'}>();
const empty=():Input=>({city:'',category:'PET_STORE',address:'',phone:'',business_hours:'',longitude:0,latitude:0,coordinate_system:'WGS84',services:[]});
const form=ref<Input>(empty()),row=ref<Profile|null>(null),rows=ref<Profile[]>([]),cursor=ref<string|null>(null),error=ref(''),notice=ref(''),busy=ref(false),loaded=ref(false);
const password=ref(''),totp=ref(''),reason=ref(''),publication=ref<'PUBLISHED'|'HIDDEN'>('PUBLISHED'),claim=ref<'VERIFIED'|'REJECTED'>('VERIFIED'),certified=ref(false);
const labels={SUPPLIES:'宠物用品',GROOMING:'美容洗护',BOARDING:'寄养',CONSULTATION:'医院咨询',EMERGENCY:'急诊联系',PET_FRIENDLY:'宠物友好'};
const keys=new Map<string,string>();let generation=0;
function stamp(){const g=generation,s=props.session.state.principal?.session_id,store=props.session.state.storeId;return ()=>g===generation&&s===props.session.state.principal?.session_id&&store===props.session.state.storeId;}
function reset(){generation++;form.value=empty();row.value=null;rows.value=[];cursor.value=null;error.value='';notice.value='';busy.value=false;loaded.value=false;password.value='';totp.value='';reason.value='';keys.clear();}
function select(profile:Profile){generation++;loaded.value=true;row.value=profile;form.value={city:profile.city,category:profile.category,address:profile.address,phone:profile.phone,business_hours:profile.business_hours,longitude:profile.longitude,latitude:profile.latitude,coordinate_system:'WGS84',services:[...profile.services]};reason.value='';password.value='';totp.value='';error.value='';notice.value='';certified.value=profile.pawday_certified;busy.value=false;}
async function load(next=false){const current=stamp();error.value='';loaded.value=false;
 try{if(props.realm==='merchant'){if(!props.session.state.storeId)return;const profile=unwrap(await props.session.client.api.GET('/merchant/stores/{store_id}/nearby-profile',{params:{path:{store_id:props.session.state.storeId}}})).data;if(current())select(profile);}
 else{const result=unwrap(await props.session.client.api.GET('/admin/nearby/stores',{params:{query:{limit:50,...(next&&cursor.value?{cursor:cursor.value}:{})}}}));if(current()){rows.value=next?[...rows.value,...result.data]:result.data;cursor.value=result.page.next_cursor;}}}
 catch(e){if(current()){if(props.realm==='merchant'&&e instanceof ApiError&&e.status===404){row.value=null;form.value=empty();}else error.value=explainError(e);}}
 finally{if(current())loaded.value=true;}}
function commandKey(body:unknown){const fingerprint=JSON.stringify([row.value?.id??props.session.state.storeId,row.value?.version??0,body]);const key=keys.get(fingerprint)??crypto.randomUUID();keys.set(fingerprint,key);return {fingerprint,key};}
async function save(){const store=props.session.state.storeId;if(!store||!loaded.value)return;busy.value=true;error.value='';notice.value='';const current=stamp(),body={...form.value,services:[...form.value.services]},command=commandKey(body);
 try{const result=unwrap(await props.session.client.api.PUT('/merchant/stores/{store_id}/nearby-profile',{params:{path:{store_id:store},header:mutationHeaders(command.key,undefined,row.value?.version??0)},body})).data;if(current()){select(result);keys.delete(command.fingerprint);notice.value='资料已保存，等待平台审核后公开。';loaded.value=true;}}
 catch(e){if(current())error.value=explainError(e);}finally{if(current())busy.value=false;}}
async function moderate(){const profile=row.value;if(!profile)return;busy.value=true;error.value='';const current=stamp();const body={publication_status:publication.value,claim_status:claim.value,pawday_certified:certified.value,reason:reason.value},command=commandKey(body);
 try{const proof=await props.session.client.reverify({action:'nearby.moderate',password:password.value,totp_code:totp.value});if(!current())return;
 const result=unwrap(await props.session.client.api.POST('/admin/nearby/stores/{id}/moderation',{params:{path:{id:profile.id},header:mutationHeaders(command.key,proof.reverify_token,profile.version)},body})).data;
 if(current()){select(result);keys.delete(command.fingerprint);notice.value='审核结果已记录。';void load();}}
 catch(e){if(current())error.value=explainError(e);}finally{password.value='';totp.value='';if(current())busy.value=false;}}
watch(()=>[props.session.state.principal?.session_id,props.session.state.storeId],()=>{reset();void load();});onMounted(()=>{void load();});onBeforeUnmount(reset);
</script>
<template>
 <div class="page-heading"><div><p class="eyebrow">NEARBY STORES</p><h1>{{ realm==='merchant'?'门店附近资料':'附近门店审核' }}</h1><p class="muted">门店地址、营业信息与可用服务由商家提供，平台审核后公开。医院仅提供地点与联系方式。</p></div><button class="secondary" :disabled="busy" @click="load()">重新读取资料</button></div>
 <p v-if="error" role="alert" class="error">{{ error }}。版本冲突时请重新读取资料。</p><p v-if="notice" role="status">{{ notice }}</p>
 <div v-if="realm==='admin'" class="cards"><article v-for="profile in rows" :key="profile.id"><h2>{{ profile.name }}</h2><p>{{ profile.city }} · {{ profile.publication_status }} · {{ profile.claim_status }}</p><button class="secondary" @click="select(profile)">审核 {{ profile.name }}</button></article><button v-if="cursor" class="secondary" @click="load(true)">更多门店</button></div>
 <form v-if="realm==='merchant'" class="confirm-card" @submit.prevent="save">
  <label>城市<input v-model="form.city" required maxlength="80" /></label><label>地点类别<select v-model="form.category" aria-label="地点类别"><option value="PET_STORE">宠物店</option><option value="VET">宠物医院</option><option value="GROOMING">美容洗护</option><option value="BOARDING">寄养</option></select></label>
  <label>门店地址<input v-model="form.address" required maxlength="500" /></label><label>联系电话<input v-model="form.phone" required maxlength="32" /></label><label>营业信息<input v-model="form.business_hours" required maxlength="240" /></label>
  <p class="muted">坐标必须为 GPS / WGS84；不要填入高德坐标拾取器的 GCJ-02 数值。修改资料会重新进入审核。</p>
  <label>GPS 经度<input v-model.number="form.longitude" type="number" min="-180" max="180" step="0.000001" required /></label><label>GPS 纬度<input v-model.number="form.latitude" type="number" min="-90" max="90" step="0.000001" required /></label>
  <fieldset><legend>可用服务（联系门店确认，不代表可在线预约）</legend><label v-for="(label,service) in labels" :key="service"><input v-model="form.services" type="checkbox" :value="service" :disabled="(service==='CONSULTATION'||service==='EMERGENCY')&&form.category!=='VET'" />{{ label }}</label></fieldset>
  <p v-if="row">{{ row.publication_status }} · 认领 {{ row.claim_status }} · {{ row.pawday_certified?'平台已认证':'未认证' }} · 版本 {{ row.version }}</p>
  <button v-if="session.can('store.nearby.write')" :disabled="busy||!loaded">保存附近资料</button>
 </form>
 <section v-else-if="row" class="confirm-card">
<h2>{{ row.name }}</h2><p>{{ row.city }} · {{ row.address }} · {{ row.phone }}</p><p>{{ row.business_hours }} · {{ row.services.map(s=>labels[s]).join('、') }}</p><p>商家提交 · WGS84 {{ row.longitude }}, {{ row.latitude }} · 版本 {{ row.version }}</p>
  <form v-if="session.can('nearby.moderate')" @submit.prevent="moderate"><label>公开状态<select v-model="publication" aria-label="公开状态"><option value="PUBLISHED">公开</option><option value="HIDDEN">隐藏</option></select></label><label>认领审核<select v-model="claim" aria-label="认领审核"><option value="VERIFIED">已核实认领</option><option value="REJECTED">拒绝认领</option></select></label><label><input v-model="certified" type="checkbox" />平台认证（需审核资质）</label><label>审核依据与原因<textarea v-model="reason" required maxlength="500" /></label><label>再次输入密码<input v-model="password" type="password" autocomplete="current-password" required /></label><label>动态验证码<input v-model="totp" required pattern="[0-9]{6}" maxlength="6" /></label><button :disabled="busy">验证并提交审核</button></form>
 </section>
</template>
