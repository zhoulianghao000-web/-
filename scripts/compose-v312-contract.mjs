import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-v3.1.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday V3.1.2 Simulated Booking Fulfillment';doc.info.version='3.0.2';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),obj=p=>({type:'object',additionalProperties:false,properties:p,required:Object.keys(p)});
const uuid={type:'string',format:'uuid'},time={type:'string',format:'date-time'},sim={type:'boolean',enum:[true]};
const status={type:'string',enum:['CHECKED_IN','COMPLETED','NO_SHOW','EXCEPTION']};
s.ServiceBooking.properties.status.enum.push(...status.enum);
s.BookingCredential=obj({booking_id:uuid,credential:{type:'string',pattern:'^[0-9a-f]{64}$'},valid_from:time,expires_at:time,simulated:sim});
s.BookingFulfillmentInput=obj({status,credential:{type:'string',maxLength:64},reason_code:{type:'string',enum:['','SERVICE_UNAVAILABLE','SAFETY_STOP','CUSTOMER_DISPUTE']}});
s.BookingFulfillmentEvent=obj({id:uuid,booking_id:uuid,version:{type:'integer',minimum:1,maximum:2},status,reason_code:s.BookingFulfillmentInput.properties.reason_code,occurred_at:time,simulated:sim});
s.BookingCredentialEnvelope=obj({data:ref('BookingCredential'),meta:ref('Meta')});
s.BookingFulfillmentEventListEnvelope=obj({data:{type:'array',items:ref('BookingFulfillmentEvent')},page:ref('Page'),meta:ref('Meta')});
const ops=[['get','/consumer/service-bookings/{id}/credential','BookingCredentialEnvelope'],['get','/consumer/service-bookings/{id}/fulfillment','BookingFulfillmentEventListEnvelope'],['get','/merchant/stores/{store_id}/service-bookings/{id}/fulfillment','BookingFulfillmentEventListEnvelope'],['post','/merchant/stores/{store_id}/service-bookings/{id}/fulfillment','ServiceBookingEnvelope']];
for(const [method,path,output] of ops){
 const realm=path.split('/')[1],list=output.endsWith('ListEnvelope'),write=method==='post';
 const parameters=[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:uuid}));
 if(list)parameters.push({name:'cursor',in:'query',schema:uuid},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}});
 if(write)parameters.push({name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:16,maxLength:128}},{name:'If-Match',in:'header',required:true,schema:{type:'string',pattern:'^"[0-9]{1,13}"$'}});
 const responses={200:{description:'Simulation only; no fee or actual identity/physical handover assertion',content:{'application/json':{schema:ref(output)}},...path.endsWith('/credential')?{headers:{'Cache-Control':{schema:{type:'string',enum:['no-store']}}}}:{}}};
 for(const code of [400,401,403,404,409,429,503])responses[code]={description:'Validation, scope, version, credential or fulfillment window rejected',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 doc.paths[path]??={};doc.paths[path][method]={operationId:'v312_'+method+'_'+path.replaceAll(/[{}]/g,'').replaceAll(/[-/]/g,'_'),tags:[realm],summary:'Simulated fulfillment '+method+' '+path,description:'Default-off non-production rehearsal. Credential belongs only to booking owner; merchant current store scope and store.nearby.write required for writes. Check-in window starts 30 minutes before slot, ends exclusively at slot end. Completion requires check-in and slot start. No-show only after end; exception fixed reason, terminal without automatic adjudication. History is UUID-paginated; order events by version for display.',security:[{[realm+'Bearer']:[]}],parameters,...write?{requestBody:{required:true,content:{'application/json':{schema:ref('BookingFulfillmentInput')}}}}:{},responses,'x-implemented-in':'V3.1.2'};
}
const output=YAML.stringify(doc,{lineWidth:0}),target=new URL('../openapi/pawday-v3.1.2.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw Error('V3.1.2 contract drift');}else await fs.writeFile(target,output);
