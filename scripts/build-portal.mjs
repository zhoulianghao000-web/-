import {build} from 'vite';
import {readFile,writeFile} from 'node:fs/promises';

// Bundle locally: the simulation portal never fetches scripts from a CDN.
await build({configFile:false,build:{
  outDir:'desktop/dist',emptyOutDir:true,
  lib:{entry:'desktop/motion.ts',name:'PawdayMotion',formats:['iife'],fileName:()=>'motion.js'},
}});
const dependency=JSON.parse(await readFile('node_modules/gsap/package.json','utf8'));
const notice=`GSAP ${dependency.version}\nCopyright 2008-2026, GreenSock. All rights reserved.\n${dependency.license}\n`;
for(const dir of ['desktop/dist','merchant-web/dist','admin-web/dist']){
  await writeFile(`${dir}/GSAP-NOTICE.txt`,notice);
}
