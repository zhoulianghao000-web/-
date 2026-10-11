import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m5.5.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday M6.6.2 Simulated Pilot Runtime API';doc.info.version='0.6.7';
doc.info.description='Dedicated invited pilot only. Generated fixtures and unverified information are never production approval. Ordinary mode keeps the M5.5 behavior.';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),obj=properties=>({type:'object',additionalProperties:false,properties,required:Object.keys(properties)}),str={type:'string'},bool={type:'boolean'};
s.PilotMaterial=obj({kind:{type:'string',enum:['SYNTHETIC','UNVERIFIED']},label:str,generated_fixture:bool,production_approved:{type:'boolean',const:false},baseline_version:{type:'string',const:'cq-v1'},media_path:{anyOf:[{type:'string',pattern:'^/api/v1/consumer/pilot/skus/[0-9a-f-]{36}/media$'},{type:'null'}]}});
for(const name of ['ConsumerStandard','ConsumerProduct','ProductFit','CatalogStandard'])if(s[name])s[name].properties.pilot_material=ref('PilotMaterial');
// Read models permit absent material; write validation still requires nonempty sourced ingredients.
for(const name of ['ConsumerStandard','ConsumerProduct','CatalogStandard'])if(s[name]?.properties.ingredients)s[name].properties.ingredients={...s[name].properties.ingredients,minItems:0};
s.PilotBaseline=obj({baseline_version:{type:'string',const:'cq-v1'},definition_sha256:{type:'string',pattern:'^[0-9a-f]{64}$'},merchant_count:{type:'integer',const:2},store_count:{type:'integer',const:2},consumer_count:{type:'integer',const:20},sku_count:{type:'integer',const:20},generated_fixture:{type:'boolean',const:true},production_approved:{type:'boolean',const:false}});
s.PilotBaselineEnvelope=obj({data:ref('PilotBaseline'),meta:ref('Meta')});
for(const [path,binary] of [['/consumer/pilot/baseline',false],['/consumer/pilot/skus/{sku_id}/media',true]]){
 const responses={200:{description:binary?'Authenticated generated image; current published reference only':'Versioned synthetic round summary without identity lists',content:binary?{'image/png':{schema:{type:'string',format:'binary'}}}:{'application/json':{schema:ref('PilotBaselineEnvelope')}}}};
 for(const status of [400,401,403,404,409,503])responses[status]={description:'Rejected without exposing private media',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 doc.paths[path]={get:{operationId:binary?'get_consumer_pilot_sku_media':'get_consumer_pilot_baseline',summary:binary?'Read invited pilot image':'Read pilot baseline version',tags:['consumer'],security:[{consumerBearer:[]}],parameters:[{name:'X-Pawday-Pilot',in:'header',required:true,schema:{type:'string',const:'simulated-v1'}},...(binary?[{name:'sku_id',in:'path',required:true,schema:{type:'string',format:'uuid'}}]:[])],responses,'x-implemented-in':'M6.6.2'}};
}
const target=new URL('../openapi/pawday-m6.6.2.yaml',import.meta.url),output=YAML.stringify(doc,{lineWidth:0});
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('M6.6.2 contract drift');}else await fs.writeFile(target,output);
