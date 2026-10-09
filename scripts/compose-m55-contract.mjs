import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m5.4.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday M5.5 Nearby Stores and AMap Handoff API';doc.info.version='0.5.5';
doc.info.description='Published existing-store facts, GPS WGS84 nearby queries, scoped merchant editing, reviewed claims and certification, controlled AMap destination handoff. User coordinates are ephemeral; no medical ranking or route engine.';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),id=()=>({type:'string',format:'uuid'}),str=(max=160)=>({type:'string',minLength:1,maxLength:max}),time=()=>({type:'string',format:'date-time'}),array=(items,max)=>({type:'array',items,...(max===undefined?{}:{maxItems:max})}),nullable=x=>({anyOf:[x,{type:'null'}]}),obj=(properties,required=Object.keys(properties))=>({type:'object',additionalProperties:false,properties,required}),bool={type:'boolean'},num={type:'integer',minimum:0,maximum:9007199254741};
function add(path,method,response,{realm='admin',request,list=false,keyed=false,proof=false,versioned=false,paged=false,query=[],binary=false,permission}={}){
 const name=response+(list?'List':'')+'Envelope';if(!binary)s[name]=obj({data:list?array(ref(response)):ref(response),...(list?{page:ref('Page')}:{}),meta:ref('Meta')});
 const parameters=[...[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:id()})),...query,...(paged?[{name:'cursor',in:'query',schema:id()},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}}]:[]),...(keyed?[{name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:16,maxLength:128}}]:[]),...(proof?[{name:'X-Reverify-Token',in:'header',required:true,schema:str(128)}]:[]),...(versioned?[{name:'If-Match',in:'header',required:true,schema:{type:'string',pattern:'^"[0-9]{1,13}"$'}}]:[])];
 const responses={200:{description:binary?'Visible referenced resource; hidden/draft access is denied':'Persisted or currently visible result',content:binary?Object.fromEntries(['image/png','image/jpeg'].map(mime=>[mime,{schema:{type:'string',format:'binary'}}])):{'application/json':{schema:ref(name)}}}};
 for(const status of [400,401,403,404,409,413,422,429,503])responses[status]={description:'Rejected without leaking unpublished or private resource data',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const op={operationId:`${method}_${path.slice(1).replaceAll(/[/{\}-]/g,'_').replace(/_+$/,'')}`,summary:`${method.toUpperCase()} ${path}`,tags:[realm],security:realm==='public'?[]:[{[`${realm}Bearer`]:[]}],parameters,responses,'x-implemented-in':'M5.5',...(permission?{'x-permission':permission}:{})};if(request)op.requestBody={required:true,content:{'application/json':{schema:ref(request)}}};(doc.paths[path]??={})[method]=op;
}



