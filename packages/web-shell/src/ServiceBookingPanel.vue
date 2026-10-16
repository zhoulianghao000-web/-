<script setup lang="ts">
import {ref,watch,onMounted,onBeforeUnmount} from 'vue';
import {ApiError,unwrap,mutationHeaders,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
type Service=components['schemas']['BookingService'];
type Slot=components['schemas']['BookingSlot'];
type Booking=components['schemas']['ServiceBooking'];
const props=defineProps<{session:StaffSession}>();
const services=ref<Service[]>([]),slots=ref<Slot[]>([]),bookings=ref<Booking[]>([]);
const serviceCursor=ref<string|null>(null),slotCursor=ref<string|null>(null),bookingCursor=ref<string|null>(null);
const selected=ref(''),title=ref(''),kind=ref<'GROOMING'|'BOARDING'>('GROOMING'),start=ref(''),end=ref(''),capacity=ref(1);
const busy=ref(false),enabled=ref(false),error=ref(''),notice=ref('');
const keys=new Map<string,string>();let generation=0;
function stamp(){const g=generation,s=props.session.state.principal?.session_id,store=props.session.state.storeId;return()=>g===generation&&s===props.session.state.principal?.session_id&&store===props.session.state.storeId;}
function reset(){generation++;services.value=[];slots.value=[];bookings.value=[];selected.value='';title.value='';start.value='';end.value='';serviceCursor.value=null;slotCursor.value=null;bookingCursor.value=null;enabled.value=false;busy.value=false;error.value='';notice.value='';keys.clear();}
async function loadServices(more=false){const store=props.session.state.storeId;if(!store)return;const current=stamp();const result=unwrap(await props.session.client.api.GET('/merchant/stores/{store_id}/booking-services',{params:{path:{store_id:store},query:{limit:50,...more&&serviceCursor.value?{cursor:serviceCursor.value}:{}}}}));if(!current())return;services.value=more?[...services.value,...result.data]:result.data;serviceCursor.value=result.page.next_cursor;enabled.value=true;if(!services.value.some(s=>s.id===selected.value))selected.value=services.value[0]?.id??'';}
async function loadSlots(more=false){const id=selected.value,current=stamp();if(!id){slots.value=[];return;}const result=unwrap(await props.session.client.api.GET('/merchant/booking-services/{id}/slots',{params:{path:{id},query:{limit:50,...more&&slotCursor.value?{cursor:slotCursor.value}:{}}}}));if(current()&&id===selected.value){slots.value=more?[...slots.value,...result.data]:result.data;slotCursor.value=result.page.next_cursor;}}
async function loadBookings(more=false){const store=props.session.state.storeId;if(!store)return;const current=stamp();const result=unwrap(await props.session.client.api.GET('/merchant/stores/{store_id}/service-bookings',{params:{path:{store_id:store},query:{limit:50,...more&&bookingCursor.value?{cursor:bookingCursor.value}:{}}}}));if(current()){bookings.value=more?[...bookings.value,...result.data]:result.data;bookingCursor.value=result.page.next_cursor;}}
async function load(){const current=stamp();busy.value=true;error.value='';try{await loadServices();if(current()&&enabled.value)await Promise.all([loadSlots(),loadBookings()]);}catch(e){if(current()){if(e instanceof ApiError&&e.code==='BOOKING_SIMULATION_DISABLED')enabled.value=false;else error.value=explainError(e);}}finally{if(current())busy.value=false;}}
async function command(fingerprint:string,work:(key:string)=>Promise<unknown>){if(busy.value)return;const current=stamp(),key=keys.get(fingerprint)??crypto.randomUUID();keys.set(fingerprint,key);busy.value=true;error.value='';notice.value='';try{await work(key);if(!current())return;keys.delete(fingerprint);notice.value='模拟记录已保存。';await loadServices();if(current())await Promise.all([loadSlots(),loadBookings()]);}catch(e){if(current())error.value=explainError(e);}finally{if(current())busy.value=false;}}
async function create(){const store=props.session.state.storeId;if(!store)return;const body={title:title.value,kind:kind.value};await command(JSON.stringify(['create',store,body]),key=>props.session.client.api.POST('/merchant/stores/{store_id}/booking-services',{params:{path:{store_id:store},header:mutationHeaders(key)},body}));}
async function toggle(s:Service){const body={status:s.status==='ACTIVE'?'PAUSED' as const:'ACTIVE' as const};await command(JSON.stringify(['state',s.id,s.version,body]),key=>props.session.client.api.PUT('/merchant/booking-services/{id}/state',{params:{path:{id:s.id},header:mutationHeaders(key,undefined,s.version)},body}));}
async function addSlot(){if(!selected.value)return;const a=new Date(start.value),b=new Date(end.value);if(!Number.isFinite(a.getTime())||!Number.isFinite(b.getTime())||b<=a){error.value='请选择有效的开始与结束时间。';return;}const id=selected.value,body={starts_at:a.toISOString(),ends_at:b.toISOString(),capacity:capacity.value};await command(JSON.stringify(['slot',id,body]),key=>props.session.client.api.POST('/merchant/booking-services/{id}/slots',{params:{path:{id},header:mutationHeaders(key)},body}));}
async function cancel(b:Booking){const store=props.session.state.storeId;if(!store)return;await command(JSON.stringify(['cancel',b.id,b.version]),key=>props.session.client.api.POST('/merchant/stores/{store_id}/service-bookings/{id}/cancel',{params:{path:{store_id:store,id:b.id},header:mutationHeaders(key,undefined,b.version)},body:{}}));}
async function more(kind:'services'|'slots'|'bookings'){const current=stamp();busy.value=true;try{await (kind==='services'?loadServices(true):kind==='slots'?loadSlots(true):loadBookings(true));}catch(e){if(current())error.value=explainError(e);}finally{if(current())busy.value=false;}}
async function select(){slots.value=[];slotCursor.value=null;const current=stamp();busy.value=true;try{await loadSlots();}catch(e){if(current())error.value=explainError(e);}finally{if(current())busy.value=false;}}
watch(()=>[props.session.state.principal?.session_id,props.session.state.storeId],()=>{reset();void load();});onMounted(()=>{void load();});onBeforeUnmount(reset);
</script>
<template>
 <p v-if="!enabled&&!error" role="status">{{ busy?'正在读取服务预约配置…':'当前环境未开启服务预约演练。' }}</p>
 <section v-if="enabled||error" class="confirm-card" aria-label="模拟服务预约">
  <h2>服务与预约演练</h2><p class="muted">仅模拟名额预约，不收费，不代表真实门店承诺。每份预约占当前服务时段一个名额，开始前可取消；各服务独立计算容量。</p>
  <p v-if="error" role="alert" class="error">{{ error }}。冲突后请刷新读取最新状态。</p><p v-if="notice" role="status">{{ notice }}</p>
  <button class="secondary" :disabled="busy" @click="load">刷新服务与预约</button>
  <form v-if="session.can('store.nearby.write')" @submit.prevent="create"><fieldset :disabled="busy"><legend>新增模拟服务</legend><label>服务名称<input v-model="title" required maxlength="120" /></label><label>服务类型<select v-model="kind"><option value="GROOMING">洗护</option><option value="BOARDING">寄养</option></select></label><button>新增服务</button></fieldset></form>
  <ul><li v-for="s in services" :key="s.id">{{ s.title }} · {{ s.status==='ACTIVE'?'可预约':'已暂停' }} <button v-if="session.can('store.nearby.write')" class="secondary" :disabled="busy" @click="toggle(s)">{{ s.status==='ACTIVE'?'暂停':'恢复' }} {{ s.title }}</button></li></ul>
  <button v-if="serviceCursor" class="secondary" :disabled="busy" @click="more('services')">更多服务</button>
  <label v-if="services.length">选择服务<select v-model="selected" :disabled="busy" @change="select"><option v-for="s in services" :key="s.id" :value="s.id">{{ s.title }}</option></select></label>
  <form v-if="selected&&session.can('store.nearby.write')" @submit.prevent="addSlot"><fieldset :disabled="busy"><legend>新增时段（本机当地时间）</legend><label>开始<input v-model="start" type="datetime-local" required /></label><label>结束<input v-model="end" type="datetime-local" required /></label><label>容量<input v-model.number="capacity" type="number" min="1" max="100" required /></label><p>时段不可重叠，保存后不可修改。可预约未来 90 天内的时段，单个时段最长 7 天。</p><button>保存模拟时段</button></fieldset></form>
  <ul><li v-for="s in slots" :key="s.id">{{ new Date(s.starts_at).toLocaleString() }} — {{ new Date(s.ends_at).toLocaleString() }} · 剩余 {{ s.remaining }}/{{ s.capacity }}</li></ul><button v-if="slotCursor" :disabled="busy" @click="more('slots')">更多时段</button>
  <h3>本店模拟预约</h3><p v-if="!bookings.length">暂无模拟预约。</p><article v-for="b in bookings" :key="b.id"><h4>{{ b.service_title }}</h4><p>{{ new Date(b.starts_at).toLocaleString() }} · {{ b.status==='BOOKED'?'已预约':'已取消' }}</p><small>预约编号 {{ b.id }}</small><button v-if="b.status==='BOOKED'&&new Date(b.starts_at).getTime()>Date.now()&&session.can('store.nearby.write')" class="secondary" :disabled="busy" @click="cancel(b)">取消模拟预约 {{ b.id }}</button></article><button v-if="bookingCursor" :disabled="busy" @click="more('bookings')">更多预约</button>
 </section>
</template>
