import {it,expect,vi} from 'vitest';
import {mount,flushPromises} from '@vue/test-utils';
import {PawdayClient,type Tokens} from '../packages/api-client/src';
import {StaffSession} from '../packages/web-shell/src/auth';
import SettlementPanel from '../packages/web-shell/src/SettlementPanel.vue';
import FinancePanel from '../packages/web-shell/src/FinancePanel.vue';
const id='00000000-0000-0000-0000-000000000001',meta={request_id:id,correlation_id:id};
const tokens:Tokens={access_token:'a'.repeat(43),refresh_token:'b'.repeat(43),expires_in:900,session_id:id,user_id:null};
const json=(data:unknown)=>new Response(JSON.stringify({data,page:{next_cursor:null,has_more:false},meta}),{headers:{'Content-Type':'application/json'}});
const batch={id,settlement_no:'STEST1',merchant_id:id,status:'SETTLED',amount_fen:1350,entry_count:3,attempt_count:0,last_error_code:null,channel_reference:'SDTEST1',initiated_by:id,created_at:'2026-10-07T00:00:00Z',settled_at:'2026-10-07T00:00:01Z',next_retry_at:null};
const track={id,suborder_id:id,order_id:id,merchant_id:id,status:'ELIGIBLE',settlement_policy_id:id,buffer_days:0,eligible_at:'2026-10-07T00:00:00Z',settlement_id:null,version:2,created_at:'2026-10-07T00:00:00Z',net_fen:1350};
const report={consistent:true,checks:[{name:'sale_credit_conservation',mismatches:0}],generated_at:'2026-10-07T00:00:00Z'};
function adminSession(network:typeof fetch){const client=new PawdayClient('admin','http://localhost/api/v1',network);client.setSession(tokens);const session=new StaffSession(client);session.state.principal={id,realm:'ADMIN',merchant_id:null,user_id:null,session_id:id,permissions:['settlement.read','settlement.execute','settlement.policy.manage','ledger.read','ledger.adjust']};return session;}
it('failed settlement reverify never initiates a batch and clears credentials',async()=>{
 const calls:Request[]=[];const network=vi.fn<typeof fetch>(async input=>{const r=input as Request;calls.push(r);const url=r.url;
  if(url.includes('/admin/settlements')&&r.method==='GET')return json([batch]);
  if(url.includes('/admin/settlement-tracks'))return json([track]);
  if(url.includes('/admin/finance/reconciliation'))return json(report);
  return new Response(JSON.stringify({error:{code:'INVALID_CREDENTIALS',message:'INVALID_CREDENTIALS',retryable:false,details:{}},meta}),{status:401,headers:{'Content-Type':'application/json'}});});
 const wrapper=mount(SettlementPanel,{props:{session:adminSession(network)}});await flushPromises();
 expect(wrapper.text()).toContain('STEST1');expect(wrapper.text()).toContain('一致');
 const inputs=wrapper.findAll('input');await inputs[0]!.setValue(id);await inputs[1]!.setValue('TEST wrong');await inputs[2]!.setValue('123456');
 await wrapper.find('form').trigger('submit');await flushPromises();
 expect(calls.some(r=>r.method==='POST'&&r.url.includes('/settlements'))).toBe(false);
 expect((inputs[1]!.element as HTMLInputElement).value).toBe('');expect((inputs[2]!.element as HTMLInputElement).value).toBe('');
 expect(wrapper.find('[role="alert"]').exists()).toBe(true);wrapper.unmount();
});
it('merchant finance panel discards private rows delivered after session clear',async()=>{
 let resolve:((r:Response)=>void)|undefined;const network=vi.fn<typeof fetch>(async input=>{const r=input as Request;if(r.url.includes('/merchant/finance-summary'))return new Promise(res=>{resolve=res;});return json([]);});
 const client=new PawdayClient('merchant','http://localhost/api/v1',network);client.setSession(tokens);const session=new StaffSession(client);session.state.principal={id,realm:'MERCHANT',merchant_id:id,user_id:null,session_id:id,permissions:['ledger.read','settlement.read']};
 const wrapper=mount(FinancePanel,{props:{session}});await flushPromises();session.clear();await flushPromises();
 resolve?.(json({merchant_id:id,balance_fen:999900,eligible_fen:0,buffering_fen:0,in_flight_fen:0,settled_total_fen:0,receivable_fen:0}));await flushPromises();
 expect(wrapper.text()).not.toContain('9999.00');wrapper.unmount();
});
