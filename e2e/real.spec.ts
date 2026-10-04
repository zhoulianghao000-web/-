import {createHmac} from 'node:crypto';
import {test,expect} from '@playwright/test';
test.skip(!process.env.PAWDAY_REAL_E2E,'Run in the mandatory real-infrastructure CI job');
function totp(){
  const secret=process.env.PAWDAY_DEMO_ADMIN_TOTP_BASE64;
  if(!secret)throw new Error('Real admin TOTP fixture must be explicitly configured');
  const counter=Buffer.alloc(8);counter.writeBigUInt64BE(BigInt(Math.floor(Date.now()/30000)));
  const hash=createHmac('sha1',Buffer.from(secret,'base64')).update(counter).digest();const offset=hash[19]!&15;
  return String((hash.readUInt32BE(offset)&0x7fffffff)%1000000).padStart(6,'0');
}
test('real merchant login, scope, refresh rotation and cross-realm rejection',async({page,request})=>{
  const password=process.env.PAWDAY_DEMO_MERCHANT_PASSWORD;if(!password)throw new Error('Real merchant fixture required');
  await page.goto('http://127.0.0.1:5173/stores');await page.getByLabel('账号',{exact:true}).fill('local-staff-a');await page.getByLabel('密码',{exact:true}).fill(password);await page.getByRole('button',{name:'登录工作台'}).click();
  await expect(page).toHaveURL('http://127.0.0.1:5173/stores');await expect(page.getByRole('heading',{name:'LOCAL DEMO Store a'})).toBeVisible();await expect(page.getByText('LOCAL DEMO Store b',{exact:true})).toHaveCount(0);
  const login=await request.post('http://127.0.0.1:8080/api/v1/merchant/auth/login',{data:{login_name:'local-staff-b',password,device_id:'ci-real-client'}});expect(login.ok()).toBe(true);const tokens=(await login.json()).data;
  const badRealm=await request.get('http://127.0.0.1:8080/api/v1/admin/me',{headers:{Authorization:`Bearer ${tokens.access_token}`}});expect(badRealm.status()).toBe(403);
  const refresh=await request.post('http://127.0.0.1:8080/api/v1/merchant/auth/refresh',{data:{refresh_token:tokens.refresh_token}});expect(refresh.ok()).toBe(true);const rotated=(await refresh.json()).data;expect(rotated.refresh_token).not.toBe(tokens.refresh_token);
  const me=await request.get('http://127.0.0.1:8080/api/v1/merchant/me',{headers:{Authorization:`Bearer ${rotated.access_token}`}});expect(me.ok()).toBe(true);expect((await me.json()).data.realm).toBe('MERCHANT');
  await page.getByRole('link',{name:'账号与设备'}).click();await expect(page.getByText('当前设备',{exact:true})).toBeVisible();await page.getByRole('button',{name:'注销其他设备',exact:true}).click();await page.getByLabel('再次输入密码').fill(password);await page.getByRole('button',{name:'验证并注销其他设备',exact:true}).click();await expect(page.getByRole('status')).toHaveText('其他设备的会话已注销。');
  await page.getByRole('button',{name:'退出登录'}).click();await expect(page).toHaveURL(/\/login$/);
});
test('real administrator TOTP login and audit HTTP response',async({page})=>{
  test.setTimeout(120000);
  const password=process.env.PAWDAY_DEMO_ADMIN_PASSWORD;if(!password)throw new Error('Real admin fixture required');
  await page.goto('http://127.0.0.1:5174/audit');await page.getByLabel('账号',{exact:true}).fill('local-admin');await page.getByLabel('密码',{exact:true}).fill(password);await page.getByLabel('动态验证码',{exact:true}).fill(totp());await page.getByRole('button',{name:'登录工作台'}).click();
  await expect(page).toHaveURL('http://127.0.0.1:5174/audit');await expect(page.getByRole('table')).toBeVisible();await expect(page.getByRole('alert')).toHaveCount(0);
  await page.getByRole('link',{name:'账号与设备'}).click();await expect(page.getByText('当前设备',{exact:true})).toBeVisible();await page.getByRole('button',{name:'注销其他设备',exact:true}).click();
  // A login TOTP is single-use. Wait for the next real step before reverify.
  const currentStep=Math.floor(Date.now()/30000);await expect.poll(()=>Math.floor(Date.now()/30000),{timeout:32000,intervals:[250]}).toBeGreaterThan(currentStep);
  await page.getByLabel('再次输入密码').fill(password);await page.getByLabel('新的动态验证码').fill(totp());await page.getByRole('button',{name:'验证并注销其他设备',exact:true}).click();await expect(page.getByRole('status')).toHaveText('其他设备的会话已注销。');
  await page.getByRole('link',{name:'审计记录'}).click();await expect(page.getByRole('cell',{name:'auth.sessions.revoked-others',exact:true}).first()).toBeVisible();
  await page.getByRole('link',{name:'宠物分类',exact:true}).click();await expect(page.getByRole('heading',{name:'宠物分类与年龄规则'})).toBeVisible();
  const form=page.locator('form').filter({has:page.getByRole('heading',{name:'维护分类词典'})});await form.getByLabel('类型').selectOption('allergens');await form.getByLabel('名称',{exact:true}).fill(`CI REAL TEST allergen ${Date.now()}`);
  const taxonomyStep=Math.floor(Date.now()/30000);await expect.poll(()=>Math.floor(Date.now()/30000),{timeout:32000,intervals:[250]}).toBeGreaterThan(taxonomyStep);
  await page.getByLabel('再次输入密码').fill(password);await page.getByLabel('新的动态验证码').fill(totp());await form.getByRole('button',{name:'保存词典项'}).click();await expect(page.getByRole('status')).toHaveText('已保存，操作已记录。');
  await page.getByRole('link',{name:'审计记录'}).click();await expect(page.getByRole('cell',{name:'pet.taxonomy.create',exact:true}).first()).toBeVisible();
});
