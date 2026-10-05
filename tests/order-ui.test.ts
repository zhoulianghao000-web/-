import {it,expect,vi} from 'vitest';
import {mount,flushPromises} from '@vue/test-utils';
import {PawdayClient,type Tokens} from '../packages/api-client/src';
import {StaffSession} from '../packages/web-shell/src/auth';
import OrdersPanel from '../packages/web-shell/src/OrdersPanel.vue';
import OrderPolicyPanel from '../packages/web-shell/src/OrderPolicyPanel.vue';
const id='00000000-0000-0000-0000-000000000001',meta={request_id:id,correlation_id:id};
const tokens:Tokens={access_token:'a'.repeat(43),refresh_token:'b'.repeat(43),expires_in:900,session_id:id,user_id:null};
const json=(data:unknown)=>new Response(JSON.stringify({data,page:{next_cursor:null,has_more:false},meta}),{headers:{'Content-Type':'application/json'}});
it('discard private merchant order rows delivered after session clear',async()=>{
 let resolve:((r:Response)=>void)|undefined;const client=new PawdayClient('merchant','http://localhost/api/v1',async()=>new Promise(r=>{resolve=r;}));client.setSession(tokens);const session=new StaffSession(client);session.state.principal={id,realm:'MERCHANT',merchant_id:id,user_id:null,session_id:id,permissions:['order.read']};
 const wrapper=mount(OrdersPanel,{props:{session,realm:'merchant'}});await flushPromises();session.clear();await flushPromises();resolve?.(json([{id,suborder_no:'TEST PRIVATE ORDER',fulfillment_status:'PENDING_PAYMENT',payable_amount_fen:2500}]));await flushPromises();expect(wrapper.text()).not.toContain('TEST PRIVATE ORDER');expect(wrapper.find('table').exists()).toBe(false);wrapper.unmount();
});
it('failed policy reverify cannot publish and clears credentials',async()=>{
 const calls:Request[]=[];const network=vi.fn<typeof fetch>(async input=>{const r=input as Request;calls.push(r);if(r.method==='GET')return json({id,version_no:1,version_code:'ORDER_V1_1',reservation_ttl_seconds:900,created_at:'2026-10-05T00:00:00Z'});return new Response(JSON.stringify({error:{code:'INVALID_CREDENTIALS',message:'INVALID_CREDENTIALS',retryable:false,details:{}},meta}),{status:401,headers:{'Content-Type':'application/json'}});});
 const client=new PawdayClient('admin','http://localhost/api/v1',network);client.setSession(tokens);const session=new StaffSession(client);session.state.principal={id,realm:'ADMIN',merchant_id:null,user_id:null,session_id:id,permissions:['order.policy.manage']};const wrapper=mount(OrderPolicyPanel,{props:{session}});await flushPromises();const inputs=wrapper.findAll('input');await inputs[0]!.setValue('ORDER_V1_2');await inputs[2]!.setValue('TEST wrong');await inputs[3]!.setValue('123456');await wrapper.find('form').trigger('submit');await flushPromises();expect(calls.some(r=>r.method==='POST'&&r.url.endsWith('/admin/order-policies'))).toBe(false);expect((inputs[2]!.element as HTMLInputElement).value).toBe('');expect((inputs[3]!.element as HTMLInputElement).value).toBe('');expect(wrapper.find('[role="alert"]').exists()).toBe(true);wrapper.unmount();
});

