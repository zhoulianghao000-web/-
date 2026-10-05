import {it,expect} from 'vitest';
import {mount,flushPromises} from '@vue/test-utils';
import {PawdayClient,type Tokens} from '../packages/api-client/src';
import {StaffSession} from '../packages/web-shell/src/auth';
import PaymentPanel from '../packages/web-shell/src/PaymentPanel.vue';
const id='00000000-0000-0000-0000-000000000001',meta={request_id:id,correlation_id:id};
const tokens:Tokens={access_token:'a'.repeat(43),refresh_token:'b'.repeat(43),expires_in:900,session_id:id,user_id:null};
const detail={id,payment_no:'TEST PRIVATE PAYMENT',order_id:id,amount_fen:2500,currency:'CNY',status:'PROCESSING',attempts:[],cases:[],simulation:true};
function staff(network:typeof fetch){const client=new PawdayClient('admin','http://localhost/api/v1',network);client.setSession(tokens);const session=new StaffSession(client);session.state.principal={id,realm:'ADMIN',merchant_id:null,user_id:null,session_id:id,permissions:['payment.read','payment.requery']};return session;}
const json=(data:unknown)=>new Response(JSON.stringify({data,meta}),{headers:{'Content-Type':'application/json'}});
it('late payment detail cannot reappear after logout',async()=>{
 let resolve:((r:Response)=>void)|undefined;const session=staff(async()=>new Promise(r=>{resolve=r;}));const wrapper=mount(PaymentPanel,{props:{session,paymentId:id}});await flushPromises();session.clear();await flushPromises();resolve?.(json({...detail,final_channel:'WECHAT'}));await flushPromises();expect(wrapper.text()).not.toContain('应付');expect(wrapper.text()).not.toContain('成功渠道');wrapper.unmount();
});
it('failed payment reverify blocks requery and clears both credentials',async()=>{
 const calls:Request[]=[];const session=staff(async input=>{const r=input as Request;calls.push(r);if(r.method==='GET')return json(detail);return new Response(JSON.stringify({error:{code:'INVALID_CREDENTIALS',message:'INVALID_CREDENTIALS',retryable:false,details:{}},meta}),{status:401,headers:{'Content-Type':'application/json'}});});const wrapper=mount(PaymentPanel,{props:{session,paymentId:id}});await flushPromises();const inputs=wrapper.findAll('input');await inputs[0]!.setValue('TEST WRONG');await inputs[1]!.setValue('123456');await wrapper.find('form').trigger('submit');await flushPromises();expect(calls.some(r=>r.url.endsWith('/payments/'+id+'/requery'))).toBe(false);expect((inputs[0]!.element as HTMLInputElement).value).toBe('');expect((inputs[1]!.element as HTMLInputElement).value).toBe('');expect(wrapper.find('[role="alert"]').exists()).toBe(true);wrapper.unmount();
});
