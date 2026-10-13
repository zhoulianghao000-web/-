import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m6.8.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday V1 Security Maintenance Runtime API';doc.info.version='1.0.7';
doc['x-json-request-max-bytes']=3*1024*1024;doc['x-media-request-max-bytes']=5*1024*1024;
for(const item of Object.values(doc.paths))for(const op of Object.values(item)){
  if(!op.responses)continue;
  for(const [status,description] of [['413','Request body exceeds the bounded JSON or media policy'],['502','Local gateway cannot reach the backend; retry after services recover']]){
    op.responses[status]={description,content:{'application/json':{schema:{$ref:'#/components/schemas/ErrorEnvelope'}}}};
  }
}
const output=YAML.stringify(doc,{lineWidth:0}),target=new URL('../openapi/pawday-v1.0.7.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw Error('Security maintenance contract drift');}else await fs.writeFile(target,output);
