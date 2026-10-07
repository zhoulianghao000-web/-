import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m4.4.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday M4.5 After-Sale and Refund API';doc.info.version='0.4.5';
doc.info.description='Paid cancellation of unshipped quantities, after-sale lifecycle with platform arbitration and frozen-unit original-route refunds. PostgreSQL is authoritative. Channel refund I/O stays outside business transactions and retries idempotently.';
doc.components.schemas.Reverify.properties.action.enum.push('aftersale.arbitrate');
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),id=()=>({type:'string',format:'uuid'}),str=(max=160)=>({type:'string',minLength:1,maxLength:max}),num=()=>({type:'integer',minimum:0,maximum:9007199254740991}),time=()=>({type:'string',format:'date-time'}),array=items=>({type:'array',items}),nullable=x=>({anyOf:[x,{type:'null'}]}),obj=(properties,required=Object.keys(properties))=>({type:'object',additionalProperties:false,properties,required});
const qty=()=>({type:'integer',minimum:1,maximum:100000});
s.Refund=obj({id:id(),refund_no:str(48),payment_id:id(),payment_attempt_id:id(),cancellation_id:nullable(id()),aftersale_id:nullable(id()),amount_fen:{type:'integer',minimum:1,maximum:9007199254740991},channel_refund_no:nullable(str(100)),status:{type:'string',enum:['CREATED','PROCESSING','SUCCEEDED','FAILED_RETRYABLE','FAILED_FINAL','CANCELLED']},attempt_count:num(),next_retry_at:nullable(time()),last_error_code:nullable(str(80)),created_at:time(),decided_at:nullable(time())});
s.CancellationItemInput=obj({order_item_id:id(),quantity:qty()});
s.CancellationInput=obj({reason_code:{type:'string',enum:['CONSUMER_CANCELLED','MERCHANT_OUT_OF_STOCK']},items:{type:'array',minItems:1,maxItems:100,items:ref('CancellationItemInput')}});
s.CancellationItem=obj({id:id(),cancellation_id:id(),order_item_id:id(),quantity:qty(),item_payable_refund_fen:num(),shipping_refund_fen:num(),allocation_snapshot:{type:'object'},refund_id:nullable(id())});
s.CancellationSummary=obj({id:id(),order_id:id(),suborder_id:nullable(id()),actor_type:{type:'string',enum:['CONSUMER','SYSTEM','MERCHANT','ADMIN']},actor_id:nullable(id()),reason_code:{type:'string',enum:['CONSUMER_CANCELLED','PAYMENT_WINDOW_EXPIRED','MERCHANT_OUT_OF_STOCK','PLATFORM_DECISION']},status:{type:'string',enum:['REQUESTED','ACCEPTED','REFUND_PENDING','COMPLETED','REJECTED']},version:num(),created_at:time()});
s.Cancellation=obj({...s.CancellationSummary.properties,items:array(ref('CancellationItem')),refund:nullable(ref('Refund')),refund_amount_fen:num()});
s.AfterSaleItemInput=obj({order_item_id:id(),quantity:qty()});
s.AfterSaleEvidenceInput=obj({content:str(1000)});
s.AfterSaleInput=obj({type:{type:'string',enum:['REFUND_ONLY','RETURN_REFUND']},reason_code:{type:'string',enum:['QUALITY_ISSUE','WRONG_ITEM','DAMAGED','NOT_RECEIVED','CONSUMER_REGRET','OTHER']},reason_text:str(500),items:{type:'array',minItems:1,maxItems:100,items:ref('AfterSaleItemInput')},evidence:{type:'array',maxItems:9,items:ref('AfterSaleEvidenceInput')}});
s.AfterSaleItem=obj({id:id(),aftersale_id:id(),order_item_id:id(),quantity:qty(),item_payable_refund_fen:num(),refund_id:nullable(id())});
s.AfterSaleEvidence=obj({id:id(),actor_type:{type:'string',enum:['CONSUMER','MERCHANT','ADMIN']},kind:{type:'string',enum:['TEXT','ASSET']},content:nullable(str(1000)),asset_id:nullable(id()),created_at:time()});
s.AfterSaleDecision=obj({id:id(),decision:{type:'string',enum:['REFUND_APPROVED','REJECTED']},reason:str(500),amount_fen:num(),created_at:time()});
const aftersaleStatus={type:'string',enum:['PENDING_MERCHANT','WAITING_RETURN','RETURN_IN_TRANSIT','WAITING_INSPECTION','REFUND_PENDING','PLATFORM_ESCALATED','COMPLETED','REJECTED','CANCELLED']};
s.AfterSaleSummary=obj({id:id(),suborder_id:id(),order_id:id(),user_id:id(),merchant_id:id(),type:{type:'string',enum:['REFUND_ONLY','RETURN_REFUND']},reason_code:{type:'string',enum:['QUALITY_ISSUE','WRONG_ITEM','DAMAGED','NOT_RECEIVED','CONSUMER_REGRET','OTHER']},reason_text:str(500),status:aftersaleStatus,return_carrier_code:nullable(str(24)),return_tracking_no:nullable(str(80)),version:num(),created_at:time()});
s.AfterSale=obj({...s.AfterSaleSummary.properties,items:array(ref('AfterSaleItem')),refund:nullable(ref('Refund')),refund_amount_fen:num(),evidence:array(ref('AfterSaleEvidence')),decisions:array(ref('AfterSaleDecision'))});
s.AfterSaleDecisionInput=obj({action:{type:'string',enum:['APPROVE_REFUND','APPROVE_RETURN','REJECT']},reason:str(500)});
s.AfterSaleInspectionInput=obj({action:{type:'string',enum:['ACCEPT','REJECT']},reason:str(500)});
s.AfterSaleReasonInput=obj({reason:str(500)});
s.ReturnShipmentInput=obj({carrier_code:{type:'string',pattern:'^[A-Z0-9_]{2,24}$'},tracking_no:{type:'string',pattern:'^[A-Za-z0-9-]{6,80}$'}});
s.AfterSaleArbitrationInput=obj({decision:{type:'string',enum:['REFUND_APPROVED','REJECTED']},reason:str(500)});
s.EmptyInput=obj({});
s.RefundAdmin=obj({...s.Refund.properties,order_id:id(),currency:str(8)});
function add(path,method,response,{realm='consumer',request,list=false,match=false,proof=false,keyed=false,query=[]}={}){
 const name=response+(list?'List':'')+'Envelope';s[name]=obj({data:list?array(ref(response)):ref(response),...(list?{page:ref('Page')}:{}),meta:ref('Meta')});
 const parameters=[...[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:id()})),...query,...(list?[{name:'cursor',in:'query',schema:id()},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}}]:[]),...(method==='get'||!keyed?[]:[{name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:16,maxLength:128}}]),...(match?[{name:'If-Match',in:'header',required:true,schema:{type:'string',pattern:'^"[0-9]+"$'}}]:[]),...(proof?[{name:'X-Reverify-Token',in:'header',required:true,schema:str(128)}]:[])];
 const responses={200:{description:'Persisted result',content:{'application/json':{schema:ref(name)}}}};for(const status of [400,401,403,404,409,422,428,429,503])responses[status]={description:'Rejected',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const op={operationId:`${method}_${path.slice(1).replaceAll(/[/{\}-]/g,'_').replace(/_+$/,'')}`,summary:`${method.toUpperCase()} ${path}`,tags:[realm],security:[{[`${realm}Bearer`]:[]}],parameters,responses,'x-implemented-in':'M4.5'};
 if(request)op.requestBody={required:true,content:{'application/json':{schema:ref(request)}}};(doc.paths[path]??={})[method]=op;
}
for(const realm of ['consumer','merchant']){
 add(`/${realm}/suborders/{id}/cancellations`,'post','Cancellation',{realm,request:'CancellationInput',keyed:true});
}
for(const realm of ['consumer','merchant','admin']){
 add(`/${realm}/suborders/{id}/cancellations`,'get','Cancellation',{realm,list:true});
 add(`/${realm}/suborders/{id}/aftersales`,'get','AfterSale',{realm,list:true});
}
for(const realm of ['consumer','merchant','admin']){add(`/${realm}/cancellations/{id}`,'get','Cancellation',{realm});add(`/${realm}/aftersales/{id}`,'get','AfterSale',{realm});}
add('/consumer/suborders/{id}/aftersales','post','AfterSale',{request:'AfterSaleInput',keyed:true});
add('/consumer/aftersales/{id}/cancel','post','AfterSale',{request:'EmptyInput',keyed:true,match:true});
add('/consumer/aftersales/{id}/return-shipment','post','AfterSale',{request:'ReturnShipmentInput',keyed:true,match:true});
add('/consumer/aftersales/{id}/escalate','post','AfterSale',{request:'AfterSaleReasonInput',keyed:true,match:true});
add('/merchant/aftersales/{id}/decide','post','AfterSale',{realm:'merchant',request:'AfterSaleDecisionInput',keyed:true,match:true});
add('/merchant/aftersales/{id}/confirm-arrival','post','AfterSale',{realm:'merchant',request:'EmptyInput',keyed:true,match:true});
add('/merchant/aftersales/{id}/inspect','post','AfterSale',{realm:'merchant',request:'AfterSaleInspectionInput',keyed:true,match:true});
add('/admin/cancellations','get','CancellationSummary',{realm:'admin',list:true});
add('/admin/aftersales','get','AfterSaleSummary',{realm:'admin',list:true,query:[{name:'status',in:'query',schema:aftersaleStatus}]});
add('/admin/aftersales/{id}/decide','post','AfterSale',{realm:'admin',request:'AfterSaleArbitrationInput',keyed:true,match:true,proof:true});
add('/admin/refunds','get','RefundAdmin',{realm:'admin',list:true,query:[{name:'status',in:'query',schema:s.Refund.properties.status}]});
for(const name of ['PaymentIntent','PaymentDetail']){if(s[name])s[name].properties.membership_order_id=nullable(id());}
const output=YAML.stringify(doc,{lineWidth:110}),target=new URL('../openapi/pawday-m4.5.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('M4.5 contract drift');console.log('M4.5 contract composition PASS');}else await fs.writeFile(target,output);
