<script setup lang="ts">
import {ref,watch,onMounted} from 'vue';
import PaymentPanel from './PaymentPanel.vue';
import FulfillmentPanel from './FulfillmentPanel.vue';
import {unwrap,type components} from '../../api-client/src';
import {StaffSession,explainError} from './auth';
type Summary=components['schemas']['OrderSummary'];type Sub=components['schemas']['Suborder'];type Order=components['schemas']['Order'];
const props=defineProps<{session:StaffSession;realm:'merchant'|'admin'}>();
const rows=ref<(Summary|Sub)[]>([]),order=ref<Order>(),sub=ref<Sub>(),cursor=ref<string>(),busy=ref(false),error=ref('');let generation=0;
function state(value:string){return ({PARTIALLY_SHIPPED:'部分发货',AWAITING_RECEIPT:'待收货',SHIPPED_WAITING_RECEIPT:'待收货',PARTIALLY_COMPLETED:'部分完成',COMPLETED:'已完成',PENDING_PAYMENT:'待付款',PAYMENT_PROCESSING:'支付确认中',FULFILLING:'已付款待履约',PAID_WAITING_FULFILLMENT:'已付款待履约',CANCELLED:'已取消',PENDING:'待付款',PROCESSING:'支付确认中',SUCCEEDED:'已付款',CLOSED:'已关闭'} as Record<string,string>)[value]??'状态未知';}
function money(fen:number){return `¥${(fen/100).toFixed(2)}`;}
async function load(more=false){if(busy.value)return;const epoch=++generation,identity=props.session.state.principal?.session_id;busy.value=true;error.value='';order.value=undefined;sub.value=undefined;if(!more)rows.value=[];
 try{const query={limit:20,...(more&&cursor.value?{cursor:cursor.value}:{})};if(props.realm==='admin'){const result=unwrap(await props.session.client.api.GET('/admin/orders',{params:{query}}));if(epoch===generation&&identity===props.session.state.principal?.session_id){rows.value.push(...result.data);cursor.value=result.page.next_cursor??undefined;}}else{const result=unwrap(await props.session.client.api.GET('/merchant/suborders',{params:{query}}));if(epoch===generation&&identity===props.session.state.principal?.session_id){rows.value.push(...result.data);cursor.value=result.page.next_cursor??undefined;}}}catch(e){if(epoch===generation)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}
}
async function inspect(id:string){if(busy.value)return;const epoch=++generation,identity=props.session.state.principal?.session_id;busy.value=true;error.value='';order.value=undefined;sub.value=undefined;
 try{if(props.realm==='admin'){const value=unwrap(await props.session.client.api.GET('/admin/orders/{id}',{params:{path:{id}}})).data;if(epoch===generation&&identity===props.session.state.principal?.session_id)order.value=value;}else{const value=unwrap(await props.session.client.api.GET('/merchant/suborders/{id}',{params:{path:{id}}})).data;if(epoch===generation&&identity===props.session.state.principal?.session_id)sub.value=value;}}catch(e){if(epoch===generation)error.value=explainError(e);}finally{if(epoch===generation)busy.value=false;}
}
watch(()=>props.session.state.principal?.session_id,()=>{generation++;rows.value=[];order.value=undefined;sub.value=undefined;cursor.value=undefined;error.value='';busy.value=false;});onMounted(()=>load());
</script>
<template>
 <h1>{{ realm==='merchant'?'商家订单':'平台订单' }}</h1><p class="muted">查看已冻结的商品及金额。已接通开发环境模拟支付、未付款取消及支付异常核查；支持分包发货和消费者确认收货。</p><p v-if="error" role="alert">{{ error }}</p><button :disabled="busy" @click="load()">刷新订单</button>
 <p v-if="!busy&&!rows.length">暂时没有可查看的订单</p>
 <table v-if="rows.length"><thead><tr><th>订单号</th><th>状态</th><th>应付</th><th>详情</th></tr></thead><tbody><tr v-for="row in rows" :key="row.id"><td>{{ 'order_no' in row?row.order_no:row.suborder_no }}</td><td>{{ state('status' in row?row.status:row.fulfillment_status) }}</td><td>{{ money(row.payable_amount_fen) }}</td><td><button :disabled="busy" @click="inspect(row.id)">查看详情</button></td></tr></tbody></table><button v-if="cursor" :disabled="busy" @click="load(true)">加载更多</button>
 <section v-if="order"><h2>订单 {{ order.order_no }}</h2><p>应付 {{ money(order.payable_amount_fen) }} · 付款期限 {{ new Date(order.reservation_expires_at).toLocaleString() }}</p><p>支付意图 {{ state(order.payment.status) }}</p><PaymentPanel v-if="session.can('payment.read')" :session="session" :payment-id="order.payment.id" /><p v-if="order.cancellation">取消原因 {{ order.cancellation.reason_code==='PAYMENT_WINDOW_EXPIRED'?'付款超时':'消费者取消' }}</p><article v-for="group in order.suborders" :key="group.id"><h3>{{ group.merchant_name }} · {{ money(group.payable_amount_fen) }}</h3><p v-for="item in group.items" :key="item.id">{{ item.product_snapshot.name }} × {{ item.quantity }} · 已取消 {{ item.cancelled_qty }} · {{ money(item.payable_amount_fen) }}</p><FulfillmentPanel :session="session" realm="admin" :suborder-id="group.id" /></article></section>
 <section v-if="sub"><h2>子订单 {{ sub.suborder_no }}</h2><p>{{ sub.merchant_name }} · {{ money(sub.payable_amount_fen) }}</p><p v-for="item in sub.items" :key="item.id">{{ item.product_snapshot.name }} × {{ item.quantity }} · 已取消 {{ item.cancelled_qty }} · {{ money(item.payable_amount_fen) }}</p><FulfillmentPanel :session="session" realm="merchant" :suborder-id="sub.id" /></section>
</template>
