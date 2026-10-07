import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m4.3.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday M4.4 Shipment and Receipt API';doc.info.version='0.4.4';
doc.info.description='Scoped partial shipments, explicit parcel receipts and derived fulfillment. PostgreSQL is authoritative. Unconfigured tracking is UNKNOWN and stale.';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),id=()=>({type:'string',format:'uuid'}),str=(max=160)=>({type:'string',minLength:1,maxLength:max}),num=()=>({type:'integer',minimum:0,maximum:9007199254740991}),time=()=>({type:'string',format:'date-time'}),array=items=>({type:'array',items}),nullable=x=>({anyOf:[x,{type:'null'}]}),obj=(properties,required=Object.keys(properties))=>({type:'object',additionalProperties:false,properties,required});
s.OrderSummary.properties.status.enum.push('PARTIALLY_SHIPPED','AWAITING_RECEIPT','PARTIALLY_COMPLETED','COMPLETED');s.Order.properties.status.enum=s.OrderSummary.properties.status.enum;
s.Suborder.properties.fulfillment_status.enum.push('PARTIALLY_SHIPPED','SHIPPED_WAITING_RECEIPT','PARTIALLY_COMPLETED','COMPLETED');
s.ShipmentItem=obj({order_item_id:id(),quantity:{type:'integer',minimum:1,maximum:100000}});
s.ShipmentInput=obj({carrier_code:{type:'string',pattern:'^[A-Z0-9_]{2,24}$'},tracking_no:{type:'string',pattern:'^[A-Za-z0-9-]{6,80}$'},items:{type:'array',minItems:1,maxItems:100,items:ref('ShipmentItem')}});
s.ReceiptInput=obj({shipment_ids:{type:'array',minItems:1,maxItems:100,uniqueItems:true,items:id()}});
s.Shipment=obj({id:id(),suborder_id:id(),carrier_code:str(24),tracking_no:str(80),created_at:time(),confirmed_at:nullable(time()),items:array(ref('ShipmentItem'))});
s.FulfillmentItem=obj({order_item_id:id(),quantity:num(),cancelled_qty:num(),shipped_qty:num(),received_qty:num()});
s.Fulfillment=obj({suborder_id:id(),version:num(),fulfillment_status:s.Suborder.properties.fulfillment_status,items:array(ref('FulfillmentItem')),shipments:array(ref('Shipment')),delivery_address:nullable(ref('CheckoutAddress'))});
s.TrackingEvent=obj({event_id:str(),occurred_at:time(),description:str(500),location:nullable(str())});
s.Tracking=obj({carrier_code:str(24),tracking_no:str(80),status:{type:'string',enum:['UNKNOWN','SHIPPED','IN_TRANSIT','DELIVERED','EXCEPTION']},events:array(ref('TrackingEvent')),last_synced_at:nullable(time()),stale:{type:'boolean'},provider_reference:str()});
function add(path,method,response,{realm='consumer',request,list=false,match=false,proof=false,keyed=false}={}){
 const name=response+(list?'List':'')+'Envelope';s[name]=obj({data:list?array(ref(response)):ref(response),...(list?{page:ref('Page')}:{}),meta:ref('Meta')});
 const parameters=[...[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:id()})),...(list?[{name:'cursor',in:'query',schema:id()},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}}]:[]),...(method==='get'||!keyed?[]:[{name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:16,maxLength:128}}]),...(match?[{name:'If-Match',in:'header',required:true,schema:{type:'string',pattern:'^"[0-9]+"$'}}]:[]),...(proof?[{name:'X-Reverify-Token',in:'header',required:true,schema:str(128)}]:[])];
 const responses={200:{description:'Persisted result',content:{'application/json':{schema:ref(name)}}}};for(const status of [400,401,403,404,409,422,428,429,503])responses[status]={description:'Rejected',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const op={operationId:`${method}_${path.slice(1).replaceAll(/[/{\}-]/g,'_').replace(/_+$/,'')}`,summary:`${method.toUpperCase()} ${path}`,tags:[realm],security:[{[`${realm}Bearer`]:[]}],parameters,responses,'x-implemented-in':'M4.4'};
 if(request)op.requestBody={required:true,content:{'application/json':{schema:ref(request)}}};(doc.paths[path]??={})[method]=op;
}


for(const realm of ['consumer','merchant','admin']){add(`/${realm}/suborders/{id}/fulfillment`,'get','Fulfillment',{realm});add(`/${realm}/shipments/{id}/tracking`,'get','Tracking',{realm});}
add('/merchant/suborders/{id}/shipments','post','Fulfillment',{realm:'merchant',request:'ShipmentInput',keyed:true,match:true});
add('/consumer/suborders/{id}/confirm-receipt','post','Fulfillment',{request:'ReceiptInput',keyed:true,match:true});
for(const name of ['PaymentIntent','PaymentDetail']){if(s[name])s[name].properties.membership_order_id=nullable(id());}
const output=YAML.stringify(doc,{lineWidth:110}),target=new URL('../openapi/pawday-m4.4.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('M4.4 contract drift');console.log('M4.4 contract composition PASS');}else await fs.writeFile(target,output);

