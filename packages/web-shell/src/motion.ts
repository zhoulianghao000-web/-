import {gsap} from 'gsap';

const feedbackSelector='.error, .notice, .confirm-card';

/** Owns only presentation; never delays navigation, focus or a business command. */
export function createPageMotion(root:HTMLElement,kind:'staff'|'portal'='staff'){
  let media:ReturnType<typeof gsap.matchMedia>|undefined;
  let destroyed=false;
  let workspaceSeen=false;

  function refresh(){
    if(destroyed)return;
    media?.revert();
    media=gsap.matchMedia();
    media.add('(prefers-reduced-motion: no-preference)',()=>{
      const seen=new WeakSet<Element>();
      function enter(elements:Element[],distance=12,stagger=0){
        const fresh=elements.filter(element=>!seen.has(element));
        fresh.forEach(element=>seen.add(element));
        if(!fresh.length)return;
        gsap.from(fresh,{
          autoAlpha:0,y:distance,duration:0.38,ease:'power2.out',
          stagger:{each:stagger,amount:Math.min(0.18,Math.max(0,fresh.length-1)*stagger)},
          clearProps:'opacity,visibility,transform',overwrite:'auto',
        });
      }
      const select=(selector:string)=>Array.from(root.querySelectorAll(selector));
      if(kind==='portal'){
        enter(select('.hero-copy > *, .hero-visual, #health'),12,0.055);
        enter(select('.cards > .card'),18,0.06);
        enter(select('.details, footer'),10,0.04);
      }else if(root.querySelector('.login-screen')){
        enter(select('.login-story > :not(.paw-mark)'),16,0.045);
        enter(select('.login-card > :not(.error)'),12,0.035);
      }else{
        // The sidebar is persistent; only animate its first appearance.
        if(!workspaceSeen){enter(select('aside .brand, aside .realm-label, header'),8,0.035);workspaceSeen=true;}
        enter(select('.page'),12);
        enter(select('.cards > article'),10,0.04);
      }
      enter(select(feedbackSelector),6);

      // Async feedback stays in the DOM immediately, including its ARIA role.
      // Tracking a bounded set avoids retaining a tween for every historic message.
      const pending=new Map<Element,gsap.core.Tween>();
      const feedback=(element:Element)=>{
        if(seen.has(element)||pending.has(element))return;
        const tween=gsap.from(element,{
          autoAlpha:0,y:6,duration:0.24,ease:'power2.out',overwrite:'auto',
          clearProps:'opacity,visibility,transform',onComplete:()=>pending.delete(element),
        });
        pending.set(element,tween);
      };
      const observer=new MutationObserver(records=>{
        for(const [element,tween] of pending){if(!root.contains(element)){tween.revert();pending.delete(element);}}
        for(const record of records)for(const node of record.addedNodes){
          if(!(node instanceof HTMLElement))continue;
          if(node.matches(feedbackSelector))feedback(node);
          else node.querySelectorAll(feedbackSelector).forEach(feedback);
        }
      });
      observer.observe(root,{childList:true,subtree:true});
      // MutationObserver callbacks run later, so their tweens are explicitly owned.
      return ()=>{
        observer.disconnect();
        pending.forEach(tween=>tween.revert());
        pending.clear();
      };
    },root);
  }
  return {refresh,destroy(){destroyed=true;media?.revert();media=undefined;}};
}
