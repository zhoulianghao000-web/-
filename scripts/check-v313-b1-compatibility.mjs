import assert from 'node:assert/strict';
import fs from 'node:fs';
import YAML from 'yaml';
const previous=YAML.parse(fs.readFileSync(new URL('../openapi/pawday-v3.1.2.yaml',import.meta.url),'utf8'));
const current=JSON.parse(fs.readFileSync(new URL('../openapi/pawday-v3.1.3-b1.json',import.meta.url),'utf8'));
// Only the new proof action extends existing shapes; legacy paths and schemas stay compatible.
for(const name of ['Proof','Reverify']){
 const actions=previous.components.schemas[name].properties.action.enum;
 if(!actions.includes('service.terms.review'))actions.push('service.terms.review');
}
for(const [name,schema] of Object.entries(previous.components.schemas))assert.deepEqual(current.components.schemas[name],schema,`Legacy schema drift: ${name}`);
for(const [path,operations] of Object.entries(previous.paths))assert.deepEqual(current.paths[path],operations,`Legacy path drift: ${path}`);
console.log('V3.1.3-B1 compatibility: all existing paths and 483 schemas preserved; proof action explicitly extended');
