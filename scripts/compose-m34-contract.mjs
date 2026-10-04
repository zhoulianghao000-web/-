import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m3.3.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday M3.4 Consumer Catalog and Deterministic Fit API';doc.info.version='0.3.4';
doc.info.description='Implemented catalog browse, sourced deterministic fit, comparison and real business search projection. Orders and checkout follow in M4.';
const s=doc.components.schemas;
const ref=n=>({$ref:`#/components/schemas/${n}`});
const str=(max=500)=>({type:'string',minLength:1,maxLength:max});
const id=()=>({type:'string',format:'uuid'});
const num=()=>({type:'integer',minimum:0,maximum:9007199254740991});
const array=items=>({type:'array',items});
const nullable=x=>({anyOf:[x,{type:'null'}]});
const obj=properties=>({type:'object',additionalProperties:false,properties,required:Object.keys(properties)});
s.PublicAllergen=obj({id:id(),name:str(160)});
s.ConsumerOffer=obj({offer_id:id(),merchant_id:id(),merchant_name:str(160),store_id:nullable(id()),sale_price_fen:num(),member_price_fen:nullable(num()),fulfillment_sla:str(),offer_version:num(),available_qty:num(),inventory_version:num(),in_stock:{type:'boolean'}});
s.ConsumerStandard=obj({id:id(),spu_id:id(),sku_code:str(80),weight_g:num(),package_unit:str(40),name:str(160),pet_category:{type:'string',enum:['CAT','DOG','AQUATIC','BIRD','SMALL_PET']},category:str(80),brand:str(160),catalog_standard_version_id:id(),ingredients:array(str(200)),nutrients:array(ref('CatalogNutrient')),allergens_known:{type:'boolean'},life_stage_ids:array(id()),source_refs:array(str(2000)),source_updated_on:{type:'string',format:'date'},published_at:{type:'string',format:'date-time'},allergens:array(ref('PublicAllergen'))});
// Sourced nutrient schema is shared with standard creation; no field is inferred.
s.ConsumerProduct=obj({...s.ConsumerStandard.properties,offers:array(ref('ConsumerOffer'))});
s.ConsumerSpu=obj({spu_id:id(),skus:array(ref('ConsumerStandard'))});
s.FitConflict={type:'object',additionalProperties:false,properties:{type:{type:'string',enum:['ALLERGEN_CONFLICT','PET_CATEGORY_MISMATCH','LIFE_STAGE_MISMATCH']},allergen_id:id(),message:str()},required:['type','message']};
s.ProductFit=obj({sku_id:id(),pet_id:id(),pet_version:num(),result:{type:'string',enum:['SUITABLE','HAS_WARNING','NOT_RECOMMENDED','INSUFFICIENT_DATA']},display_label:str(),hard_conflicts:array(ref('FitConflict')),uncertainties:array(str(100)),catalog_standard_version_id:id(),fit_rule_version:{type:'string',const:'pawday-fit-1'},life_stage_id:nullable(id())});
s.CompareInput={type:'object',additionalProperties:false,properties:{sku_ids:{...array(id()),minItems:2,maxItems:4,uniqueItems:true},pet_id:id()},required:['sku_ids']};
s.CompareItem=obj({standard:ref('ConsumerStandard'),offers:array(ref('ConsumerOffer')),fit:nullable(ref('ProductFit'))});s.ProductComparison=obj({items:array(ref('CompareItem'))});
function add(path,response,{list=false,request,method='get',publicApi=false,params=[]}={}){
 const name=response+(list?'List':'')+'Envelope';s[name]=obj({data:list?array(ref(response)):ref(response),...(list?{page:ref('Page')}:{}),meta:ref('Meta')});
 const responses={200:{description:'Authoritative current catalog data',content:{'application/json':{schema:ref(name)}}}};
 for(const code of [400,401,403,404,409,422,429,503])responses[code]={description:'Rejected or service unavailable',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const op={operationId:`${method}_${path.replace(/^\//,'').replaceAll(/[/{\}-]/g,'_').replace(/_+$/,'')}`,summary:`${method.toUpperCase()} ${path}`,tags:[publicApi?'public':'consumer'],security:publicApi?[]:[{consumerBearer:[]}],parameters:[...[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:id()})),...params],responses,'x-implemented-in':'M3.4'};
 if(request)op.requestBody={required:true,content:{'application/json':{schema:ref(request)}}};(doc.paths[path]??={})[method]=op;
}
for(const realm of ['public','consumer']){
 const opts={publicApi:realm==='public'};
 add(`/${realm}/spus/{id}`,'ConsumerSpu',opts);add(`/${realm}/skus/{id}`,'ConsumerStandard',opts);add(`/${realm}/skus/{id}/offers`,'ConsumerOffer',{...opts,list:true});
 add(`/${realm}/products`,'ConsumerProduct',{...opts,list:true,params:[{name:'q',in:'query',schema:{type:'string',maxLength:160}},{name:'pet_category',in:'query',schema:s.ConsumerStandard.properties.pet_category},{name:'cursor',in:'query',schema:id()},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:20}}]});
}
add('/consumer/skus/{id}/fit','ProductFit',{params:[{name:'pet_id',in:'query',required:true,schema:id()}]});
add('/consumer/products/compare','ProductComparison',{method:'post',request:'CompareInput'});
const output=YAML.stringify(doc,{lineWidth:110}),target=new URL('../openapi/pawday-m3.4.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('M3.4 contract drift');console.log('M3.4 contract composition PASS');}else await fs.writeFile(target,output);
