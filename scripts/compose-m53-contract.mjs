import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m5.2.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday M5.3 Human Support and Notifications API';doc.info.version='0.5.3';
doc.info.description='Private human support with current participant/store authorization, immutable ordered/idempotent messages, private controlled images, live-authorized product/order cards, bounded reconnectable polling, notification preferences and transactional Outbox inbox delivery. OS push, arbitrary merchant marketing and autonomous AI are not implemented.';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),id=()=>({type:'string',format:'uuid'}),str=(max=160)=>({type:'string',minLength:1,maxLength:max}),time=()=>({type:'string',format:'date-time'}),array=(items,max)=>({type:'array',items,...(max===undefined?{}:{maxItems:max})}),nullable=x=>({anyOf:[x,{type:'null'}]}),obj=(properties,required=Object.keys(properties))=>({type:'object',additionalProperties:false,properties,required}),bool={type:'boolean'},num={type:'integer',minimum:0,maximum:9007199254741};
s.Reverify.properties.action.enum.push('support.assign');
const category={type:'string',enum:['ORDER','AFTERSALE','PRICE_DROP','RESTOCK','FOOD_REMINDER','ACTIVITY','SUPPORT']};
s.Conversation=obj({id:id(),kind:{type:'string',enum:['PLATFORM','MERCHANT']},store_id:nullable(id()),status:{type:'string',enum:['OPEN','CLOSED']},last_sequence:num,delivered_sequence:num,version:num,created_at:time(),updated_at:time(),assigned_to_me:bool,assigned:bool,read_sequence:num,unread_count:num});
s.ConversationInput=obj({kind:s.Conversation.properties.kind,store_id:nullable(id())});
s.SupportAssignment=obj({principal_id:id(),reason:str(500)});
s.ConversationStatusInput=obj({status:s.Conversation.properties.status});
s.SupportMessageInput=obj({type:{type:'string',enum:['TEXT','IMAGE','PRODUCT','ORDER']},body:nullable(str(2000)),asset_ids:{...array(id(),4),uniqueItems:true},target_id:nullable(id())});
s.SupportMessage=obj({id:id(),conversation_id:id(),sequence:{...num,minimum:1},sender_realm:{type:'string',enum:['CONSUMER','MERCHANT','ADMIN']},type:s.SupportMessageInput.properties.type,body:nullable(str(2000)),target_id:nullable(id()),created_at:time(),outgoing:bool,media:array(ref('PublicationMedia'),4)});
s.ConversationRead=obj({through_sequence:num});
s.SupportCard=obj({type:{type:'string',enum:['PRODUCT','ORDER']},target_id:id(),available:bool,label:nullable(str(240)),destination:nullable(str(400))});
s.NotificationPreference=obj({category,enabled:bool});s.NotificationPreferenceInput=obj({enabled:bool});
s.NotificationMessage=obj({id:id(),category,event_type:str(80),target_type:{type:'string',enum:['ORDER','AFTERSALE','CONVERSATION']},target_id:id(),notify_enabled:bool,read_at:nullable(time()),created_at:time()});
s.NotificationUnread=obj({unread_count:num});s.NotificationDestination=obj({destination:str(400)});
function add(path,method,response,{realm='admin',request,list=false,keyed=false,proof=false,versioned=false,paged=false,query=[],binary=false,permission}={}){
 const name=response+(list?'List':'')+'Envelope';if(!binary)s[name]=obj({data:list?array(ref(response)):ref(response),...(list?{page:ref('Page')}:{}),meta:ref('Meta')});
 const parameters=[...[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:id()})),...query,...(paged?[{name:'cursor',in:'query',schema:id()},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}}]:[]),...(keyed?[{name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:16,maxLength:128}}]:[]),...(proof?[{name:'X-Reverify-Token',in:'header',required:true,schema:str(128)}]:[]),...(versioned?[{name:'If-Match',in:'header',required:true,schema:{type:'string',pattern:'^"[0-9]{1,13}"$'}}]:[])];
 const responses={200:{description:binary?'Visible referenced resource; hidden/draft access is denied':'Persisted or currently visible result',content:binary?Object.fromEntries(['image/png','image/jpeg'].map(mime=>[mime,{schema:{type:'string',format:'binary'}}])):{'application/json':{schema:ref(name)}}}};
 for(const status of [400,401,403,404,409,413,422,429,503])responses[status]={description:'Rejected without leaking unpublished or private resource data',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const op={operationId:`${method}_${path.slice(1).replaceAll(/[/{\}-]/g,'_').replace(/_+$/,'')}`,summary:`${method.toUpperCase()} ${path}`,tags:[realm],security:realm==='public'?[]:[{[`${realm}Bearer`]:[]}],parameters,responses,'x-implemented-in':'M5.3',...(permission?{'x-permission':permission}:{})};if(request)op.requestBody={required:true,content:{'application/json':{schema:ref(request)}}};(doc.paths[path]??={})[method]=op;
}

