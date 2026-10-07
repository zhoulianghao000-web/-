import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m4.5.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday M4.6 Settlement Ledger API';doc.info.version='0.4.6';
doc.info.description='Merchant settlement ledger: commission policies frozen at payment success, append-only ledger entries, per-suborder settlement tracks with after-sale buffering, batch settlement with retryable disbursement, and a reconciliation gate. PostgreSQL is authoritative; ledger history is never overwritten.';
doc.components.schemas.Reverify.properties.action.enum.push('settlement.policy.manage','settlement.execute','ledger.adjust');
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),id=()=>({type:'string',format:'uuid'}),str=(max=160)=>({type:'string',minLength:1,maxLength:max}),num=()=>({type:'integer',minimum:0,maximum:9007199254740991}),time=()=>({type:'string',format:'date-time'}),array=items=>({type:'array',items}),nullable=x=>({anyOf:[x,{type:'null'}]}),obj=(properties,required=Object.keys(properties))=>({type:'object',additionalProperties:false,properties,required});
const entryType={type:'string',enum:['SALE_CREDIT','COMMISSION_DEBIT','REFUND_DEBIT','COMMISSION_REVERSAL','SHIPPING_ADJUSTMENT','SETTLEMENT_DEBIT','SETTLEMENT_ADJUSTMENT','MANUAL_ADJUSTMENT']};
const direction={type:'string',enum:['CREDIT','DEBIT']};
const trackStatus={type:'string',enum:['WAITING_RECEIPT','BUFFERING','FROZEN','ELIGIBLE','PROCESSING','SETTLED','ADJUSTED']};
const settlementStatus={type:'string',enum:['PROCESSING','SETTLED','FAILED_RETRYABLE']};
s.CommissionPolicy=obj({id:id(),name:str(160),merchant_id:nullable(id()),category:nullable(str(80)),campaign_code:nullable(str(80)),rate_basis_points:{type:'integer',minimum:0,maximum:10000},priority:{type:'integer'},effective_from:time(),effective_to:nullable(time()),policy_version:{type:'integer',minimum:1},created_by:nullable(id()),created_at:time()});
s.CommissionPolicyInput=obj({name:str(160),merchant_id:nullable(id()),category:nullable(str(80)),campaign_code:nullable(str(80)),rate_basis_points:{type:'integer',minimum:0,maximum:10000},priority:{type:'integer',default:0},effective_from:time(),effective_to:nullable(time())},['name','rate_basis_points','effective_from']);
s.SettlementPolicy=obj({id:id(),buffer_days:{type:'integer',minimum:0,maximum:90},policy_version:{type:'integer',minimum:1},created_by:nullable(id()),created_at:time()});
s.SettlementPolicyInput=obj({buffer_days:{type:'integer',minimum:0,maximum:90}});
s.LedgerEntry=obj({id:id(),merchant_id:id(),entry_type:entryType,direction,amount_fen:{type:'integer',minimum:1,maximum:9007199254740991},affects_balance:{type:'boolean'},order_id:nullable(id()),suborder_id:nullable(id()),order_item_id:nullable(id()),refund_id:nullable(id()),settlement_id:nullable(id()),source_event:str(64),reason:nullable(str(500)),created_by_type:{type:'string',enum:['SYSTEM','PRINCIPAL']},created_by:nullable(id()),created_at:time()});
s.LedgerAdjustmentInput=obj({direction,amount_fen:{type:'integer',minimum:1,maximum:9007199254740991},reason:str(500),suborder_id:nullable(id())},['direction','amount_fen','reason']);
s.SettlementTrack=obj({id:id(),suborder_id:id(),order_id:id(),merchant_id:id(),status:trackStatus,settlement_policy_id:nullable(id()),buffer_days:nullable({type:'integer'}),eligible_at:nullable(time()),settlement_id:nullable(id()),version:num(),created_at:time(),net_fen:{type:'integer'}});
s.SettlementItem=obj({ledger_entry_id:id(),signed_amount_fen:{type:'integer'},entry_type:entryType,suborder_id:nullable(id()),source_event:str(64)});
s.SettlementSummary=obj({id:id(),settlement_no:str(48),merchant_id:id(),status:settlementStatus,amount_fen:{type:'integer',minimum:1,maximum:9007199254740991},entry_count:{type:'integer',minimum:1},attempt_count:num(),last_error_code:nullable(str(80)),channel_reference:nullable(str(100)),initiated_by:nullable(id()),created_at:time(),settled_at:nullable(time()),next_retry_at:nullable(time())});
s.Settlement=obj({...s.SettlementSummary.properties,items:array(ref('SettlementItem'))});
s.FinanceSummary=obj({merchant_id:id(),balance_fen:{type:'integer'},eligible_fen:{type:'integer'},buffering_fen:{type:'integer'},in_flight_fen:{type:'integer'},settled_total_fen:num(),receivable_fen:num()});
s.ReconciliationCheck=obj({name:str(80),mismatches:num()});
s.ReconciliationReport=obj({consistent:{type:'boolean'},checks:array(ref('ReconciliationCheck')),generated_at:time()});
function add(path,method,response,{realm='admin',request,list=false,proof=false,keyed=false,query=[]}={}){
 const name=response+(list?'List':'')+'Envelope';s[name]=obj({data:list?array(ref(response)):ref(response),...(list?{page:ref('Page')}:{}),meta:ref('Meta')});
 const parameters=[...[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:id()})),...query,...(list?[{name:'cursor',in:'query',schema:id()},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}}]:[]),...(method==='get'||!keyed?[]:[{name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:16,maxLength:128}}]),...(proof?[{name:'X-Reverify-Token',in:'header',required:true,schema:str(128)}]:[])];
 const responses={200:{description:'Persisted result',content:{'application/json':{schema:ref(name)}}}};for(const status of [400,401,403,404,409,422,428,429,503])responses[status]={description:'Rejected',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const op={operationId:`${method}_${path.slice(1).replaceAll(/[/{\}-]/g,'_').replace(/_+$/,'')}`,summary:`${method.toUpperCase()} ${path}`,tags:[realm],security:[{[`${realm}Bearer`]:[]}],parameters,responses,'x-implemented-in':'M4.6'};
 if(request)op.requestBody={required:true,content:{'application/json':{schema:ref(request)}}};(doc.paths[path]??={})[method]=op;
}
add('/admin/commission-policies','get','CommissionPolicy',{list:true});
add('/admin/commission-policies','post','CommissionPolicy',{request:'CommissionPolicyInput',proof:true});
add('/admin/settlement-policies','get','SettlementPolicy',{list:true});
add('/admin/settlement-policies','post','SettlementPolicy',{request:'SettlementPolicyInput',proof:true});
for(const realm of ['admin','merchant']){
 add(`/${realm}/settlement-tracks`,'get','SettlementTrack',{realm,list:true,query:[{name:'status',in:'query',schema:trackStatus}]});
 add(`/${realm}/settlements`,'get','SettlementSummary',{realm,list:true,query:[{name:'status',in:'query',schema:settlementStatus}]});
 add(`/${realm}/settlements/{id}`,'get','Settlement',{realm});
}
add('/admin/merchants/{id}/settlements','post','Settlement',{request:'EmptyInput',keyed:true,proof:true});
add('/admin/settlements/{id}/retry','post','Settlement',{request:'EmptyInput',keyed:true,proof:true});
add('/admin/merchants/{id}/ledger','get','LedgerEntry',{list:true,query:[{name:'entry_type',in:'query',schema:entryType}]});
add('/merchant/ledger','get','LedgerEntry',{realm:'merchant',list:true,query:[{name:'entry_type',in:'query',schema:entryType}]});
add('/admin/merchants/{id}/finance-summary','get','FinanceSummary',{});
add('/merchant/finance-summary','get','FinanceSummary',{realm:'merchant'});
add('/admin/merchants/{id}/ledger-adjustments','post','LedgerEntry',{request:'LedgerAdjustmentInput',keyed:true,proof:true});
add('/admin/finance/reconciliation','get','ReconciliationReport',{});
for(const name of ['PaymentIntent','PaymentDetail']){if(s[name])s[name].properties.membership_order_id=nullable(id());}
const output=YAML.stringify(doc,{lineWidth:110}),target=new URL('../openapi/pawday-m4.6.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('M4.6 contract drift');console.log('M4.6 contract composition PASS');}else await fs.writeFile(target,output);
