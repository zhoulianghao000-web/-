import {test,expect} from '@playwright/test';
for(const realm of ['merchant','admin'] as const){
 test(`pilot ${realm} keeps visible simulation label across login and dashboard`,async({page})=>{
  const meta={request_id:'00000000-0000-4000-8000-000000000001',correlation_id:'00000000-0000-4000-8000-000000000001'};
  await page.route('**/api/v1/**',async route=>{
   const r=route.request(),path=new URL(r.url()).pathname;expect(r.headers()['x-pawday-pilot']).toBe('simulated-v1');
   const data=path.endsWith('/login')?{access_token:'TEST_ACCESS',refresh_token:'TEST_REFRESH',expires_in:900,session_id:meta.request_id,user_id:null}:path.endsWith('/me')?{id:meta.request_id,realm:realm.toUpperCase(),merchant_id:realm==='merchant'?meta.request_id:null,user_id:null,session_id:meta.request_id,permissions:[]}:[];
   if(!path.endsWith('/login'))expect(r.headers()['authorization']).toBe('Bearer TEST_ACCESS');
   await route.fulfill({status:200,headers:{'Content-Type':'application/json','X-Pawday-Environment':'SIMULATED_PILOT'},body:JSON.stringify({data,meta})});
  });
  await page.goto(`http://127.0.0.1:${realm==='merchant'?5173:5174}/login`);
  await expect(page.getByText('模拟试点 · 仅测试账号 · 不发生真实交易、短信或 AI 调用',{exact:true})).toBeVisible();
  await page.getByLabel('账号',{exact:true}).fill(realm==='merchant'?'local-staff-a':'local-admin');await page.getByLabel('密码',{exact:true}).fill('TEST_ONLY_password');
  if(realm==='admin')await page.getByLabel('动态验证码',{exact:true}).fill('123456');
  await page.getByRole('button',{name:'登录工作台'}).click();await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByText('模拟试点 · 仅测试账号 · 不发生真实交易、短信或 AI 调用',{exact:true})).toBeVisible();
 });
}
