import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-v1.0.9.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday V2.1 Quotation History';doc.info.version='2.0.1';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),nullable=x=>({anyOf:[x,{type:'null'}]}),obj=properties=>({type:'object',additionalProperties:false,properties,required:Object.keys(properties)}),uuid={type:'string',format:'uuid'},time={type:'string',format:'date-time'},date={type:'string',format:'date'},fen={type:'integer',minimum:1,maximum:1000000000},state={type:'string',enum:['DRAFT','ACTIVE','PAUSED','FROZEN','DELISTED']};
s.PriceHistoryPoint=obj({date,sale_price_fen:nullable(fen),member_price_fen:nullable(fen),sale_status:nullable(state),recorded_at:nullable(time),publicly_recorded:nullable({type:'boolean'})});
s.OfferPriceHistory=obj({offer_id:uuid,sku_id:uuid,days:{type:'integer',enum:[30,90]},timezone:{type:'string',enum:['Asia/Shanghai']},currency:{type:'string',enum:['CNY']},basis:{type:'string',enum:['DAILY_LAST_RECORDED_QUOTATION']},as_of:time,from_date:date,to_date:date,observed_from:nullable(time),current_sale_price_fen:fen,current_member_price_fen:nullable(fen),offer_version:{type:'integer',minimum:0},observed_days:{type:'integer',minimum:0,maximum:90},lowest_recorded_daily_sale_price_fen:nullable(fen),highest_recorded_daily_sale_price_fen:nullable(fen),points:{type:'array',minItems:30,maxItems:90,items:ref('PriceHistoryPoint')}});
s.OfferPriceHistoryEnvelope=obj({data:ref('OfferPriceHistory'),meta:ref('Meta')});
for(const realm of ['public','consumer','merchant','admin']){
 const responses={200:{description:'30/90 Shanghai calendar daily last recorded quotations; unknown or nonpublic prices are null, no backfilled history',content:{'application/json':{schema:ref('OfferPriceHistoryEnvelope')}}}};
 for(const status of [400,401,403,404,413,429,502,503])responses[status]={description:'Rejected without disclosing foreign or nonpublic quotations',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 doc.paths[`/${realm}/offers/{id}/price-history`]={get:{operationId:`get_${realm}_offers_id_price_history`,summary:'Read observed quotation history',tags:[realm],security:realm==='public'?[]:[{[`${realm}Bearer`]:[]}],parameters:[{name:'id',in:'path',required:true,schema:uuid},{name:'days',in:'query',schema:{type:'integer',enum:[30,90],default:30}}],responses,'x-implemented-in':'V2.1',...(realm==='merchant'||realm==='admin'?{'x-permission':realm==='admin'?'offer.admin.read':'offer.read'}:{})}};
}
const output=YAML.stringify(doc,{lineWidth:0}),target=new URL('../openapi/pawday-v2.1.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw Error('V2.1 quotation history contract drift');}else await fs.writeFile(target,output);
