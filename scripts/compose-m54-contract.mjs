import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m5.3.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday M5.4 Nearby Stores and AMap Handoff API';doc.info.version='0.5.4';
doc.info.description='Published existing-store facts, GPS WGS84 nearby queries, scoped merchant editing, reviewed claims and certification, controlled AMap destination handoff. User coordinates are ephemeral; no medical ranking or route engine.';
const s=doc.components.schemas,ref=n=>({$ref:`#/components/schemas/${n}`}),id=()=>({type:'string',format:'uuid'}),str=(max=160)=>({type:'string',minLength:1,maxLength:max}),time=()=>({type:'string',format:'date-time'}),array=(items,max)=>({type:'array',items,...(max===undefined?{}:{maxItems:max})}),nullable=x=>({anyOf:[x,{type:'null'}]}),obj=(properties,required=Object.keys(properties))=>({type:'object',additionalProperties:false,properties,required}),bool={type:'boolean'},num={type:'integer',minimum:0,maximum:9007199254741};
function add(path,method,response,{realm='admin',request,list=false,keyed=false,proof=false,versioned=false,paged=false,query=[],binary=false,permission}={}){
 const name=response+(list?'List':'')+'Envelope';if(!binary)s[name]=obj({data:list?array(ref(response)):ref(response),...(list?{page:ref('Page')}:{}),meta:ref('Meta')});
 const parameters=[...[...path.matchAll(/\{([^}]+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:id()})),...query,...(paged?[{name:'cursor',in:'query',schema:id()},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}}]:[]),...(keyed?[{name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:16,maxLength:128}}]:[]),...(proof?[{name:'X-Reverify-Token',in:'header',required:true,schema:str(128)}]:[]),...(versioned?[{name:'If-Match',in:'header',required:true,schema:{type:'string',pattern:'^"[0-9]{1,13}"$'}}]:[])];
 const responses={200:{description:binary?'Visible referenced resource; hidden/draft access is denied':'Persisted or currently visible result',content:binary?Object.fromEntries(['image/png','image/jpeg'].map(mime=>[mime,{schema:{type:'string',format:'binary'}}])):{'application/json':{schema:ref(name)}}}};
 for(const status of [400,401,403,404,409,413,422,429,503])responses[status]={description:'Rejected without leaking unpublished or private resource data',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const op={operationId:`${method}_${path.slice(1).replaceAll(/[/{\}-]/g,'_').replace(/_+$/,'')}`,summary:`${method.toUpperCase()} ${path}`,tags:[realm],security:realm==='public'?[]:[{[`${realm}Bearer`]:[]}],parameters,responses,'x-implemented-in':'M5.4',...(permission?{'x-permission':permission}:{})};if(request)op.requestBody={required:true,content:{'application/json':{schema:ref(request)}}};(doc.paths[path]??={})[method]=op;
}


s.Reverify.properties.action.enum.push('nearby.moderate');
const category={type:'string',enum:['PET_STORE','VET','GROOMING','BOARDING']},services={type:'array',items:{type:'string',enum:['SUPPLIES','GROOMING','BOARDING','CONSULTATION','EMERGENCY','PET_FRIENDLY']},maxItems:6,uniqueItems:true};
const lon={type:'number',minimum:-180,maximum:180},lat={type:'number',minimum:-90,maximum:90},coord={type:'string',enum:['WGS84']};
s.NearbyProfileInput=obj({city:str(80),category,address:str(500),phone:str(32),business_hours:str(240),longitude:lon,latitude:lat,coordinate_system:coord,services});
s.NearbyProfile=obj({id:id(),name:str(160),merchant_id:id(),...s.NearbyProfileInput.properties,source:{type:'string',enum:['MERCHANT_SUBMITTED']},publication_status:{type:'string',enum:['DRAFT','PUBLISHED','HIDDEN']},claim_status:{type:'string',enum:['UNREVIEWED','VERIFIED','REJECTED']},pawday_certified:bool,version:num,updated_at:time()});
s.NearbyPlace=obj({...s.NearbyProfile.properties});delete s.NearbyPlace.properties.merchant_id;s.NearbyPlace.required=Object.keys(s.NearbyPlace.properties);
s.NearbyResult=obj({...s.NearbyPlace.properties,distance_m:nullable(num)});
s.NearbyModeration=obj({publication_status:{type:'string',enum:['PUBLISHED','HIDDEN']},claim_status:{type:'string',enum:['VERIFIED','REJECTED']},pawday_certified:bool,reason:str(500)});
s.NavigationInput=obj({place_id:id(),mode:{type:'string',enum:['DESTINATION']}});
s.NavigationIntent=obj({provider:{type:'string',enum:['AMAP_URI']},place_id:id(),destination_name:str(160),longitude:lon,latitude:lat,coordinate_system:coord,mode:s.NavigationInput.properties.mode,launch_url:{type:'string',format:'uri'},fallback_url:{type:'string',format:'uri'}});
add('/merchant/stores/{store_id}/nearby-profile','get','NearbyProfile',{realm:'merchant',permission:'store.read'});
add('/merchant/stores/{store_id}/nearby-profile','put','NearbyProfile',{realm:'merchant',request:'NearbyProfileInput',permission:'store.nearby.write',keyed:true,versioned:true});
add('/admin/nearby/stores','get','NearbyProfile',{realm:'admin',permission:'nearby.read',list:true,paged:true});
add('/admin/nearby/stores/{id}','get','NearbyProfile',{realm:'admin',permission:'nearby.read'});
add('/admin/nearby/stores/{id}/moderation','post','NearbyProfile',{realm:'admin',permission:'nearby.moderate',request:'NearbyModeration',keyed:true,versioned:true,proof:true});
const query=[{name:'city',in:'query',schema:str(80)},{name:'category',in:'query',schema:category},{name:'longitude',in:'query',schema:lon},{name:'latitude',in:'query',schema:lat},{name:'coordinate_system',in:'query',schema:coord},{name:'radius_m',in:'query',schema:{type:'integer',minimum:100,maximum:100000,default:10000}},{name:'offset',in:'query',schema:{type:'integer',minimum:0,maximum:10000,default:0}},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}}];
add('/public/nearby/places','get','NearbyResult',{realm:'public',list:true,query});
add('/public/nearby/places/{id}','get','NearbyPlace',{realm:'public'});
for(const realm of ['public','consumer'])add(`/${realm}/nearby/navigation-intents`,'post','NavigationIntent',{realm,request:'NavigationInput'});
const output=YAML.stringify(doc,{lineWidth:120}),target=new URL('../openapi/pawday-m5.4.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('M5.4 composition drift');console.log('M5.4 composition PASS');}else{await fs.writeFile(target,output);console.log('M5.4 composed');}