add('/consumer/conversations','post','Conversation',{realm:'consumer',request:'ConversationInput',keyed:true});
for(const realm of ['consumer','merchant','admin']){
 const prefix=`/${realm}/conversations`,permission=realm==='consumer'?undefined:'support.read';
 add(prefix,'get','Conversation',{realm,list:true,paged:true,permission,query:realm==='merchant'?[{name:'store_id',in:'query',required:true,schema:id()}]:[]});
 add(`${prefix}/{id}`,'get','Conversation',{realm,permission});
 add(`${prefix}/{id}/messages`,'get','SupportMessage',{realm,list:true,permission,query:[{name:'after_sequence',in:'query',schema:{...num,default:0}},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}},{name:'wait_seconds',in:'query',schema:{type:'integer',minimum:0,maximum:20,default:0}}]});
 add(`${prefix}/{id}/messages`,'post','SupportMessage',{realm,request:'SupportMessageInput',keyed:true,permission:realm==='consumer'?undefined:'support.reply'});
 add(`${prefix}/{id}/read`,'post','Conversation',{realm,request:'ConversationRead',keyed:true,permission});
 add(`${prefix}/{id}/status`,'post','Conversation',{realm,request:'ConversationStatusInput',keyed:true,versioned:true,permission:realm==='consumer'?undefined:'support.reply'});
 add(`${prefix}/{id}/messages/{mid}/media/{asset}`,'get','PublicationMedia',{realm,binary:true,permission});
 add(`${prefix}/{id}/messages/{mid}/card`,'get','SupportCard',{realm,permission});
 if(realm!=='consumer')add(`${prefix}/{id}/assignment`,'post','Conversation',{realm,request:'SupportAssignment',keyed:true,proof:true,versioned:true,permission:'support.assign'});
}
add('/consumer/messages','get','NotificationMessage',{realm:'consumer',list:true,paged:true,query:[{name:'category',in:'query',schema:category}]});
add('/consumer/messages/{id}/target','get','NotificationDestination',{realm:'consumer'});
add('/consumer/messages/unread','get','NotificationUnread',{realm:'consumer'});
add('/consumer/messages/{id}/read','post','NotificationMessage',{realm:'consumer',keyed:true});
add('/consumer/notification-preferences','get','NotificationPreference',{realm:'consumer',list:true});
add('/consumer/notification-preferences/{category}','put','NotificationPreference',{realm:'consumer',request:'NotificationPreferenceInput',keyed:true});
// The category parameter is a frozen taxonomy, not a UUID.
doc.paths['/consumer/notification-preferences/{category}'].put.parameters.find(p=>p.name==='category').schema=category;
const output=YAML.stringify(doc,{lineWidth:120}),target=new URL('../openapi/pawday-m5.3.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('M5.3 composition drift');console.log('M5.3 composition PASS');}else{await fs.writeFile(target,output);console.log('M5.3 composed');}
