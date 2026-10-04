import {test,expect,type Page} from '@playwright/test';
const meta={request_id:'00000000-0000-0000-0000-000000000001',correlation_id:'00000000-0000-0000-0000-000000000002'};
const tokens={access_token:'access',refresh_token:'refresh',expires_in:900,session_id:meta.request_id,user_id:null};
async function fixture(page:Page,realm:'merchant'|'admin',permissions:string[],reverifyAction='session.revoke-others'){
  const principal={id:meta.request_id,realm:realm.toUpperCase(),merchant_id:realm==='merchant'?meta.request_id:null,user_id:null,session_id:meta.request_id,permissions};
  const seen:string[]=[];
  await page.route('**/api/v1/**',async route=>{
    const request=route.request(),path=new URL(request.url()).pathname;seen.push(path);
    let data:unknown={id:meta.request_id,version:1,accepted_at:new Date().toISOString()};
    if(path.endsWith('/login')||path.endsWith('/refresh'))data=tokens;
    else if(path.endsWith('/me'))data=principal;
    else if(path.endsWith('/stores'))data=[{id:'store-a',merchant_id:meta.request_id,name:'南山店'},{id:'store-b',merchant_id:meta.request_id,name:'海岸店'}];
    else if(path.endsWith('/sessions'))data=[{id:meta.request_id,device_id:'Browser',created_at:new Date().toISOString(),expires_at:new Date().toISOString(),revoked_at:null}];
    else if(path.endsWith('/reverify')){const body=JSON.parse(request.postData()??'{}');expect(body.action).toBe(reverifyAction);expect(body.password).toBe('TEST_ONLY_password');if(realm==='admin')expect(body.totp_code).toBe('654321');data={reverify_token:'one-use-proof',action:reverifyAction,expires_at:new Date().toISOString()};}
    else if(path.endsWith('/pet-taxonomy'))data=[{id:'cat-root',parent_id:null,name:'猫',category:'CAT',life_stages:[]}];
    else if(['/skus','/spus','/brands','/catalog/search','/catalog-reviews','/catalog-requests','/allergens'].some(p=>path.endsWith(p)))data=[];
    else if(path.endsWith('/pet-taxonomy/species')){expect(request.headers()['x-reverify-token']).toBe('one-use-proof');expect(request.headers()['idempotency-key']).toBeTruthy();expect(request.postDataJSON()).toEqual({name:'布偶猫',parent_id:'cat-root'});data={id:'new-species',name:'布偶猫'};}
    else if(path.endsWith('/revoke-others'))expect(request.headers()['x-reverify-token']).toBe('one-use-proof');
    else if(path.endsWith('/audit'))data=[{id:'audit',actor_type:'ADMIN',actor_id:meta.request_id,action:'auth.sessions.revoked-others',object_type:'SESSION',object_id:meta.request_id,before_json:null,after_json:null,request_id:meta.request_id,correlation_id:meta.correlation_id,created_at:'2026-10-04T00:00:00Z'}];
    if(!path.endsWith('/login'))expect(request.headers()['authorization']).toBe('Bearer access');
    expect(request.headers()['x-request-id']).toBeTruthy();
    await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({data,meta,page:{next_cursor:null,has_more:false}})});
  });return seen;
}
async function login(page:Page,realm:'merchant'|'admin'){
  await page.getByLabel('账号',{exact:true}).fill('test-account');await page.getByLabel('密码',{exact:true}).fill('TEST_ONLY_password');
  if(realm==='admin')await page.getByLabel('动态验证码',{exact:true}).fill('123456');
  await page.getByRole('button',{name:'登录工作台'}).click();
}
test('merchant login returns to requested route and preserves authorized store selection',async({page})=>{
  await fixture(page,'merchant',['store.read']);await page.goto('http://127.0.0.1:5173/stores');await expect(page).toHaveURL(/login\?returnTo/);await login(page,'merchant');await expect(page).toHaveURL('http://127.0.0.1:5173/stores');
  await page.getByLabel('当前门店').selectOption('store-b');await page.getByRole('link',{name:'工作台',exact:true}).click();await expect(page.getByLabel('当前门店')).toHaveValue('store-b');
  expect(await page.evaluate(()=>Object.keys(localStorage))).toEqual(['pawday.merchant.device']);await page.screenshot({path:'test-results/merchant-dashboard.png',fullPage:true});
  await page.reload();await expect(page).toHaveURL(/\/login/);
});
test('merchant direct unauthorized route is denied using current server permissions',async({page})=>{
  await fixture(page,'merchant',[]);await page.goto('http://127.0.0.1:5173/stores');await login(page,'merchant');await expect(page).toHaveURL(/\/denied$/);await expect(page.getByRole('heading',{name:'暂无访问权限'})).toBeVisible();await expect(page.getByRole('link',{name:'我的门店'})).toHaveCount(0);
});
test('admin requires TOTP and loads audit only after authenticated RBAC guard',async({page})=>{
  const seen=await fixture(page,'admin',['audit.read']);await page.goto('http://127.0.0.1:5174/audit');
  await page.getByLabel('账号',{exact:true}).fill('admin');await page.getByLabel('密码',{exact:true}).fill('TEST_ONLY_password');await page.getByRole('button',{name:'登录工作台'}).click();expect(seen.some(p=>p.endsWith('/login'))).toBe(false);
  await page.getByLabel('动态验证码',{exact:true}).fill('123456');await page.getByRole('button',{name:'登录工作台'}).click();await expect(page).toHaveURL('http://127.0.0.1:5174/audit');await expect(page.getByRole('cell',{name:'auth.sessions.revoked-others',exact:true})).toBeVisible();await page.screenshot({path:'test-results/admin-audit.png',fullPage:true});
});
for(const realm of ['merchant','admin'] as const)test(`${realm} sensitive device action obtains and immediately consumes action-bound proof`,async({page})=>{
  const seen=await fixture(page,realm,realm==='merchant'?['store.read']:['audit.read']);await page.goto(`http://127.0.0.1:${realm==='merchant'?5173:5174}/sessions`);await login(page,realm);await expect(page.getByText('当前设备',{exact:true})).toBeVisible();
  await page.getByRole('button',{name:'注销其他设备',exact:true}).click();expect(seen.some(p=>p.endsWith('/reverify'))).toBe(false);
  await page.getByLabel('再次输入密码').fill('TEST_ONLY_password');if(realm==='admin')await page.getByLabel('新的动态验证码').fill('654321');await page.getByRole('button',{name:'验证并注销其他设备',exact:true}).click();await expect(page.getByRole('status')).toHaveText('其他设备的会话已注销。');
  expect(seen.findIndex(p=>p.endsWith('/reverify'))).toBeLessThan(seen.findIndex(p=>p.endsWith('/revoke-others')));expect(await page.evaluate(()=>JSON.stringify(localStorage))).not.toContain('proof');
});
test('login error shows request ID without accepting a session',async({page})=>{
  await page.route('**/api/v1/**',route=>route.fulfill({status:401,contentType:'application/json',body:JSON.stringify({error:{code:'LOGIN_FAILED',message:'failed',retryable:false,details:{}},meta})}));await page.goto('http://127.0.0.1:5173/login');await login(page,'merchant');await expect(page.getByRole('alert')).toContainText(meta.request_id);await expect(page).toHaveURL(/\/login$/);
});

