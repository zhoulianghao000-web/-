import {it,expect} from 'vitest';
import {mount,flushPromises} from '@vue/test-utils';
import CatalogPanel from '../packages/web-shell/src/CatalogPanel.vue';
import {PawdayClient} from '../packages/api-client/src';
import {StaffSession} from '../packages/web-shell/src/auth';
const id='00000000-0000-4000-8000-000000000001';
for(const realm of ['merchant','admin'] as const)it(`${realm} sees unverified source label and missing ingredients`,async()=>{
 const version={id,sku_id:id,version_no:1,status:'PUBLISHED',ingredients:[],nutrients:[],allergen_ids:[],allergens_known:false,life_stage_ids:[],source_refs:['GENERATED_FIXTURE'],source_updated_on:'2026-10-11',created_by:id,created_at:'2026-10-11T00:00:00Z',published_at:'2026-10-11T00:00:00Z',pilot_material:{kind:'UNVERIFIED',label:'未核验，仅供测试',generated_fixture:true,production_approved:false,baseline_version:'cq-v1',media_path:null}};
 const sku={id,spu_id:id,sku_code:'PILOT-CQ-V1-17',weight_g:500,package_unit:'测试包',status:'ACTIVE',version:0};
 const client=new PawdayClient(realm,'http://localhost/api/v1',async input=>{
  const path=new URL((input as Request).url).pathname;
  const data=path.endsWith('/'+id)?{...sku,standard_versions:[version]}:path.endsWith('/skus')||path.endsWith('/search')?[sku]:[];
  return new Response(JSON.stringify({data,page:{next_cursor:null,has_more:false},meta:{request_id:'r',correlation_id:'r'}}),{headers:{'Content-Type':'application/json','X-Pawday-Environment':'SIMULATED_PILOT'}});
 },()=>{},true);
 client.setSession({access_token:'a',refresh_token:'r',expires_in:900,session_id:id,user_id:null});
 const session=new StaffSession(client);session.state.principal={id,realm:realm==='merchant'?'MERCHANT':'ADMIN',user_id:null,merchant_id:realm==='merchant'?id:null,session_id:id,permissions:['catalog.standard.read']};
 const wrapper=mount(CatalogPanel,{props:{realm,session}});await flushPromises();
 const button=wrapper.findAll('button').find(x=>x.text().includes('查看标准资料'));expect(button).toBeDefined();await button!.trigger('click');await flushPromises();
 expect(wrapper.text()).toContain('未核验，仅供测试');expect(wrapper.text()).toContain('配料：信息不足');wrapper.unmount();
});
