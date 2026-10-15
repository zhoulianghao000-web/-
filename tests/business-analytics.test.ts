import {afterEach,describe,it,expect,vi} from 'vitest';
import {flushPromises,mount} from '@vue/test-utils';
import {ApiError,PawdayClient,type components} from '../packages/api-client/src';
import {StaffSession} from '../packages/web-shell/src/auth';
import BusinessAnalyticsPanel from '../packages/web-shell/src/BusinessAnalyticsPanel.vue';
const merchant='00000000-0000-4000-8000-000000000001',store='00000000-0000-4000-8000-000000000002';
const metrics={paid_suborders:0,refund_count:1,paid_fen:0,refund_fen:100,net_fen:-100,commission_net_fen:-5,merchant_net_fen:-95};
function setup(realm:'merchant'|'admin'='merchant'){
 const session=new StaffSession(new PawdayClient(realm,'http://127.0.0.1/api/v1'));
 session.state.principal={id:merchant,realm:realm.toUpperCase() as 'MERCHANT'|'ADMIN',user_id:null,merchant_id:realm==='merchant'?merchant:null,session_id:merchant,permissions:['ledger.read','order.read','order.admin.read']};
 session.state.stores=[{id:store,name:'测试门店',merchant_id:merchant}];vi.spyOn(session,'refreshIdentity').mockResolvedValue();
 return session;
}
const envelope:{data:components['schemas']['BusinessAnalyticsEnvelope'];response:Response}={data:{data:{merchant_id:merchant,store_id:null,timezone:'Asia/Shanghai',from:'2026-10-15',to:'2026-10-15',as_of:'2026-10-15T00:00:00Z',source:'IMMUTABLE_MERCHANT_LEDGER',scope_policy:'WHOLE_AUTHORIZED_SUBORDER',simulated:true,totals:metrics,days:[{date:'2026-10-15',metrics}]},meta:{request_id:merchant,correlation_id:merchant}},response:new Response('{}')};
afterEach(()=>vi.restoreAllMocks());
describe('business analytics scope and request isolation',()=>{
 it('displays signed refunds, simulation and whole-suborder scope without claiming income',async()=>{
  const session=setup();vi.spyOn(session.client.api,'GET').mockResolvedValue(envelope as never);const page=mount(BusinessAnalyticsPanel,{props:{session,realm:'merchant'}});await flushPromises();
  expect(page.text()).toContain('¥-1.00');expect(page.text()).toContain('模拟经营数据');expect(page.text()).toContain('不代表利润或可提余额');expect(page.text()).toContain('混店子订单');page.unmount();
 });
 it('clears old facts when the store changes and rejects a late old response',async()=>{
  const session=setup();let resolve!:(value:typeof envelope)=>void;vi.spyOn(session.client.api,'GET').mockImplementation(()=>new Promise(r=>{resolve=r;}) as never);const page=mount(BusinessAnalyticsPanel,{props:{session,realm:'merchant'}});await flushPromises();
  await page.get('select').setValue(store);resolve(envelope);await flushPromises();expect(page.text()).not.toContain('¥-1.00');expect(page.text()).not.toContain('统计截至');page.unmount();
 });
 it('does not display an old account response after logout',async()=>{
  const session=setup();let resolve!:(value:typeof envelope)=>void;vi.spyOn(session.client.api,'GET').mockImplementation(()=>new Promise(r=>{resolve=r;}) as never);const page=mount(BusinessAnalyticsPanel,{props:{session,realm:'merchant'}});await flushPromises();session.clear();resolve(envelope);await flushPromises();expect(page.text()).not.toContain('¥-1.00');page.unmount();
 });
 it('admin must choose a merchant before reading financial facts',async()=>{
  const session=setup('admin'),get=vi.spyOn(session.client.api,'GET').mockResolvedValue(envelope as never);const page=mount(BusinessAnalyticsPanel,{props:{session,realm:'admin'}});await flushPromises();expect(get).not.toHaveBeenCalled();await page.get('form').trigger('submit');await flushPromises();expect(page.text()).toContain('有效商户编号');expect(get).not.toHaveBeenCalled();page.unmount();
 });
 it('denied queries show request ID and allow explicit retry without keeping stale values',async()=>{
  const session=setup();vi.spyOn(session.client.api,'GET').mockRejectedValueOnce(new ApiError(403,'PERMISSION_DENIED','TEST_REQUEST')).mockResolvedValueOnce(envelope as never);const page=mount(BusinessAnalyticsPanel,{props:{session,realm:'merchant'}});await flushPromises();expect(page.text()).toContain('TEST_REQUEST');expect(page.text()).not.toContain('¥-1.00');await page.get('form').trigger('submit');await flushPromises();expect(page.text()).toContain('¥-1.00');page.unmount();
 });
});
