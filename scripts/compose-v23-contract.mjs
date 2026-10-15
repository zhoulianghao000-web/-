import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-v2.2.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday V2.3 Merchant App and Business Analytics';doc.info.version='2.0.3';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),obj=p=>({type:'object',additionalProperties:false,properties:p,required:Object.keys(p)}),date={type:'string',format:'date'},uuid={type:'string',format:'uuid'},str={type:'string'},integer={type:'integer',minimum:-9007199254740991,maximum:9007199254740991};
s.BusinessMetrics=obj(Object.fromEntries(['paid_suborders','refund_count','paid_fen','refund_fen','net_fen','commission_net_fen','merchant_net_fen'].map(k=>[k,{...integer,...(['paid_suborders','refund_count','paid_fen','refund_fen'].includes(k)?{minimum:0}:{})}])));
s.BusinessDay=obj({date,metrics:ref('BusinessMetrics')});
s.BusinessAnalytics=obj({merchant_id:uuid,store_id:{anyOf:[uuid,{type:'null'}]},timezone:{...str,enum:['Asia/Shanghai']},from:date,to:date,as_of:{type:'string',format:'date-time'},source:{...str,enum:['IMMUTABLE_MERCHANT_LEDGER']},scope_policy:{...str,enum:['WHOLE_AUTHORIZED_SUBORDER']},simulated:{type:'boolean'},totals:ref('BusinessMetrics'),days:{type:'array',minItems:1,maxItems:90,items:ref('BusinessDay')}});
s.BusinessAnalyticsEnvelope=obj({data:ref('BusinessAnalytics'),meta:ref('Meta')});
for(const realm of ['merchant','admin']){
 const path=realm==='merchant'?'/merchant/business-analytics':'/admin/merchants/{id}/business-analytics';
 const responses={200:{description:'Whole authorized suborders only; ledger-day cash flows, not income or withdrawable balance',content:{'application/json':{schema:ref('BusinessAnalyticsEnvelope')}}}};
 for(const code of [400,401,403,404,409,422,429,503])responses[code]={description:'Invalid range, denied scope, overflow or unavailable facts',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const parameters=[...realm==='admin'?[{name:'id',in:'path',required:true,schema:uuid}]:[],...['from','to'].map(name=>({name,in:'query',required:true,schema:date})),{name:'store_id',in:'query',schema:uuid}];
 doc.paths[path]={get:{operationId:realm+'_business_analytics',tags:[realm],summary:'Business ledger analytics over 1–90 Shanghai days',security:[{[realm+'Bearer']:[]}],parameters,responses,'x-implemented-in':'V2.3'}};
}
const output=YAML.stringify(doc,{lineWidth:0}),target=new URL('../openapi/pawday-v2.3.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw Error('V2.3 contract drift');}else await fs.writeFile(target,output);