s.Reverify.properties.action.enum.push('ai.manage');
s.AiPreferences=obj({personalization_enabled:bool,version:num,data_usage:str(1000),provider_available:bool});
s.AiPreferenceInput=obj({personalization_enabled:bool});
s.AiQuota=obj({ordinary_remaining:num,membership_remaining:num,remaining:num,policy_id:id(),ordinary_period:{const:'SHANGHAI_DAY',type:'string'},membership_period:{const:'PURCHASED_TERM',type:'string'},enabled:bool});
s.AiConversationInput=obj({current_pet_id:nullable(id())});
s.AiMessageInput=obj({text:str(1000),current_pet_id:nullable(id()),selected_sku_ids:{...array(id(),3),uniqueItems:true}});
s.AiProductCard=obj({sku_id:id(),name:str(240),catalog_standard_version_id:id(),offer_id:id(),offer_version:num,inventory_version:num,price_fen:num,available_qty:num,ingredients:array(str(500)),source_refs:array(str(1000)),fit_result:{type:'string',enum:['SUITABLE','NOT_RECOMMENDED','INSUFFICIENT_DATA']},hard_conflicts:array(ref('FitConflict')),uncertainties:array(str(160))});
s.AiPetContext=obj({pet_id:id(),pet_version:num});
s.AiMessage=obj({message_id:id(),conversation_id:id(),text:str(12000),user_text:str(1000),pet_context:nullable(ref('AiPetContext')),product_cards:array(ref('AiProductCard'),3),prompt_id:id(),policy_id:id(),fit_rule_version:str(100),mode:{type:'string',const:'DEEPSEEK_GROUNDED'},proposal_id:nullable(id()),created_at:time(),quota:ref('AiQuota')});
s.AiConversation=obj({id:id(),pet_id:nullable(id()),status:{type:'string',enum:['ACTIVE']},expires_at:time(),created_at:time()});
s.AiConversationDetail=obj({...s.AiConversation.properties,messages:array(ref('AiMessage'),50)});
s.AiCleared=obj({id:id(),status:{type:'string',const:'DELETED'}});
s.AiProposal=obj({id:id(),request_id:id(),pet_id:nullable(id()),pet_version:num,before_value:nullable({type:'string',enum:['YES','NO','UNKNOWN']}),proposed_value:nullable({type:'string',enum:['YES','NO']}),status:{type:'string',enum:['PENDING','ACCEPTED','REJECTED','EXPIRED']},expires_at:time(),version:num});
s.AiRelease=obj({active_prompt_id:id(),staged_prompt_id:nullable(id()),staged_percent:{type:'integer',minimum:0,maximum:99},policy_id:id(),version:num,provider_available:bool,fit_rule_version:str(100)});
s.AiPromptInput=obj({instruction:str(2000)});
s.AiPrompt=obj({id:id(),instruction:str(2000),created_at:time()});
s.AiPromptView=obj({...s.AiPrompt.properties,status:{type:'string',enum:['ACTIVE','STAGED','VALIDATED','DRAFT']}});
s.AiEvaluationCase=obj({case_code:str(200),passed:bool});
s.AiEvaluation=obj({id:id(),prompt_id:id(),passed:bool,cases:array(ref('AiEvaluationCase')),created_at:time()});
s.AiPolicyInput=obj({ordinary_daily_limit:{type:'integer',minimum:0,maximum:1000},member_daily_ceiling:{type:'integer',minimum:0,maximum:10000},retention_days:{type:'integer',minimum:1,maximum:90},lease_seconds:{type:'integer',minimum:10,maximum:120},enabled:bool});
s.AiPolicy=obj({id:id(),...s.AiPolicyInput.properties,created_at:time()});
s.AiStage=obj({percentage:{type:'integer',minimum:1,maximum:99}});
s.AiEmpty=obj({});
s.AiRules=obj({fit_rule_version:str(100),authority:{type:'string',const:'POSTGRESQL_DETERMINISTIC_RULES'},model_tools:array(str(),0),hard_conflicts_overridable:{type:'boolean',const:false},maximum_comparison_skus:{type:'integer',const:3}});
add('/consumer/ai/preferences','get','AiPreferences',{realm:'consumer'});
add('/consumer/ai/preferences','put','AiPreferences',{realm:'consumer',request:'AiPreferenceInput',keyed:true,versioned:true});
add('/consumer/ai/quota','get','AiQuota',{realm:'consumer'});
add('/consumer/ai/conversations','post','AiConversationDetail',{realm:'consumer',request:'AiConversationInput',keyed:true});
add('/consumer/ai/conversations','get','AiConversation',{realm:'consumer',list:true,paged:true});
add('/consumer/ai/conversations/{conversation_id}','get','AiConversationDetail',{realm:'consumer'});
add('/consumer/ai/conversations/{conversation_id}','delete','AiCleared',{realm:'consumer',keyed:true});
add('/consumer/ai/conversations/{conversation_id}/messages','post','AiMessage',{realm:'consumer',request:'AiMessageInput',keyed:true});
add('/consumer/ai/profile-proposals/{proposal_id}','get','AiProposal',{realm:'consumer'});
for(const action of ['accept','reject'])add(`/consumer/ai/profile-proposals/{proposal_id}/${action}`,'post','AiProposal',{realm:'consumer',request:'AiEmpty',keyed:true,versioned:true});
add('/admin/ai/release','get','AiRelease',{permission:'ai.read'});
add('/admin/ai/rules','get','AiRules',{permission:'ai.read'});
add('/admin/ai/prompts','get','AiPromptView',{list:true,permission:'ai.read'});
add('/admin/ai/policies','get','AiPolicy',{list:true,permission:'ai.read'});
add('/admin/ai/evaluations','get','AiEvaluation',{list:true,permission:'ai.read'});
add('/admin/ai/prompts/versions','post','AiPrompt',{request:'AiPromptInput',keyed:true,proof:true,permission:'ai.manage'});
add('/admin/ai/prompts/{version_id}/validate','post','AiEvaluation',{request:'AiEmpty',keyed:true,proof:true,permission:'ai.manage'});
for(const action of ['stage','activate','rollback'])add(`/admin/ai/prompts/{version_id}/${action}`,'post','AiRelease',{request:action==='stage'?'AiStage':'AiEmpty',keyed:true,proof:true,versioned:true,permission:'ai.manage'});
add('/admin/ai/policies/versions','post','AiPolicy',{request:'AiPolicyInput',keyed:true,proof:true,versioned:true,permission:'ai.manage'});
doc.info.title='Pawday M5.5 Grounded AI Explanations API';
doc.info.description='Verified PostgreSQL facts and deterministic fit remain authoritative. Evidence-only DeepSeek HTTP adapter; reserved quota, immutable purchased-term membership grants, encrypted/erasable conversations, explicit versioned profile proposals, controlled prompt release. No model tools or raw user/pet data sent to the provider.';
// Quote YES/NO enums for validators that also support YAML 1.1 boolean spellings.
const output=YAML.stringify(doc,{lineWidth:120}).replace(/^(\s*-\s*)(YES|NO)(\s*)$/gm,'$1"$2"$3'),target=new URL('../openapi/pawday-m5.5.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('M5.5 composition drift');console.log('M5.5 composition PASS');}else{await fs.writeFile(target,output);console.log('M5.5 composed');}
