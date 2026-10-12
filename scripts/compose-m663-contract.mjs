import fs from 'node:fs/promises';
import YAML from 'yaml';
const doc=YAML.parse(await fs.readFile(new URL('../openapi/pawday-m6.6.2.yaml',import.meta.url),'utf8'));
doc.info.title='Pawday Pet Profile and Nearby Experience API';doc.info.version='0.6.10';
for(const name of ['PetRequest','PetPatch','Pet']) {
 const s=doc.components.schemas[name];
 s.properties.custom_breed_name={type:['string','null'],minLength:1,maxLength:80,description:'Owner supplied breed/type label, mutually exclusive with breed_id. Not verified taxonomy or medical evidence.'};
 s.properties.photo_asset_id={type:['string','null'],format:'uuid',description:'Own READY CONSUMER AVATAR image reference; no file bodies in pet records.'};
}
const output=YAML.stringify(doc,{lineWidth:0}),target=new URL('../openapi/pawday-m6.6.3.yaml',import.meta.url);
if(process.argv.includes('--check')) {if(await fs.readFile(target,'utf8')!==output)throw new Error('Pet profile contract drift');}else await fs.writeFile(target,output);
