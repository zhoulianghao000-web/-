<script setup lang="ts">
import AiPanel from './AiPanel.vue';
import NearbyPanel from './NearbyPanel.vue';
import SupportPanel from './SupportPanel.vue';
import ReviewPanel from './ReviewPanel.vue';
import ContentPanel from './ContentPanel.vue';
import OrdersPanel from './OrdersPanel.vue';
import OrderPolicyPanel from './OrderPolicyPanel.vue';
import ShippingPanel from './ShippingPanel.vue';
import OfferPanel from './OfferPanel.vue';
import CatalogPanel from './CatalogPanel.vue';
import {computed,onMounted,ref,watch} from 'vue';
import {useRoute,useRouter} from 'vue-router';
import {safeReturnTo,unwrap,type Audit,type Session} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
import TaxonomyPanel from './TaxonomyPanel.vue';
import SettlementPanel from './SettlementPanel.vue';
import FinancePolicyPanel from './FinancePolicyPanel.vue';
import FinancePanel from './FinancePanel.vue';
import MembershipPanel from './MembershipPanel.vue';
const props=defineProps<{realm:'merchant'|'admin';session:StaffSession}>();
const route=useRoute();const router=useRouter();
const principal=computed(()=>props.session.state.principal);
const title=computed(()=>props.realm==='merchant'?'商家工作台':'平台管理台');
const loginName=ref(''),password=ref(''),totp=ref(''),error=ref(''),busy=ref(false);
const audit=ref<Audit[]>([]),sessions=ref<Session[]>([]),listLoading=ref(false);
const reverifyOpen=ref(false),reverifyPassword=ref(''),reverifyTotp=ref(''),notice=ref('');
let pageGeneration=0;
function deviceId(){const key=`pawday.${props.realm}.device`;let id=localStorage.getItem(key);if(!id){id=crypto.randomUUID();localStorage.setItem(key,id);}return id;}
async function login(){
  error.value='';busy.value=true;
  try{await props.session.login(loginName.value,password.value,totp.value,deviceId());await router.replace(safeReturnTo(route.query.returnTo));}
  catch(e){error.value=explainError(e);}finally{password.value='';totp.value='';busy.value=false;}
}
async function logout(){busy.value=true;try{await props.session.client.logout();}catch(e){error.value=explainError(e);}finally{props.session.clear();busy.value=false;await router.replace('/login');}}
async function loadPage(){
  const generation=++pageGeneration,sessionId=principal.value?.session_id;
  const current=()=>generation===pageGeneration&&sessionId===principal.value?.session_id;
  audit.value=[];sessions.value=[];error.value='';notice.value='';reverifyOpen.value=false;reverifyPassword.value='';reverifyTotp.value='';
  if(!principal.value)return;
  listLoading.value=true;
  try{
    if(route.meta.page==='audit'&&props.session.can('audit.read')){const rows=unwrap(await props.session.client.api.GET('/admin/audit',{params:{query:{limit:20}}})).data;if(current())audit.value=rows;}
    if(route.meta.page==='sessions'){const rows=await props.session.client.sessions();if(current())sessions.value=rows;}
  }catch(e){if(current())error.value=explainError(e);}finally{if(current())listLoading.value=false;}
}
async function revokeOthers(){
  busy.value=true;error.value='';
  try{
    const proof=await props.session.client.reverify({action:'session.revoke-others',password:reverifyPassword.value,...(props.realm==='admin'?{totp_code:reverifyTotp.value}:{})});
    await props.session.client.revokeOthers(proof.reverify_token);
    await loadPage();notice.value='其他设备的会话已注销。';
  }catch(e){error.value=explainError(e);}finally{reverifyPassword.value='';reverifyTotp.value='';busy.value=false;}
}
function selectStore(event:Event){try{props.session.selectStore((event.target as HTMLSelectElement).value);}catch(e){error.value=explainError(e);}}
watch(()=>route.fullPath,loadPage);onMounted(loadPage);
</script>
<template>
  <div v-if="route.meta.page==='login'" class="login-screen">
    <section class="login-story"><div class="brand">爪日 <span>Pawday</span></div><p class="eyebrow">让每一份照顾，都有回应</p><h1>{{ title }}</h1><p>{{ realm==='merchant'?'管理你的门店，让日常经营更从容。':'守护平台秩序，让每一份信任有迹可循。' }}</p><div class="paw-mark" aria-hidden="true">✦</div></section>
    <form class="login-card" @submit.prevent="login">
      <p class="eyebrow">{{ realm==='merchant'?'MERCHANT':'ADMINISTRATOR' }}</p><h2>欢迎回来</h2><p>使用你的{{ realm==='merchant'?'商家员工':'平台管理员' }}账号登录</p>
      <label>账号<input v-model="loginName" name="username" autocomplete="username" required maxlength="160" /></label>
      <label>密码<input v-model="password" name="password" type="password" autocomplete="current-password" required maxlength="200" /></label>
      <label v-if="realm==='admin'">动态验证码<input v-model="totp" name="totp" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" required placeholder="身份验证器中的 6 位验证码" /></label>
      <p v-if="error" role="alert" class="error">{{ error }}</p><button :disabled="busy" type="submit">{{ busy?'正在登录…':'登录工作台' }}</button>
    </form>
  </div>
  <div v-else class="workspace">
    <aside><div class="brand">爪日 <span>Pawday</span></div><p class="realm-label">{{ title }}</p><nav aria-label="主导航"><RouterLink to="/dashboard">工作台</RouterLink><RouterLink v-if="session.can(realm==='merchant'?'order.read':'order.admin.read')" to="/orders">订单</RouterLink><RouterLink v-if="realm==='admin'&&session.can('order.policy.manage')" to="/order-policies">付款期限规则</RouterLink><RouterLink v-if="realm==='merchant'&&session.can('store.read')" to="/stores">我的门店</RouterLink><RouterLink v-if="realm==='admin'&&session.can('audit.read')" to="/audit">审计记录</RouterLink><RouterLink v-if="realm==='admin'&&session.can('pet.taxonomy.read')" to="/pet-taxonomy">宠物分类</RouterLink><RouterLink v-if="session.can('catalog.standard.read')" to="/catalog">标准商品</RouterLink><RouterLink v-if="session.can(realm==='merchant'?'offer.read':'offer.admin.read')" to="/offers">报价与库存</RouterLink><RouterLink v-if="realm==='admin'&&session.can('pricing.shipping.manage')" to="/shipping">配送规则</RouterLink><RouterLink v-if="realm==='admin'&&session.can('settlement.read')" to="/settlements">结算管理</RouterLink><RouterLink v-if="realm==='admin'&&session.can('settlement.policy.manage')" to="/finance-policies">佣金与账本</RouterLink><RouterLink v-if="realm==='admin'&&session.can('points.read')" to="/membership">会员与积分</RouterLink><RouterLink v-if="realm==='merchant'&&session.can('ledger.read')" to="/finance">资金与结算</RouterLink><RouterLink v-if="session.can(realm==='merchant'?'review.merchant.read':'review.read')" to="/reviews">评价</RouterLink><RouterLink v-if="realm==='admin'&&session.can('content.read')" to="/content">知识内容</RouterLink><RouterLink v-if="session.can('support.read')" to="/support">人工客服</RouterLink><RouterLink v-if="session.can(realm==='merchant'?'store.read':'nearby.read')" to="/nearby">{{ realm==='merchant'?'附近资料':'附近审核' }}</RouterLink><RouterLink v-if="realm==='merchant'||session.can('ai.read')" to="/ai">AI 资料解释</RouterLink><RouterLink to="/sessions">账号与设备</RouterLink></nav><p class="aside-footer">认真照顾，每一个日常。</p></aside>
    <main>
      <header><span>{{ title }}</span><div class="account"><select v-if="realm==='merchant'&&session.state.stores.length" aria-label="当前门店" :value="session.state.storeId" @change="selectStore"><option v-for="store in session.state.stores" :key="store.id" :value="store.id">{{ store.name }}</option></select><button class="secondary" :disabled="busy" @click="logout">退出登录</button></div></header>
      <section class="page">
        <p v-if="error" role="alert" class="error">{{ error }}</p><p v-if="notice" role="status" class="notice">{{ notice }}</p>
        <AiPanel v-if="route.meta.page==='ai'" :session="session" :realm="realm" /><NearbyPanel v-else-if="route.meta.page==='nearby'" :session="session" :realm="realm" /><SupportPanel v-else-if="route.meta.page==='support'" :session="session" :realm="realm" /><ReviewPanel v-else-if="route.meta.page==='reviews'" :session="session" :realm="realm" /><ContentPanel v-else-if="route.meta.page==='content'" :session="session" /><OrdersPanel v-else-if="route.meta.page==='orders'" :session="session" :realm="realm" /><OrderPolicyPanel v-else-if="route.meta.page==='order-policies'" :session="session" /><ShippingPanel v-else-if="route.meta.page==='shipping'" :session="session" /><SettlementPanel v-else-if="route.meta.page==='settlements'" :session="session" /><FinancePolicyPanel v-else-if="route.meta.page==='finance-policies'" :session="session" /><FinancePanel v-else-if="route.meta.page==='finance'" :session="session" /><MembershipPanel v-else-if="route.meta.page==='membership'" :session="session" /><OfferPanel v-else-if="route.meta.page==='offers'" :session="session" :realm="realm" /><CatalogPanel v-else-if="route.meta.page==='catalog'" :session="session" :realm="realm" /><TaxonomyPanel v-else-if="route.meta.page==='pet-taxonomy'" :session="session" /><template v-else-if="route.meta.page==='dashboard'"><p class="eyebrow">PAWDAY WORKSPACE</p><h1>今天，也一起照顾好它们</h1><p class="muted">{{ realm==='merchant'?'从你的门店开始，安排每一个有序的日常。':'查看账号权限与平台操作记录。' }}</p><div class="cards"><article><h2>当前身份</h2><p>{{ title }}</p><small>{{ principal?.id }}</small></article><article v-if="realm==='merchant'"><h2>授权门店</h2><p class="large">{{ session.state.stores.length }}</p><RouterLink v-if="session.can('store.read')" to="/stores">查看门店 →</RouterLink></article><article><h2>账号安全</h2><p>查看已登录设备</p><RouterLink to="/sessions">管理会话 →</RouterLink></article></div></template>
        <template v-else-if="route.meta.page==='stores'"><h1>我的门店</h1><p class="muted">仅展示当前员工获授权的门店。</p><div class="cards"><article v-for="store in session.state.stores" :key="store.id"><h2>{{ store.name }}</h2><small>{{ store.id }}</small><button class="secondary" @click="session.selectStore(store.id)">{{ session.state.storeId===store.id?'当前门店':'切换到此门店' }}</button></article></div><p v-if="!session.state.stores.length">暂未分配门店，请联系商家管理员。</p></template>
        <template v-else-if="route.meta.page==='audit'"><div class="page-heading"><div><p class="eyebrow">PLATFORM ACTIVITY</p><h1>审计记录</h1><p class="muted">最近 20 条平台操作记录</p></div><button class="secondary" :disabled="listLoading" @click="loadPage">刷新</button></div><p v-if="listLoading" role="status">正在读取记录…</p><div v-else class="table-wrap"><table v-if="audit.length"><thead><tr><th>操作</th><th>对象</th><th>时间</th><th>请求编号</th></tr></thead><tbody><tr v-for="row in audit" :key="row.id"><td>{{ row.action }}</td><td>{{ row.object_type }}</td><td>{{ row.created_at }}</td><td>{{ row.request_id??'—' }}</td></tr></tbody></table><p v-else-if="!error">暂无审计记录。</p></div></template>
        <template v-else-if="route.meta.page==='sessions'"><h1>账号与设备</h1><p class="muted">检查你的登录设备；注销其他设备需要再次验证。</p><p v-if="listLoading" role="status">正在读取设备…</p><ul class="session-list"><li v-for="item in sessions" :key="item.id"><strong>{{ item.id===principal?.session_id?'当前设备':'其他设备' }}</strong><span>{{ item.device_id }}</span><small>{{ item.revoked_at?'已注销':`有效至 ${item.expires_at}` }}</small></li></ul><button :disabled="busy" @click="reverifyOpen=true">注销其他设备</button><form v-if="reverifyOpen" class="confirm-card" @submit.prevent="revokeOthers"><h2>验证并确认</h2><p>将注销当前账号的其他设备，当前设备保持登录。</p><label>再次输入密码<input v-model="reverifyPassword" type="password" autocomplete="current-password" required /></label><label v-if="realm==='admin'">新的动态验证码<input v-model="reverifyTotp" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" required /></label><button :disabled="busy" type="submit">{{ busy?'正在验证…':'验证并注销其他设备' }}</button><button type="button" class="secondary" :disabled="busy" @click="reverifyOpen=false;reverifyPassword='';reverifyTotp=''">取消</button></form></template>
        <template v-else><h1>暂无访问权限</h1><p>请联系管理员调整账号权限。</p><RouterLink to="/dashboard">返回工作台</RouterLink></template>
      </section>
    </main>
  </div>
</template>
