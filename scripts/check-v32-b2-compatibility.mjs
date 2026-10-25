import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const read=async n=>JSON.parse(await fs.readFile(new URL(`../openapi/${n}.json`,import.meta.url),'utf8'));
const before=await read('pawday-v3.2-b1'),after=await read('pawday-v3.2-b2');
for(const [path,value] of Object.entries(before.paths))assert.deepEqual(after.paths[path],value,path);
for(const [name,value] of Object.entries(before.components.schemas)){
 const current=structuredClone(after.components.schemas[name]);
 if(['Proof','Reverify'].includes(name)){assert.equal(current.properties.action.enum.pop(),'integration.delivery.retry');}
 assert.deepEqual(current,value,name);
}
assert.equal(Object.values(after.paths).flatMap(v=>Object.values(v)).filter(v=>v['x-implemented-in']==='V3.2-B2').length,3);
console.log('V3.2-B2 preserves all prior operations and schemas');
