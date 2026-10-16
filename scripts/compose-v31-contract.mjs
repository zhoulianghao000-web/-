import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-v2.3.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday V3.1.1 Simulated Service Booking';doc.info.version='3.0.1';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),obj=p=>({type:'object',additionalProperties:false,properties:p,required:Object.keys(p)});
const uuid={type:'string',format:'uuid'},time={type:'string',format:'date-time'},integer={type:'integer',minimum:0,maximum:9007199254740991},str={type:'string'},sim={type:'boolean',enum:[true]};
s.BookingServiceInput=obj({title:{type:'string',minLength:1,maxLength:120},kind:{type:'string',enum:['GROOMING','BOARDING']}});
s.BookingService=obj({id:uuid,store_id:uuid,...s.BookingServiceInput.properties,status:{type:'string',enum:['ACTIVE','PAUSED']},version:integer,created_at:time,simulated:sim});
s.BookingServiceState=obj({status:{type:'string',enum:['ACTIVE','PAUSED']}});
s.BookingSlotInput=obj({starts_at:time,ends_at:time,capacity:{type:'integer',minimum:1,maximum:100}});
s.BookingSlot=obj({id:uuid,service_id:uuid,...s.BookingSlotInput.properties,created_at:time,remaining:{type:'integer',minimum:0,maximum:100},simulated:sim});
s.ServiceBookingInput=obj({slot_id:uuid});
s.ServiceBooking=obj({id:uuid,slot_id:uuid,service_id:uuid,store_id:uuid,service_title:{type:'string',minLength:1,maxLength:120},policy:{...str,enum:['SIMULATION_NO_CHARGE_V1']},amount_fen:{type:'integer',enum:[0]},status:{type:'string',enum:['BOOKED','CANCELLED']},version:integer,created_at:time,cancelled_at:{anyOf:[time,{type:'null'}]},starts_at:time,ends_at:time,simulated:sim});
s.BookingEmpty=obj({});
for(const name of ['BookingService','BookingSlot','ServiceBooking']){
 s[name+'Envelope']=obj({data:ref(name),meta:ref('Meta')});
 s[name+'ListEnvelope']=obj({data:{type:'array',items:ref(name)},page:ref('Page'),meta:ref('Meta')});
}
const ops=[
 ['get','/merchant/stores/{store_id}/booking-services','BookingService',null,true],
 ['get','/consumer/stores/{store_id}/booking-services','BookingService',null,true],
 ['post','/merchant/stores/{store_id}/booking-services','BookingService','BookingServiceInput'],
 ['put','/merchant/booking-services/{id}/state','BookingService','BookingServiceState',false,true],
 ['post','/merchant/booking-services/{id}/slots','BookingSlot','BookingSlotInput'],
 ['get','/merchant/booking-services/{id}/slots','BookingSlot',null,true],
 ['get','/consumer/booking-services/{id}/slots','BookingSlot',null,true],
 ['post','/consumer/service-bookings','ServiceBooking','ServiceBookingInput'],
 ['get','/consumer/service-bookings','ServiceBooking',null,true],
 ['get','/merchant/stores/{store_id}/service-bookings','ServiceBooking',null,true],
 ['post','/consumer/service-bookings/{id}/cancel','ServiceBooking','BookingEmpty',false,true],
 ['post','/merchant/stores/{store_id}/service-bookings/{id}/cancel','ServiceBooking','BookingEmpty',false,true],
];
for(const [method,path,output,input,list,version] of ops){
 const realm=path.split('/')[1],parameters=[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:uuid}));
 if(list)parameters.push({name:'cursor',in:'query',schema:uuid},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}});
 if(input)parameters.push({name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:16,maxLength:128}});
 if(version)parameters.push({name:'If-Match',in:'header',required:true,schema:{type:'string',pattern:'^"[0-9]{1,13}"$'}});
 const responses={200:{description:'Synthetic rehearsal only; zero charge; no payment or fulfillment promise',content:{'application/json':{schema:ref(output+(list?'ListEnvelope':'Envelope'))}}}};
 for(const code of [400,401,403,404,409,429,503])responses[code]={description:'Invalid input, denied scope, disabled simulation, capacity or version conflict',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 doc.paths[path]??={};doc.paths[path][method]={operationId:'v31_'+method+'_'+path.replaceAll(/[{}]/g,'').replaceAll(/[-/]/g,'_'),tags:[realm],summary:'Simulated booking: '+method+' '+path,description:'Disabled by default. Requires explicit simulation flag and a non-production deployment. Merchant access reuses store.read / store.nearby.write and current store scope. One booking reserves one place in a service-specific slot. No actual partner or charge is implied.',security:[{[realm+'Bearer']:[]}],parameters,...input?{requestBody:{required:true,content:{'application/json':{schema:ref(input)}}}}:{},responses,'x-implemented-in':'V3.1.1'};
}
const output=YAML.stringify(doc,{lineWidth:0}),target=new URL('../openapi/pawday-v3.1.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw Error('V3.1 contract drift');}else await fs.writeFile(target,output);
