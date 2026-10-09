<script setup lang="ts">
import {onMounted,onBeforeUnmount,ref,watch} from 'vue';
import {mutationHeaders,unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
type Release=components['schemas']['AiRelease'];
type Policy=components['schemas']['AiPolicyInput'];
type Prompt=components['schemas']['AiPromptView'];
type Evaluation=components['schemas']['AiEvaluation'];
const props=defineProps<{session:StaffSession;realm:'admin'|'merchant'}>();
const release=ref<Release|null>(null),prompts=ref<Prompt[]>([]),evaluations=ref<Evaluation[]>([]);
const form=ref<Policy>({ordinary_daily_limit:3,member_daily_ceiling:200,retention_days:30,lease_seconds:60,enabled:true});
const instruction=ref('Return JSON with verified evidence_ids.'),percentage=ref(10),password=ref(''),totp=ref(''),error=ref(''),notice=ref(''),busy=ref(false);
let generation=0;const keys=new Map<string,string>();
function fence(){const g=generation,s=props.session.state.principal?.session_id;return ()=>g===generation&&s===props.session.state.principal?.session_id;}
function reset(){generation++;release.value=null;prompts.value=[];evaluations.value=[];password.value='';totp.value='';error.value='';notice.value='';busy.value=false;keys.clear();}
async function load(){if(props.realm!=='admin')return;const current=fence();error.value='';
 try{const api=props.session.client.api;const [r,p,v,e]=await Promise.all([api.GET('/admin/ai/release'),api.GET('/admin/ai/prompts'),api.GET('/admin/ai/policies'),api.GET('/admin/ai/evaluations')]);
 if(current()){release.value=unwrap(r).data;prompts.value=unwrap(p).data;evaluations.value=unwrap(e).data;const policy=unwrap(v).data.find(x=>x.id===release.value?.policy_id);if(policy)form.value={ordinary_daily_limit:policy.ordinary_daily_limit,member_daily_ceiling:policy.member_daily_ceiling,retention_days:policy.retention_days,lease_seconds:policy.lease_seconds,enabled:policy.enabled};}}
 catch(e){if(current())error.value=explainError(e);}}
async function command(action:'policy'|'create'|'validate'|'stage'|'activate'|'rollback',id?:string){if(busy.value||!release.value)return;busy.value=true;error.value='';notice.value='';const current=fence(),api=props.session.client.api,version=release.value.version;
 const policy={...form.value},text=instruction.value,percent=percentage.value;
 const fingerprint=JSON.stringify([action,id,version,action==='policy'?policy:action==='create'?text:action==='stage'?percent:null]);const key=keys.get(fingerprint)??crypto.randomUUID();keys.set(fingerprint,key);
 try{const proof=await props.session.client.reverify({action:'ai.manage',password:password.value,totp_code:totp.value});if(!current())return;const header=mutationHeaders(key,proof.reverify_token,version);
 switch(action){
  case 'policy':unwrap(await api.POST('/admin/ai/policies/versions',{params:{header},body:policy}));break;
  case 'create':unwrap(await api.POST('/admin/ai/prompts/versions',{params:{header},body:{instruction:text}}));break;
  case 'validate':unwrap(await api.POST('/admin/ai/prompts/{version_id}/validate',{params:{header,path:{version_id:id!}},body:{}}));break;
  case 'stage':unwrap(await api.POST('/admin/ai/prompts/{version_id}/stage',{params:{header,path:{version_id:id!}},body:{percentage:percent}}));break;
  case 'activate':unwrap(await api.POST('/admin/ai/prompts/{version_id}/activate',{params:{header,path:{version_id:id!}},body:{}}));break;
  case 'rollback':unwrap(await api.POST('/admin/ai/prompts/{version_id}/rollback',{params:{header,path:{version_id:id!}},body:{}}));break;
 }
 if(current()){keys.delete(fingerprint);await load();if(current())notice.value='操作已提交并记录审计。';}
 }catch(e){if(current())error.value=explainError(e);}finally{if(current()){password.value='';totp.value='';busy.value=false;}}}
watch(()=>props.session.state.principal?.session_id,()=>{reset();void load();});onMounted(()=>{void load();});onBeforeUnmount(reset);
</script>
<template>
 <div class="page-heading"><div><p class="eyebrow">PAWDAY AI</p><h1>{{ realm==='admin'?'AI 解释与额度':'AI 商品资料说明' }}</h1><p class="muted">商品资料、过敏和年龄判断以平台核对资料为准。消费者单独授权后可使用宠物上下文；商家不能读取消费者 AI 会话。</p></div><button v-if="realm==='admin'" class="secondary" :disabled="busy" @click="load()">重新读取 AI 配置</button></div>
 <p v-if="error" role="alert" class="error">{{ error }}</p><p v-if="notice" role="status">{{ notice }}</p>
 <section v-if="realm==='merchant'" class="confirm-card"><h2>让解释有据可查</h2><p>请在标准商品页维护已核对的配料、来源和适用阶段，在报价与库存页维护可售事实。资料缺失时显示信息不足；AI 不会替商家修改商品、创建订单或作医疗诊断。</p><RouterLink to="/catalog">查看标准商品资料</RouterLink></section>
 <template v-else-if="release">
  <p>解释服务：{{ release.provider_available?'已配置供应商凭证':'尚未配置供应商凭证，消费者入口暂停发送' }} · 规则 {{ release.fit_rule_version }} · 配置版本 {{ release.version }}</p>
  <section class="confirm-card"><h2>再次验证</h2><label>再次输入密码<input v-model="password" type="password" autocomplete="current-password" :disabled="busy" /></label><label>动态验证码<input v-model="totp" inputmode="numeric" maxlength="6" :disabled="busy" /></label><p>每项配置变更分别验证，提交后清空凭证。</p></section>
  <form v-if="session.can('ai.manage')" class="confirm-card" @submit.prevent="command('policy')"><h2>额度和保留策略</h2><label>普通用户每日次数<input v-model.number="form.ordinary_daily_limit" type="number" min="0" max="1000" required /></label><label>会员每日安全上限<input v-model.number="form.member_daily_ceiling" type="number" min="0" max="10000" required /></label><p>会员总次数按已付款月度／年度购买权益冻结，不按天重置。</p><label>会话保留天数<input v-model.number="form.retention_days" type="number" min="1" max="90" required /></label><label>请求额度租期（秒）<input v-model.number="form.lease_seconds" type="number" min="10" max="120" required /></label><label><input v-model="form.enabled" type="checkbox" />开启 AI 解释</label><button :disabled="busy||!password||totp.length!==6">验证并发布额度策略</button></form>
  <form v-if="session.can('ai.manage')" class="confirm-card" @submit.prevent="command('create')"><h2>新建提示版本</h2><label>整理指令<textarea v-model="instruction" maxlength="2000" required /></label><p>提示只能选择平台证据，不能修改确定性规则或调用交易工具。</p><button :disabled="busy||!password||totp.length!==6">验证并保存提示版本</button></form>
  <label>灰度比例（1–99%）<input v-model.number="percentage" type="number" min="1" max="99" /></label>
  <div class="cards"><article v-for="p in prompts" :key="p.id"><h2>{{ p.status }}</h2><p>{{ p.instruction }}</p><small>{{ p.id }}</small><template v-if="session.can('ai.manage')"><button :disabled="busy||!password||totp.length!==6" @click="command('validate',p.id)">运行边界验证</button><button :disabled="busy||!password||totp.length!==6" @click="command('stage',p.id)">验证并灰度</button><button :disabled="busy||!password||totp.length!==6" @click="command('activate',p.id)">验证并启用</button><button :disabled="busy||!password||totp.length!==6" @click="command('rollback',p.id)">回滚到此已发布版本</button></template></article></div>
  <section><h2>确定性边界验证记录</h2><p>此处检查证据白名单与工具隔离；云端模型效果在生产凭证接入后的专项验收中记录。</p><article v-for="e in evaluations" :key="e.id"><p>{{ e.created_at }} · {{ e.passed?'通过':'未通过' }} · {{ e.prompt_id }}</p><ul><li v-for="c in e.cases" :key="c.case_code">{{ c.case_code }}：{{ c.passed?'通过':'未通过' }}</li></ul></article></section>
 </template>
</template>