test('admin taxonomy route requires permission',async({page})=>{
  await fixture(page,'admin',[]);await page.goto('http://127.0.0.1:5174/pet-taxonomy');await login(page,'admin');await expect(page).toHaveURL(/\/denied$/);await expect(page.getByRole('link',{name:'宠物分类',exact:true})).toHaveCount(0);
});
test('taxonomy command requires fresh reverify and clears credentials',async({page})=>{
  const seen=await fixture(page,'admin',['pet.taxonomy.read','pet.taxonomy.write'],'pet.taxonomy.write');await page.goto('http://127.0.0.1:5174/pet-taxonomy');await login(page,'admin');await expect(page.getByRole('heading',{name:'宠物分类与年龄规则'})).toBeVisible();
  const form=page.locator('form').filter({has:page.getByRole('heading',{name:'维护分类词典'})});await form.getByLabel('名称',{exact:true}).fill('布偶猫');await form.getByLabel('所属父分类').selectOption('cat-root');await expect(form.getByRole('button',{name:'保存词典项'})).toBeDisabled();
  await page.getByLabel('再次输入密码').fill('TEST_ONLY_password');await page.getByLabel('新的动态验证码').fill('654321');await form.getByRole('button',{name:'保存词典项'}).click();await expect(page.getByRole('status')).toHaveText('已保存，操作已记录。');await expect(page.getByLabel('再次输入密码')).toHaveValue('');await expect(page.getByLabel('新的动态验证码')).toHaveValue('');expect(seen.findIndex(p=>p.endsWith('/reverify'))).toBeLessThan(seen.findIndex(p=>p.endsWith('/pet-taxonomy/species')));
  await page.screenshot({path:'test-results/m31-admin-taxonomy.png',fullPage:true});
});

