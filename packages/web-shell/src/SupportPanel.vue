<script setup lang="ts">
import {onBeforeUnmount,onMounted,ref,watch} from 'vue';
import {useRouter} from 'vue-router';
import {mutationHeaders,unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
type Conversation=components['schemas']['Conversation'];type Message=components['schemas']['SupportMessage'];
const props=defineProps<{session:StaffSession;realm:'merchant'|'admin'}>();const router=useRouter();
const rows=ref<Conversation[]>([]),selected=ref<Conversation|null>(null),messages=ref<Message[]>([]),error=ref(''),busy=ref(false),text=ref('');
const target=ref(''),type=ref<'TEXT'|'IMAGE'|'PRODUCT'|'ORDER'>('TEXT'),assets=ref<string[]>([]),imageUrls=ref<Record<string,string>>({});
const assignTo=ref(''),reason=ref(''),password=ref(''),totp=ref(''),assignOpen=ref(false);
const nextCursor=ref<string|null>(null);const keys=new Map<string,string>();let generation=0,polling=false,listPolling=false,timer:ReturnType<typeof setInterval>|undefined;
function stamp(){const g=generation,session=props.session.state.principal?.session_id,store=props.session.state.storeId;return ()=>g===generation&&session===props.session.state.principal?.session_id&&store===props.session.state.storeId;}
function revokeImages(){for(const url of Object.values(imageUrls.value))URL.revokeObjectURL(url);imageUrls.value={};}
function reset(){generation++;busy.value=false;nextCursor.value=null;rows.value=[];selected.value=null;messages.value=[];text.value='';assets.value=[];target.value='';keys.clear();assignOpen.value=false;password.value='';totp.value='';reason.value='';assignTo.value='';error.value='';revokeImages();}
async function refresh(next=false){if(listPolling)return;listPolling=true;const current=stamp();try{const path=`/${props.realm}/conversations` as const;const result=unwrap(await props.session.client.api.GET(path,{params:{query:{limit:50,...(next&&nextCursor.value?{cursor:nextCursor.value}:{}),...(props.realm==='merchant'?{store_id:props.session.state.storeId??''}:{})}}}));if(current()){if(next)rows.value.push(...result.data.filter(row=>!rows.value.some(old=>old.id===row.id)));else rows.value=[...result.data,...rows.value.filter(row=>!result.data.some(fresh=>fresh.id===row.id))];if(next||!nextCursor.value)nextCursor.value=result.page.next_cursor;}}catch(e){if(current())error.value=explainError(e);}finally{listPolling=false;}}
async function select(row:Conversation){generation++;selected.value=row;messages.value=[];error.value='';busy.value=false;assets.value=[];text.value='';target.value='';assignOpen.value=false;password.value='';totp.value='';revokeImages();if(row.assigned_to_me)await poll();}
async function poll(){const row=selected.value;if(!row?.assigned_to_me||polling)return;polling=true;const current=stamp();try{
 const result=unwrap(await props.session.client.api.GET(`/${props.realm}/conversations/{id}/messages`,{params:{path:{id:row.id},query:{after_sequence:messages.value.at(-1)?.sequence??0,limit:50,wait_seconds:1}}}));if(!current())return;
 const seen=new Set(messages.value.map(m=>m.id));messages.value.push(...result.data.filter(m=>!seen.has(m.id)));
 const last=messages.value.at(-1)?.sequence;if(last!==undefined&&last>row.read_sequence){const read=unwrap(await props.session.client.api.POST(`/${props.realm}/conversations/{id}/read`,{params:{path:{id:row.id},header:mutationHeaders(crypto.randomUUID())},body:{through_sequence:last}})).data;if(current()&&(!selected.value||read.version>=selected.value.version))selected.value=read;}
 }catch(e){if(current()){error.value=explainError(e);messages.value=[];revokeImages();}}finally{polling=false;}}
async function send(){const row=selected.value;if(!row)return;busy.value=true;error.value='';const current=stamp();const body={type:type.value,body:type.value==='TEXT'?text.value:null,asset_ids:type.value==='IMAGE'?assets.value:[],target_id:['PRODUCT','ORDER'].includes(type.value)?target.value:null};const fingerprint=JSON.stringify([row.id,body]);const key=keys.get(fingerprint)??crypto.randomUUID();keys.set(fingerprint,key);
 try{await props.session.client.api.POST(`/${props.realm}/conversations/{id}/messages`,{params:{path:{id:row.id},header:mutationHeaders(key)},body});if(current()){keys.delete(fingerprint);text.value='';assets.value=[];target.value='';await poll();await refresh();}}
 catch(e){if(current())error.value=explainError(e);}finally{if(current())busy.value=false;}}
async function upload(event:Event){const file=(event.target as HTMLInputElement).files?.[0];if(!file)return;busy.value=true;const current=stamp();try{const asset=await props.session.client.uploadMedia('CHAT',file);if(current())assets.value=[asset.asset_id];}catch(e){if(current())error.value=explainError(e);}finally{(event.target as HTMLInputElement).value='';if(current())busy.value=false;}}
async function image(media:components['schemas']['PublicationMedia']){const current=stamp();try{const blob=await props.session.client.publicationMedia(media.content_url);if(current()){const old=imageUrls.value[media.asset_id];if(old)URL.revokeObjectURL(old);imageUrls.value[media.asset_id]=URL.createObjectURL(blob);}}catch(e){if(current())error.value=explainError(e);}}
async function openCard(message:Message){const row=selected.value;if(!row)return;const current=stamp();try{const card=unwrap(await props.session.client.api.GET(`/${props.realm}/conversations/{id}/messages/{mid}/card`,{params:{path:{id:row.id,mid:message.id}}})).data;if(!current())return;if(!card.available)error.value='商品暂不可用';else if(card.type==='ORDER')await router.push('/orders');else await router.push('/catalog');}catch(e){if(current())error.value=explainError(e);}}
async function assign(){const row=selected.value;if(!row)return;busy.value=true;const current=stamp();try{
 const proof=await props.session.client.reverify({action:'support.assign',password:password.value,...(props.realm==='admin'?{totp_code:totp.value}:{})});if(!current())return;
 const updated=unwrap(await props.session.client.api.POST(`/${props.realm}/conversations/{id}/assignment`,{params:{path:{id:row.id},header:mutationHeaders(crypto.randomUUID(),proof.reverify_token,row.version)},body:{principal_id:assignTo.value||props.session.state.principal!.id,reason:reason.value}})).data;
 if(current()){await select(updated);await refresh();}
 }catch(e){if(current())error.value=explainError(e);}finally{password.value='';totp.value='';if(current())busy.value=false;else busy.value=false;}}
async function changeStatus(){const row=selected.value;if(!row)return;busy.value=true;const current=stamp();try{const updated=unwrap(await props.session.client.api.POST(`/${props.realm}/conversations/{id}/status`,{params:{path:{id:row.id},header:mutationHeaders(crypto.randomUUID(),undefined,row.version)},body:{status:row.status==='OPEN'?'CLOSED':'OPEN'}})).data;if(current()){selected.value=updated;await refresh();}}catch(e){if(current())error.value=explainError(e);}finally{if(current())busy.value=false;}}
watch(()=>[props.session.state.principal?.session_id,props.session.state.storeId],()=>{reset();void refresh();});
onMounted(()=>{void refresh();timer=setInterval(()=>{void refresh();void poll();},2500);});onBeforeUnmount(()=>{if(timer)clearInterval(timer);reset();});
</script>
<template>
 <div class="page-heading"><div><p class="eyebrow">HUMAN SUPPORT</p><h1>{{ realm==='merchant'?'门店客服':'平台人工客服' }}</h1><p class="muted">用户发起会话后，由获授权客服接待。转接需再次验证。</p></div><button class="secondary" @click="refresh()">刷新会话</button></div>
 <p v-if="error" role="alert" class="error">{{ error }}。发送失败可保留原内容重试。</p>
 <div class="support-layout">
<section class="support-queue"><button v-for="row in rows" :key="row.id" class="secondary" @click="select(row)"><strong>{{ row.id.slice(0,8) }}</strong> · {{ row.status==='OPEN'?'处理中':'已关闭' }} · {{ row.assigned_to_me?'由我接待':row.assigned?'其他客服接待':'待分配' }}<span>未读 {{ row.unread_count }}</span></button><p v-if="!rows.length">暂无当前范围内的会话。</p><button v-if="nextCursor" class="secondary" @click="refresh(true)">更多会话</button></section>
 <section v-if="selected" class="support-chat">
<h2>会话 {{ selected.id.slice(0,8) }}</h2>
  <button v-if="session.can('support.assign')" class="secondary" @click="assignOpen=!assignOpen">{{ selected.assigned?'转接 / 重新分配':'领取会话' }}</button>
  <form v-if="assignOpen" class="confirm-card" @submit.prevent="assign"><label>接待员工编号（留空为自己）<input v-model="assignTo" /></label><label>分配原因<input v-model="reason" required maxlength="500" /></label><label>再次输入密码<input v-model="password" type="password" autocomplete="current-password" required /></label><label v-if="realm==='admin'">动态验证码<input v-model="totp" maxlength="6" pattern="[0-9]{6}" required /></label><button :disabled="busy">验证并分配</button></form>
  <p v-if="!selected.assigned_to_me" class="muted">消息与附件仅向当前接待客服开放。请选择自己领取，或由主管分配。</p>
  <template v-else>
<ol class="support-messages" aria-live="polite"><li v-for="message in messages" :key="message.id" :class="{outgoing:message.outgoing}"><small>{{ message.outgoing?'我':message.sender_realm==='CONSUMER'?'用户':'客服' }} · {{ message.sequence }}</small><p v-if="message.type==='TEXT'">{{ message.body }}</p><template v-else-if="message.type==='IMAGE'"><template v-for="media in message.media" :key="media.asset_id"><img v-if="imageUrls[media.asset_id]" :src="imageUrls[media.asset_id]" alt="会话图片" /><button v-else class="secondary" @click="image(media)">查看私有图片</button></template></template><button v-else class="secondary" @click="openCard(message)">{{ message.type==='ORDER'?'查看订单卡片':'查看商品卡片' }}</button></li></ol>
   <p class="muted">已保存 {{ selected.last_sequence }} 条消息 · 传输确认 {{ selected.delivered_sequence }} 条</p>
   <button v-if="session.can('support.reply')" class="secondary" :disabled="busy" @click="changeStatus">{{ selected.status==='OPEN'?'关闭会话':'重新打开' }}</button>
   <form v-if="selected.status==='OPEN'&&session.can('support.reply')" class="support-compose" @submit.prevent="send"><label>消息类型<select v-model="type"><option value="TEXT">文字</option><option value="IMAGE">图片</option><option value="PRODUCT">商品卡片</option><option value="ORDER">订单卡片</option></select></label><label v-if="type==='TEXT'">消息<textarea v-model="text" required maxlength="2000" /></label><label v-else-if="type==='IMAGE'">图片<input type="file" accept="image/png,image/jpeg" :disabled="busy" @change="upload" /><span>{{ assets.length?'图片已上传，等待发送':'PNG / JPEG，最大 5 MB' }}</span></label><label v-else>关联{{ type==='ORDER'?'子订单':'SKU' }}编号<input v-model="target" required /></label><button :disabled="busy||(type==='IMAGE'&&!assets.length)">发送消息</button></form>
  </template>
 </section>
</div>
</template>
