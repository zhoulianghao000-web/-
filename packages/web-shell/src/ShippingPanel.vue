<script setup lang="ts">
import {ref,watch} from 'vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
const props=defineProps<{session:StaffSession}>();
const merchant=ref(''),provinces=ref(''),base=ref(''),perKg=ref(''),free=ref(''),password=ref(''),totp=ref('');
const current=ref<components['schemas']['ShippingRule']>(),busy=ref(false),error=ref(''),notice=ref('');
let generation=0;
const keys=new Map<string,string>();
function amount(value:string){if(!/^\d+$/.test(value)||!Number.isSafeInteger(Number(value))||Number(value)>1000000000)throw new Error('金额必须是允许范围内的整数分');return Number(value);}
async function read(){if(busy.value)return;const epoch=++generation,session=props.session.state.principal?.session_id,id=merchant.value;busy.value=true;error.value='';current.value=undefined;try{const row=unwrap(await props.session.client.api.GET('/admin/merchants/{id}/shipping-rules',{params:{path:{id}}})).data;if(epoch===generation&&session===props.session.state.principal?.session_id&&id===merchant.value){current.value=row;provinces.value=row.province_codes.join(',');base.value=String(row.base_fen);perKg.value=String(row.per_kg_fen);free.value=row.free_threshold_fen==null?'':String(row.free_threshold_fen);}}catch(e){if(epoch===generation)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}}
async function publish(){
 if(busy.value)return;const epoch=++generation,session=props.session.state.principal?.session_id,id=merchant.value;busy.value=true;error.value='';notice.value='';
 try{const codes=provinces.value.split(',').map(x=>x.trim());if(codes.some(x=>!/^\d{6}$/.test(x)))throw new Error('配送省份请填写六位行政区划编码，使用逗号分隔');
  const body:components['schemas']['ShippingRuleInput']={province_codes:codes,base_fen:amount(base.value),per_kg_fen:amount(perKg.value),free_threshold_fen:free.value===''?null:amount(free.value)};
  const fingerprint=JSON.stringify({session,id,body}),key=keys.get(fingerprint)??crypto.randomUUID();keys.set(fingerprint,key);
  const proof=await props.session.client.reverify({action:'pricing.shipping.manage',password:password.value,totp_code:totp.value});
  const result=unwrap(await props.session.client.api.POST('/admin/merchants/{id}/shipping-rules',{params:{path:{id},header:{'Idempotency-Key':key,'X-Reverify-Token':proof.reverify_token}},body}));
  if(epoch===generation&&session===props.session.state.principal?.session_id&&id===merchant.value){current.value=result.data;keys.delete(fingerprint);notice.value='新配送规则已发布，已有试算需重新确认';}
 }catch(e){if(epoch===generation)error.value=e instanceof Error&&!(e.name==='ApiError')?e.message:explainError(e);}finally{password.value='';totp.value='';if(epoch===generation)busy.value=false;}
}
watch(()=>props.session.state.principal?.session_id,()=>{generation++;keys.clear();current.value=undefined;merchant.value='';password.value='';totp.value='';busy.value=false;error.value='';notice.value='';});
watch(merchant,()=>{generation++;current.value=undefined;busy.value=false;error.value='';notice.value='';});
</script>
<template>
 <h1>配送规则</h1><p class="muted">每个商户独立配置配送范围、基础运费、整公斤费用及包邮门槛。发布新版本会使旧试算失效。</p>
 <p v-if="error" role="alert">{{ error }}</p><p v-if="notice" role="status">{{ notice }}</p>
 <label>商户 ID<input v-model="merchant" :disabled="busy" required /></label><button :disabled="busy||!merchant" @click="read">读取当前配送规则</button>
 <p v-if="current">当前版本 {{ current.version_no }} · 基础运费 {{ current.base_fen }} 分 · 每整公斤 {{ current.per_kg_fen }} 分</p>
 <form class="confirm-card" @submit.prevent="publish"><label>配送省份编码（逗号分隔）<input v-model="provinces" :disabled="busy" required /></label><label>基础运费（分）<input v-model="base" inputmode="numeric" :disabled="busy" required /></label><label>每整公斤运费（分）<input v-model="perKg" inputmode="numeric" :disabled="busy" required /></label><label>包邮商品金额门槛（分，可留空）<input v-model="free" inputmode="numeric" :disabled="busy" /></label><label>再次输入密码<input v-model="password" type="password" autocomplete="current-password" :disabled="busy" required /></label><label>新的动态验证码<input v-model="totp" inputmode="numeric" maxlength="6" pattern="[0-9]{6}" :disabled="busy" required /></label><button type="submit" :disabled="busy||!merchant">验证并发布配送规则</button></form>
</template>
