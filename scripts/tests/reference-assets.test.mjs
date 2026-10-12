import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const root=new URL('../../consumer-app/flutter/assets/reference/',import.meta.url);
test('all eleven original reference images remain local and byte-verifiable',async()=>{
 const manifest=JSON.parse(await readFile(new URL('manifest.json',root),'utf8'));
 assert.equal(manifest.assets.length,11);
 assert.equal(new Set(manifest.assets.map(item=>item.file)).size,11);
 for(const item of manifest.assets){
  assert.match(item.file,/^[a-z-]+\.jpg$/);
  const bytes=await readFile(new URL(item.file,root));
  assert.equal(bytes.length,item.size);assert.equal(bytes.readUInt16BE(0),0xffd8);
  assert.equal(createHash('sha256').update(bytes).digest('hex'),item.sha256);
 }
});
