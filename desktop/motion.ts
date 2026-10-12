import {createPageMotion} from '../packages/web-shell/src/motion';

const root=document.querySelector('main');
if(root){
  let motion=createPageMotion(root,'portal');
  motion.refresh();
  window.addEventListener('pagehide',()=>motion.destroy());
  window.addEventListener('pageshow',event=>{
    if(event.persisted){motion=createPageMotion(root,'portal');motion.refresh();}
  });
}
