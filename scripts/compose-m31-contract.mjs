// Compose the implemented contract from the preserved M2 API and formal M1 pet schemas.
import fs from 'node:fs/promises';
import YAML from 'yaml';
const read=async name=>YAML.parse(await fs.readFile(new URL(`../openapi/${name}`,import.meta.url),'utf8'));
const doc=await read('pawday-m2.3.yaml'), core=await read('pawday-v1.yaml');
doc.info.title='Pawday M3.1 Pet Taxonomy and Profiles API';doc.info.version='0.3.1';
doc.info.description='Implemented M2 infrastructure plus M3.1 pet taxonomy, sourced lifecycle rules and consumer-owned profiles. No catalog or transaction APIs implied.';
const schemas=doc.components.schemas;
schemas.Reverify.properties.action.enum.push('pet.taxonomy.write');
const ref=name=>({$ref:`#/components/schemas/${name}`});
const string=(max=160)=>({type:'string',minLength:1,maxLength:max});
const object=(properties,required=Object.keys(properties))=>({type:'object',additionalProperties:false,properties,required});
const integer=(min=0,max=9007199254740991)=>({type:'integer',minimum:min,maximum:max});
for(const name of ['LifeStage','Species','AllergenEntry','PetRequest','PetPatch','Pet'])schemas[name]=structuredClone(core.components.schemas[name]);
for(const name of ['PetRequest','PetPatch','Pet'])schemas[name].properties.name.maxLength=160;
for(const name of ['PetRequest','PetPatch']){schemas[name].properties.allergens.maxItems=100;schemas[name].properties.avoidance_notes.maxItems=50;schemas[name].properties.age_estimate_months.anyOf[0].maximum=2400;}
schemas.Breed=object({id:string(128),species_id:string(128),name:string()});
schemas.Allergen=object({id:string(128),name:string()});
schemas.Weight=object({id:string(128),weight_g:integer(1,100000000),recorded_on:{type:'string',format:'date'},source:{type:'string',enum:['OWNER_OBSERVATION','VET_DIAGNOSIS']}});
schemas.WeightRequest=object({...schemas.Weight.properties});delete schemas.WeightRequest.properties.id;schemas.WeightRequest.required=schemas.WeightRequest.required.filter(x=>x!=='id');
schemas.WeightCreated=object({...schemas.Weight.properties,pet_version:integer()});
schemas.PetDeleted=object({id:string(128),version:integer(),status:{type:'string',const:'DELETED'}});
schemas.TaxonomyCreated=object({id:string(128),name:string()});
schemas.TaxonomyRetired=object({id:string(128),status:{type:'string',const:'RETIRED'}});
schemas.RulePublished=object({id:string(128),species_id:string(128),version_no:integer(1),status:{type:'string',const:'PUBLISHED'}});
schemas.SpeciesCreate=object({name:string(),parent_id:string(128)});
schemas.BreedCreate=object({name:string(),species_id:string(128)});
schemas.AllergenCreate=object({name:string()});
schemas.StageDefinition=object({stage_code:string(80),display_name:string(),min_age_value:{type:['integer','null'],minimum:0,maximum:2147483647},max_age_value:{type:['integer','null'],minimum:1,maximum:2147483647},age_unit:{type:'string',enum:['DAY','MONTH','YEAR']},is_unknown:{type:'boolean'}});
schemas.RulePublish=object({species_id:string(128),source_refs:{type:'array',items:string(2000),maxItems:20},stages:{type:'array',items:ref('StageDefinition'),minItems:1,maxItems:30}});
function envelope(name,list=false){const n=name+(list?'List':'')+'Envelope';schemas[n]=object({data:list?{type:'array',items:ref(name)}:ref(name),...(list?{page:ref('Page')}:{}),meta:ref('Meta')});return n;}
function add(path,method,name,{request,list=false,realm,version=false,reverify=false,status='200'}={}){
 const parameters=[];for(const id of path.matchAll(/\{([^}]+)\}/g))parameters.push({name:id[1],in:'path',required:true,schema:string(128)});
 if(method!=='get')parameters.push({name:'Idempotency-Key',in:'header',required:true,schema:{...string(128),minLength:16}});
 if(version)parameters.push({name:'If-Match',in:'header',required:true,schema:{type:'string',pattern:'^"[0-9]+"$'}});
 if(reverify)parameters.push({name:'X-Reverify-Token',in:'header',required:true,schema:string(128)});
 if(list&&realm==='consumer'){parameters.push({name:'cursor',in:'query',schema:string(128)},{name:'limit',in:'query',schema:{type:'integer',minimum:1,maximum:100,default:50}});}
 const responses={[status]:{description:'Success',content:{'application/json':{schema:ref(envelope(name,list))}}}};
 for(const code of ['400','401','403','404','409','422','429','503'])responses[code]={description:'Request rejected',content:{'application/json':{schema:ref('ErrorEnvelope')}}};
 const op={operationId:`${method}_${path.replace(/^\//,'').replaceAll(/[/{\}-]/g,'_').replace(/_+$/,'')}`,summary:`${method.toUpperCase()} ${path}`,tags:[realm??'public'],security:realm?[{[`${realm}Bearer`]:[]}]:[],parameters,responses,'x-implemented-in':'M3.1'};
 if(request)op.requestBody={required:true,content:{'application/json':{schema:ref(request)}}};
 (doc.paths[path]??={})[method]=op;
}
add('/public/pet-taxonomy','get','Species',{list:true});
add('/public/pet-species/{species_id}/breeds','get','Breed',{list:true});
add('/public/allergens','get','Allergen',{list:true});
add('/consumer/pets','get','Pet',{list:true,realm:'consumer'});
add('/consumer/pets','post','Pet',{request:'PetRequest',realm:'consumer',status:'201'});
add('/consumer/pets/{pet_id}','get','Pet',{realm:'consumer'});
add('/consumer/pets/{pet_id}','patch','Pet',{request:'PetPatch',realm:'consumer',version:true});
add('/consumer/pets/{pet_id}','delete','PetDeleted',{realm:'consumer',version:true});
add('/consumer/pets/{pet_id}/weight-records','get','Weight',{realm:'consumer',list:true});
add('/consumer/pets/{pet_id}/weight-records','post','WeightCreated',{request:'WeightRequest',realm:'consumer',version:true,status:'201'});
add('/admin/pet-taxonomy','get','Species',{list:true,realm:'admin'});
for(const [type,request] of [['species','SpeciesCreate'],['breeds','BreedCreate'],['allergens','AllergenCreate'],['life-stage-rules','RulePublish']])add(`/admin/pet-taxonomy/${type}`,'post',type==='life-stage-rules'?'RulePublished':'TaxonomyCreated',{request,realm:'admin',reverify:true,status:'201'});
for(const type of ['species','breeds','allergens'])add(`/admin/pet-taxonomy/${type}/{id}/retire`,'post','TaxonomyRetired',{realm:'admin',reverify:true});
doc.tags.push({name:'public',description:'Anonymous taxonomy reads'});
const output=YAML.stringify(doc,{lineWidth:110});const target=new URL('../openapi/pawday-m3.1.yaml',import.meta.url);
if(process.argv.includes('--check')){if(await fs.readFile(target,'utf8')!==output)throw new Error('M3.1 composed contract drift');console.log('M3.1 contract composition PASS');}else await fs.writeFile(target,output);
