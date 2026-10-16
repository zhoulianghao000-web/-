import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,rm,symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import http from 'node:http';
import {createDesktopServers} from '../desktop-server.mjs';

test('local desktop delivery serves four sites and proxies actual HTTP without injecting authority',async t=>{
 const root=await mkdtemp(join(tmpdir(),'pawday-desktop-'));
 const paths=['desktop','release/merchant-web','release/admin-web','release/consumer-preview'];
 for(const path of paths){await mkdir(join(root,path),{recursive:true});await writeFile(join(root,path,'index.html'),`<h1>${path}</h1>`);}
 await writeFile(join(root,'secret.env'),'SHOULD_NOT_BE_SERVED');await writeFile(join(root,'release/consumer.apk'),'TEST_APK');await writeFile(join(root,'release/merchant.apk'),'TEST_MERCHANT_APK');
 const seen=[];const backend=http.createServer((req,res)=>{seen.push({url:req.url,headers:req.headers});res.setHeader('Content-Type','application/json');res.setHeader('X-Pawday-Environment','SIMULATED_PILOT');const done=()=>res.end(JSON.stringify(req.url==='/actuator/health'?{status:'UP'}:{data:{ok:true}}));req.on('error',()=>{});req.on('end',done);req.resume();});
 await new Promise(r=>backend.listen(0,'127.0.0.1',r));
 const servers=await createDesktopServers({root,ports:[0,0,0,0],backendPort:backend.address().port});
 const urls=servers.map(s=>`http://127.0.0.1:${s.address().port}`);
 try{
  await t.test('only consumer Android is served, including deliveries with stale merchant files',async()=>{
   await mkdir(join(root,'release/merchant-web/app'),{recursive:true});
   await writeFile(join(root,'release/merchant-web/app/index.html'),'RETIRED_MERCHANT_PREVIEW');
   await writeFile(join(root,'release/merchant-web/app/main.dart.js'),'RETIRED_MERCHANT_SCRIPT');
   await writeFile(join(root,'desktop/admin.apk'),'RETIRED_ADMIN_APK');
   for(const url of urls){
    for(const path of ['/merchant.apk','/admin.apk','/%6derchant.apk'])assert.equal((await fetch(url+path)).status,404);
   }
   for(const path of ['/app','/app/','/app/index.html','/app/main.dart.js','/%61pp/','/APP/','/%2fapp/','/unused%2f..%2fapp/index.html'])assert.equal((await fetch(urls[1]+path)).status,404);
   assert.equal((await fetch(urls[0]+'/merchant.apk',{method:'HEAD'})).status,404);
   assert.equal((await fetch(urls[0]+'/consumer.apk',{method:'HEAD'})).status,200);
   for(const url of urls.slice(1))assert.equal((await fetch(url+'/consumer.apk')).status,404);
  });
  await t.test('four real static sites and SPA return paths',async()=>{
   for(let i=0;i<4;i++){assert.equal(await(await fetch(urls[i])).text(),`<h1>${paths[i]}</h1>`);assert.equal((await(await fetch(urls[i]+'/desktop-identity')).json()).site,['portal','merchant','admin','consumer'][i]);}
   assert.equal((await fetch(urls[1]+'/orders')).status,200);assert.equal((await fetch(urls[0]+'/missing.js')).status,404);
  });
  await t.test('login pages cannot be embedded by a hostile site',async()=>{
   const page=await fetch(urls[2]+'/login');assert.equal(page.headers.get('x-frame-options'),'DENY');assert.match(page.headers.get('content-security-policy'),/frame-ancestors 'none'/);assert.equal(page.headers.get('referrer-policy'),'no-referrer');
   assert.equal((await fetch(urls[2]+'/login',{headers:{'Sec-Fetch-Dest':'iframe'}})).status,403);
  });
  await t.test('oversized declared and chunked JSON is rejected without killing the local service',async()=>{
   const oversized='x'.repeat(3*1024*1024+1);
   const response=await fetch(urls[1]+'/api/v1/admin/auth/login',{method:'POST',body:oversized});assert.equal(response.status,413);assert.equal((await response.json()).error.code,'REQUEST_BODY_TOO_LARGE');assert.equal(response.headers.get('x-pawday-environment'),'SIMULATED_PILOT');
   const chunked=new ReadableStream({start(c){c.enqueue(new TextEncoder().encode(oversized));c.close();}});
   assert.equal((await fetch(urls[1]+'/api/v1/admin/auth/login',{method:'POST',body:chunked,duplex:'half'})).status,413);
   assert.equal((await fetch(urls[0])).status,200);
  });
  await t.test('local JSON proxy retains pilot marker, bearer and idempotency headers',async()=>{
   const response=await fetch(urls[1]+'/api/v1/consumer/orders?limit=5',{method:'POST',headers:{'X-Pawday-Pilot':'simulated-v1',Authorization:'Bearer TEST_LOCAL','Idempotency-Key':'TEST_KEY','Content-Type':'application/json'},body:'{}'});
   assert.equal(response.status,200);assert.equal(response.headers.get('x-pawday-environment'),'SIMULATED_PILOT');assert.equal(response.headers.get('cache-control'),'no-store');
   const last=seen.at(-1);assert.equal(last.url,'/api/v1/consumer/orders?limit=5');assert.equal(last.headers.authorization,'Bearer TEST_LOCAL');assert.equal(last.headers['idempotency-key'],'TEST_KEY');
   await fetch(urls[1]+'/api/v1/consumer/me');assert.equal(seen.at(-1).headers.authorization,undefined);assert.equal(seen.at(-1).headers['x-pawday-pilot'],undefined);
  });
  await t.test('foreign origins, arbitrary files, encoded traversal and unsafe methods rejected',async()=>{
   assert.equal((await fetch(urls[1]+'/api/v1/consumer/me',{headers:{Origin:'https://outside.example'}})).status,403);
   for(const path of ['/secret.env','/%2e%2e%2fsecret.env','/%2e%2e%5csecret.env','/.pilot/config.env','/api/other','/missing.js'])assert.equal((await fetch(urls[0]+path)).status,404);
   assert.equal((await fetch(urls[0],{method:'POST'})).status,405);
  });
  await t.test('symlink escape never exposes private delivery files',async()=>{
   try{await symlink(join(root,'secret.env'),join(root,'desktop','escape.txt'));}catch(e){if(e.code==='EPERM'){t.diagnostic('Windows has no symlink privilege; traversal checks above remain active');return;}throw e;}
   assert.equal((await fetch(urls[0]+'/escape.txt')).status,404);
  });
  await t.test('health and APK are explicit safe resources; upstream loss is visible',async()=>{
   assert.equal((await(await fetch(urls[0]+'/desktop-status')).json()).healthy,true);
   const apk=await fetch(urls[0]+'/consumer.apk');assert.equal(await apk.text(),'TEST_APK');assert.match(apk.headers.get('content-disposition'),/attachment/);
   await new Promise(r=>backend.close(r));assert.equal((await(await fetch(urls[0]+'/desktop-status')).json()).healthy,false);const failure=await fetch(urls[1]+'/api/v1/consumer/me');assert.equal(failure.status,502);const value=await failure.json();assert.equal(value.error.code,'LOCAL_BACKEND_UNAVAILABLE');assert.equal(value.error.retryable,true);assert.equal(value.meta.request_id,failure.headers.get('x-request-id'));assert.equal(failure.headers.get('x-pawday-environment'),'SIMULATED_PILOT');
  });
 }finally{await Promise.all(servers.map(s=>new Promise(r=>s.close(r))));if(backend.listening)await new Promise(r=>backend.close(r));await rm(root,{recursive:true,force:true});}
});
