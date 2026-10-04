<script setup lang="ts">
import {onMounted,ref} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
const props=defineProps<{session:StaffSession}>();
type Species=components['schemas']['Species'];
const species=ref<Species[]>([]),error=ref(''),notice=ref(''),busy=ref(false);
const kind=ref<'species'|'breeds'|'allergens'>('species'),name=ref(''),parent=ref('');
const password=ref(''),totp=ref(''),source=ref(''),ruleSpecies=ref(''),unit=ref<'DAY'|'MONTH'|'YEAR'>('MONTH');
const stages=ref([{code:'',name:'',min:0,max:null as number|null}]);
let generation=0;
let pending:{fingerprint:string;key:string}|undefined;
async function load(){const turn=++generation,sessionId=props.session.state.principal?.session_id;try{const rows=unwrap(await props.session.client.api.GET('/admin/pet-taxonomy')).data;if(turn===generation&&sessionId===props.session.state.principal?.session_id)species.value=rows;}catch(e){if(turn===generation)error.value=explainError(e);}}
async function mutate(fingerprint:string,action:(headers:{'Idempotency-Key':string;'X-Reverify-Token':string})=>Promise<unknown>){
 if(busy.value)return;busy.value=true;error.value='';notice.value='';
 const sessionId=props.session.state.principal?.session_id;
 if(!pending||pending.fingerprint!==fingerprint)pending={fingerprint,key:crypto.randomUUID()};
 try{const proof=await props.session.client.reverify({action:'pet.taxonomy.write',password:password.value,totp_code:totp.value});await action({'Idempotency-Key':pending.key,'X-Reverify-Token':proof.reverify_token});if(sessionId===props.session.state.principal?.session_id){pending=undefined;notice.value='已保存，操作已记录。';await load();}}
 catch(e){if(sessionId===props.session.state.principal?.session_id)error.value=explainError(e);}
 finally{password.value='';totp.value='';busy.value=false;}
}
async function create(){
 const payload={name:name.value,...(kind.value==='species'?{parent_id:parent.value}:kind.value==='breeds'?{species_id:parent.value}:{})};
 await mutate(JSON.stringify([kind.value,payload]),async headers=>{
  if(kind.value==='species')unwrap(await props.session.client.api.POST('/admin/pet-taxonomy/species',{params:{header:headers},body:{name:name.value,parent_id:parent.value}}));
  else if(kind.value==='breeds')unwrap(await props.session.client.api.POST('/admin/pet-taxonomy/breeds',{params:{header:headers},body:{name:name.value,species_id:parent.value}}));
  else unwrap(await props.session.client.api.POST('/admin/pet-taxonomy/allergens',{params:{header:headers},body:{name:name.value}}));
 });
}
async function publish(){
 const body:components['schemas']['RulePublish']={species_id:ruleSpecies.value,source_refs:source.value.split('\n').map(s=>s.trim()).filter(Boolean),stages:[...stages.value.map(s=>({stage_code:s.code,display_name:s.name,min_age_value:s.min,max_age_value:s.max==null||String(s.max)===''?null:s.max,age_unit:unit.value,is_unknown:false})),{stage_code:'UNKNOWN',display_name:'信息不足',min_age_value:null,max_age_value:null,age_unit:unit.value,is_unknown:true}]};
 await mutate(JSON.stringify(body),async headers=>unwrap(await props.session.client.api.POST('/admin/pet-taxonomy/life-stage-rules',{params:{header:headers},body})));
}
onMounted(load);
</script>
<template>
 <div>
  <div class="page-heading"><div><p class="eyebrow">PET KNOWLEDGE</p><h1>宠物分类与年龄规则</h1><p class="muted">分类可扩展；已发布规则保留版本。缺少可信规则时显示信息不足。</p></div><button class="secondary" :disabled="busy" @click="load">刷新</button></div>
  <p v-if="error" role="alert" class="error">{{ error }}</p><p v-if="notice" role="status" class="notice">{{ notice }}</p>
  <div class="cards"><article v-for="item in species" :key="item.id"><h2>{{ item.name }}</h2><p>{{ item.parent_id?'具体物种':'父分类' }}</p><ul><li v-for="stage in item.life_stages" :key="stage.id">{{ stage.display_name }} · {{ stage.is_unknown?'信息不足':`${stage.min_age_value} 至 ${stage.max_age_value??'无上限'} ${stage.age_unit==='MONTH'?'月':stage.age_unit==='YEAR'?'年':'天'}` }}</li></ul></article></div>
  <template v-if="session.can('pet.taxonomy.write')">
   <section class="confirm-card"><h2>操作验证</h2><p>每次保存须提供密码和新的动态验证码。</p><label>再次输入密码<input v-model="password" type="password" autocomplete="current-password" :disabled="busy" /></label><label>新的动态验证码<input v-model="totp" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" autocomplete="one-time-code" :disabled="busy" /></label></section>
   <form class="confirm-card" @submit.prevent="create"><h2>维护分类词典</h2><label>类型<select v-model="kind" :disabled="busy"><option value="species">物种</option><option value="breeds">品种</option><option value="allergens">过敏原</option></select></label><label>名称<input v-model="name" required maxlength="160" :disabled="busy" /></label><label v-if="kind!=='allergens'">{{ kind==='species'?'所属父分类':'所属物种' }}<select v-model="parent" required :disabled="busy"><option value="" disabled>请选择</option><option v-for="item in species.filter(s=>kind==='breeds'||!s.parent_id)" :key="item.id" :value="item.id">{{ item.name }}</option></select></label><button :disabled="busy||!password||!totp">保存词典项</button></form>
   <form class="confirm-card" @submit.prevent="publish">
<h2>发布年龄规则的新版本</h2><p>按审核过的来源填写。区间包含下限、不包含上限；留空上限表示无上限。</p><label>物种<select v-model="ruleSpecies" required :disabled="busy"><option value="" disabled>请选择</option><option v-for="item in species" :key="item.id" :value="item.id">{{ item.name }}</option></select></label><label>来源依据（每行一条）<textarea v-model="source" required :disabled="busy" /></label><label>年龄单位<select v-model="unit" :disabled="busy"><option value="DAY">天</option><option value="MONTH">月</option><option value="YEAR">年</option></select></label>
    <fieldset v-for="(stage,index) in stages" :key="index" :disabled="busy"><legend>阶段 {{ index+1 }}</legend><label>阶段标识<input v-model="stage.code" required maxlength="80" /></label><label>显示名称<input v-model="stage.name" required maxlength="160" /></label><label>年龄下限<input v-model.number="stage.min" type="number" min="0" required /></label><label>年龄上限<input v-model.number="stage.max" type="number" min="1" /></label><button v-if="stages.length>1" type="button" class="secondary" @click="stages.splice(index,1)">移除此阶段</button></fieldset>
    <button type="button" class="secondary" :disabled="busy||stages.length>=29" @click="stages.push({code:'',name:'',min:0,max:null})">增加阶段</button><p>信息不足阶段会自动保留。</p><button :disabled="busy||!password||!totp">发布新版本</button>
   </form>
  </template>
 </div>
</template>
<style scoped>
textarea {width:100%;min-height:100px;padding:12px;border:1px solid #dbe3dc;border-radius:10px;font:inherit;}
fieldset {border:1px solid #dbe3dc;border-radius:10px;padding:16px;margin:16px 0;}
</style>
