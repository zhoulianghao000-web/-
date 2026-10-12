import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m6.6.3.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday V1 Consumer Care and Favorites API';doc.info.version='0.6.11';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),id=()=>({type:'string',format:'uuid'}),str=max=>({type:'string',minLength:1,maxLength:max}),num=(min,max)=>({type:'integer',minimum:min,maximum:max}),nullable=x=>({anyOf:[x,{type:'null'}]}),obj=properties=>({type:'object',additionalProperties:false,properties,required:Object.keys(properties)}),date={type:'string',format:'date'},time={type:'string',format:'date-time'},bool={type:'boolean'},version=num(0,9007199254741);
s.PetFoodInput=obj({sku_id:nullable(id()),food_name:str(160),package_weight_g:num(1,100000000),daily_amount_g:num(1,1000000),started_on:date,reminder_enabled:bool,remind_before_days:num(0,30)});
s.PetFoodPlan=obj({id:id(),pet_id:id(),...s.PetFoodInput.properties,baseline_on:date,baseline_remaining_g:num(0,100000000),active:bool,version,created_at:time,updated_at:time,estimated_remaining_g:num(0,100000000),estimated_finish_on:date,estimate_as_of:date,estimate_notice:str(160)});
s.PetFoodCalibration=obj({remaining_g:num(0,100000000),recorded_on:date});
s.PetFoodChange=obj({id:id(),plan_id:id(),version,action:{type:'string',enum:['START','CALIBRATE','STOP']},created_at:time});
s.FavoriteInput=obj({kind:{type:'string',enum:['PRODUCT','STORE']},target_id:id()});
s.Favorite=obj({id:id(),...s.FavoriteInput.properties,name:str(160),available:bool,created_at:time});
s.FavoriteRemoved=obj({id:id(),active:bool});
s.NotificationMessage.properties.target_type.enum.push('PET_FOOD');
function add(path,method,response,{request,list=false,keyed=false,versioned=false,optional=false,realm='consumer',proof=false,permission}={}){
 const name=response+(list?'List':optional?'Optional':'')+'Envelope';s[name]=obj({data:list?{type:'array',items:ref(response)}:optional?nullable(ref(response)):ref(response),...(list?{page:ref('Page')}:{}),meta:ref('Meta')});
 const parameters=[...[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:id()})),...(list?[{name:'cursor',in:'query',schema:id()},{name:'limit',in:'query',schema:{...num(1,100),default:50}}]:[]),...(keyed?[{name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:16,maxLength:128}}]:[]),...(proof?[{name:'X-Reverify-Token',in:'header',required:true,schema:str(128)}]:[]),...(versioned?[{name:'If-Match',in:'header',required:true,schema:{type:'string',pattern:'^"[0-9]{1,13}"$'}}]:[])];
 const responses={200:{description:'Owner authorized persisted result',content:{'application/json':{schema:ref(name)}}}};
 for(const status of [400,401,403,404,409,429,503])responses[status]={description:'Rejected without leaking foreign private facts',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const op={operationId:`${method}_${path.slice(1).replaceAll(/[/{\}-]/g,'_').replace(/_+$/,'')}`,summary:`${method.toUpperCase()} ${path}`,tags:[realm],security:[{[`${realm}Bearer`]:[]}],parameters,responses,...(permission?{'x-permission':permission}:{}),'x-implemented-in':'M6.7'};if(request)op.requestBody={required:true,content:{'application/json':{schema:ref(request)}}};(doc.paths[path]??={})[method]=op;
}
add('/consumer/pets/{pet}/food','get','PetFoodPlan',{optional:true});
add('/consumer/pets/{pet}/food','put','PetFoodPlan',{request:'PetFoodInput',keyed:true,versioned:true});
add('/consumer/pets/{pet}/food/history','get','PetFoodChange',{list:true});
add('/consumer/pets/{pet}/food/calibrations','post','PetFoodPlan',{request:'PetFoodCalibration',keyed:true,versioned:true});
add('/consumer/pets/{pet}/food/stop','post','PetFoodPlan',{keyed:true,versioned:true});
add('/consumer/favorites','get','Favorite',{list:true});
add('/consumer/favorites','post','Favorite',{request:'FavoriteInput',keyed:true});
add('/consumer/favorites/{fid}','delete','FavoriteRemoved',{keyed:true});

s.Reverify.properties.action.enum.push('invoice.handle');
const invoiceBase={id:id(),suborder_id:id(),title_type:{type:'string',enum:['PERSONAL','BUSINESS']},status:{type:'string',enum:['REQUESTED','ACCEPTED','REJECTED']},reason:nullable(str(500)),version,created_at:time,updated_at:time,order_id:id(),merchant_id:id(),merchant_name:str(160),suborder_no:str(160),payable_amount_fen:num(0,9007199254741),issuer_notice:str(160)};
s.InvoiceApplication=obj({...invoiceBase,title:str(160),tax_number:nullable(str(20)),email:str(254)});s.InvoiceApplication.required=Object.keys(invoiceBase);
s.InvoiceBatch=obj({applications:{type:'array',items:ref('InvoiceApplication')}});
s.InvoiceInput=obj({order_id:id(),suborder_ids:{type:'array',items:id(),minItems:1,maxItems:20,uniqueItems:true},title_type:invoiceBase.title_type,title:str(160),tax_number:nullable(str(20)),email:str(254)});
s.InvoiceDecision=obj({status:{type:'string',enum:['ACCEPTED','REJECTED']},reason:str(500)});
for(const realm of ['consumer','merchant','admin']){
 add(`/${realm}/invoices`,'get','InvoiceApplication',{realm,list:true,permission:realm==='consumer'?undefined:'invoice.read'});
 add(`/${realm}/invoices/{application}`,'get','InvoiceApplication',{realm,permission:realm==='consumer'?undefined:'invoice.read'});
}
add('/consumer/invoices','post','InvoiceBatch',{request:'InvoiceInput',keyed:true});
add('/merchant/invoices/{application}/decision','post','InvoiceApplication',{realm:'merchant',request:'InvoiceDecision',keyed:true,versioned:true,proof:true,permission:'invoice.handle'});
const output=YAML.stringify(doc,{lineWidth:0}),target=new URL('../openapi/pawday-m6.7.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('V1 closeout contract drift');}else await fs.writeFile(target,output);