test('catalog route denies missing permission and does not call catalog API',async({page})=>{
 const seen=await fixture(page,'merchant',[]);await page.goto('http://127.0.0.1:5173/catalog');await login(page,'merchant');await expect(page).toHaveURL(/\/denied$/);expect(seen.some(x=>x.endsWith('/catalog/search'))).toBe(false);
});
test('read-only catalog staff cannot see mutation or reverify controls',async({page})=>{
 await fixture(page,'admin',['catalog.standard.read']);await page.goto('http://127.0.0.1:5174/catalog');await login(page,'admin');await expect(page.getByRole('heading',{name:'标准商品与审核'})).toBeVisible();await expect(page.getByText('尚无标准商品。')).toBeVisible();await expect(page.getByLabel('再次输入密码')).toHaveCount(0);await expect(page.getByText('新建品牌、商品与规格',{exact:true})).toHaveCount(0);await expect(page.locator('input[type=file]')).toHaveCount(0);
});
test('brand creation refreshes the accessible SPU selector and clears credentials',async({page})=>{
 await fixture(page,'admin',['catalog.standard.read','catalog.standard.write'],'catalog.standard.write');
 const brands:{id:string;name:string;source_ref:string;status:string}[]=[];
 await page.route('**/api/v1/admin/brands',async route=>{if(route.request().method()==='POST'){expect(route.request().headers()['x-reverify-token']).toBe('one-use-proof');brands.push({id:meta.request_id,name:'TEST ONLY brand',source_ref:'TEST ONLY source',status:'ACTIVE'});await route.fulfill({status:201,contentType:'application/json',body:JSON.stringify({data:{id:meta.request_id,status:'ACTIVE'},meta})});}else await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({data:brands,page:{next_cursor:null,has_more:false},meta})});});
 await page.goto('http://127.0.0.1:5174/catalog');await login(page,'admin');await page.getByText('新建品牌、商品与规格',{exact:true}).click();
 const brand=page.locator('form').filter({has:page.getByRole('heading',{name:'品牌',exact:true})});await brand.getByLabel('名称',{exact:true}).fill('TEST ONLY brand');await brand.getByLabel('来源依据',{exact:true}).fill('TEST ONLY source');await page.getByLabel('再次输入密码').fill('TEST_ONLY_password');await page.getByLabel('新的动态验证码').fill('654321');await brand.getByRole('button',{name:'创建品牌'}).click();await expect(page.getByRole('status')).toHaveText('已保存，操作已记录。');await expect(page.getByLabel('再次输入密码')).toHaveValue('');
 const spu=page.locator('form').filter({has:page.getByRole('heading',{name:'标准商品',exact:true})});await spu.getByRole('combobox',{name:'品牌',exact:true}).selectOption({label:'TEST ONLY brand'},{timeout:10000});await expect(spu.getByRole('combobox',{name:'品牌',exact:true})).toHaveValue(meta.request_id);
});
