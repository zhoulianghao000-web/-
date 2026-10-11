import http from 'node:http';
import {createReadStream} from 'node:fs';
import {readFile,realpath,stat} from 'node:fs/promises';
import {resolve,relative,isAbsolute,extname} from 'node:path';
import {pathToFileURL} from 'node:url';

const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json','.png':'image/png','.ico':'image/x-icon','.svg':'image/svg+xml','.wasm':'application/wasm','.woff2':'font/woff2','.ttf':'font/ttf','.apk':'application/vnd.android.package-archive'};
const inside=(base,file)=>{const rel=relative(base,file);return !rel.startsWith('..')&&!isAbsolute(rel);};
function reply(res,status,body,type='application/json; charset=utf-8'){
  res.writeHead(status,{'Content-Type':type,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(typeof body==='string'?body:JSON.stringify(body));
}
export async function createDesktopServers({root,ports=[4172,4173,4174,4175],backendPort=8086}){
  root=await realpath(root);const servers=[];
  const sites=[['portal','desktop'],['merchant','release/merchant-web'],['admin','release/admin-web'],['consumer','release/consumer-preview']];
  try{
    for(let i=0;i<sites.length;i++){
      const [site,dir]=sites[i],base=await realpath(resolve(root,dir));
      if(!inside(root,base))throw new Error('Site directory outside delivery');
      const server=http.createServer(async(req,res)=>{
        try{
          const port=server.address().port,host=`127.0.0.1:${port}`;
          if(req.headers.host!==host||req.headers.origin&&req.headers.origin!==`http://${host}`){reply(res,403,{error:'LOCAL_ORIGIN_REQUIRED'});return;}
          const url=new URL(req.url,`http://${host}`);
          if(url.pathname==='/desktop-identity'){reply(res,200,{product:'PawdayV1',site,mode:'SIMULATED_PILOT',root});return;}
          if(url.pathname==='/desktop-status'){
            const upstream=await fetch(`http://127.0.0.1:${backendPort}/actuator/health`,{signal:AbortSignal.timeout(3000)}).catch(()=>null);
            let healthy=false;if(upstream?.ok)healthy=(await upstream.json()).status==='UP';
            reply(res,200,{healthy,mode:'SIMULATED_PILOT',production_ready:false,pending_production_gates:14});return;
          }
          if(site!=='portal'&&url.pathname.startsWith('/api/v1/')){
            if(!['GET','POST','PUT','PATCH','DELETE'].includes(req.method)){reply(res,405,{error:'METHOD_NOT_ALLOWED'});return;}
            const headers={...req.headers,host:`127.0.0.1:${backendPort}`};delete headers.connection;delete headers['transfer-encoding'];delete headers['content-length'];
            const upstream=http.request({hostname:'127.0.0.1',port:backendPort,path:url.pathname+url.search,method:req.method,headers,timeout:15000},r=>{
              const safeHeaders={...r.headers,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};delete safeHeaders.connection;
              res.writeHead(r.statusCode,safeHeaders);r.pipe(res);
            });
            let size=0;req.on('data',chunk=>{size+=chunk.length;if(size>64*1024*1024){upstream.destroy();if(!res.headersSent)reply(res,413,{error:'BODY_TOO_LARGE'});}});
            upstream.on('timeout',()=>upstream.destroy());upstream.on('error',()=>{if(!res.headersSent)reply(res,502,{error:'LOCAL_BACKEND_UNAVAILABLE'});else res.destroy();});
            req.on('aborted',()=>upstream.destroy());req.pipe(upstream);return;
          }
          if(!['GET','HEAD'].includes(req.method)){reply(res,405,{error:'METHOD_NOT_ALLOWED'});return;}
          let path=decodeURIComponent(url.pathname);
          if(path.includes('\\')||path.includes('\0')){reply(res,404,{error:'NOT_FOUND'});return;}
          let file;
          if(site==='portal'&&path==='/consumer.apk')file=resolve(root,'release/consumer.apk');
          else{
            file=resolve(base,'.'+path);
            if(!inside(base,file)){reply(res,404,{error:'NOT_FOUND'});return;}
            if(path.endsWith('/'))file=resolve(file,'index.html');
            try{if((await stat(file)).isDirectory())file=resolve(file,'index.html');}
            catch{if(!extname(path)&&site!=='portal')file=resolve(base,'index.html');}
          }
          const actual=await realpath(file).catch(()=>null);
          const allowed=site==='portal'&&path==='/consumer.apk'?resolve(root,'release/consumer.apk'):base;
          if(!actual||!(actual===allowed||inside(allowed,actual))){reply(res,404,{error:'NOT_FOUND'});return;}
          const info=await stat(actual);if(!info.isFile()){reply(res,404,{error:'NOT_FOUND'});return;}
          res.writeHead(200,{'Content-Type':types[extname(actual)]||'application/octet-stream','Content-Length':info.size,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...(path==='/consumer.apk'?{'Content-Disposition':'attachment; filename="PawdayV1-Consumer-debug.apk"'}:{})});
          if(req.method==='HEAD')res.end();else createReadStream(actual).on('error',()=>res.destroy()).pipe(res);
        }catch{if(!res.headersSent)reply(res,400,{error:'INVALID_LOCAL_REQUEST'});else res.destroy();}
      });
      await new Promise((yes,no)=>{server.once('error',no);server.listen(ports[i],'127.0.0.1',yes);});servers.push(server);
    }
    return servers;
  }catch(error){await Promise.all(servers.map(s=>new Promise(r=>s.close(r))));throw error;}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  const root=resolve(process.argv[2]||'.');
  // A delivery must contain the marked, previously verified pilot backend and apps.
  const manifest=JSON.parse(await readFile(resolve(root,'release/desktop-manifest.json'),'utf8'));
  if(manifest.mode!=='SIMULATED_PILOT'||manifest.production_ready!==false)throw new Error('Explicit simulation delivery required');
  const servers=await createDesktopServers({root});
  for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{for(const s of servers)s.close();});
  process.stdout.write('PawdayV1 local simulation ready: http://127.0.0.1:4172\n');
}
