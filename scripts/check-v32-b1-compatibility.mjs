import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const read=async n=>JSON.parse(await fs.readFile(new URL(`../openapi/${n}.json`,import.meta.url),'utf8'));
const before=await read('pawday-v3.1.3-b3'),after=await read('pawday-v3.2-b1');
for(const [path,value] of Object.entries(before.paths))assert.deepEqual(after.paths[path],value,path);
for(const [name,value] of Object.entries(before.components.schemas)){
 const current=structuredClone(after.components.schemas[name]);
 if(['Proof','Reverify'].includes(name)){assert.deepEqual(current.properties.action.enum.slice(-3),['integration.manage','integration.mapping.write','integration.stock.apply']);current.properties.action.enum=current.properties.action.enum.slice(0,-3);}
 assert.deepEqual(current,value,name);
}
assert.equal(Object.values(after.paths).flatMap(v=>Object.values(v)).filter(v=>v['x-implemented-in']==='V3.2-B1').length,10);
console.log('V3.2-B1 preserves all prior operations and schemas');
