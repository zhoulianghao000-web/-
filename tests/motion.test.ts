import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {gsap} from 'gsap';
import {createPageMotion} from '../packages/web-shell/src/motion';

let reduce=false;
let motion:ReturnType<typeof createPageMotion>|undefined;
beforeEach(()=>{
  reduce=false;
  vi.stubGlobal('matchMedia',(query:string)=>({
    matches:query.includes('no-preference')?!reduce:reduce,media:query,
    addListener(){},removeListener(){},addEventListener(){},removeEventListener(){},
  }));
  document.body.innerHTML='<div id="owned"><div class="login-screen"><form class="login-card"><h2>Login</h2><label>Password<input /></label><button>Submit</button></form></div></div><h2 id="other">Untouched</h2>';
});
afterEach(()=>{motion?.destroy();motion=undefined;document.body.innerHTML='';vi.unstubAllGlobals();});
const root=()=>document.querySelector<HTMLElement>('#owned')!;

it('reduced motion keeps controls visible without presentation tweens',()=>{
  reduce=true;motion=createPageMotion(root());motion.refresh();
  const heading=root().querySelector('h2')!;
  expect(heading.getAttribute('style')).toBeNull();expect(gsap.getTweensOf(heading)).toHaveLength(0);
});
it('owns only its subtree and reverts all entrance styles on destroy',()=>{
  motion=createPageMotion(root());motion.refresh();
  const heading=root().querySelector('h2')!;
  expect(gsap.getTweensOf(heading).length).toBeGreaterThan(0);
  expect(document.querySelector('#other')!.getAttribute('style')).toBeNull();
  motion.destroy();
  expect(gsap.getTweensOf(heading)).toHaveLength(0);
  expect((heading as HTMLElement).style.opacity).toBe('');expect((heading as HTMLElement).style.transform).toBe('');
  motion.refresh();expect(gsap.getTweensOf(heading)).toHaveLength(0);
});
it('rapid route refresh releases the outgoing nodes before animating the new page',()=>{
  motion=createPageMotion(root());motion.refresh();
  const oldHeading=root().querySelector('h2')!;
  root().innerHTML='<section class="page"><h1>Next</h1></section>';
  motion.refresh();const next=root().querySelector('.page')!;
  expect(gsap.getTweensOf(oldHeading)).toHaveLength(0);expect(gsap.getTweensOf(next).length).toBeGreaterThan(0);
  motion.refresh();expect(gsap.getTweensOf(next)).toHaveLength(1);
  motion.destroy();expect(gsap.getTweensOf(next)).toHaveLength(0);
});
it('cleans up asynchronous feedback and disconnects observation at unmount',async()=>{
  motion=createPageMotion(root());motion.refresh();
  const alert=document.createElement('p');alert.className='error';alert.setAttribute('role','alert');alert.textContent='Please retry';root().append(alert);
  await Promise.resolve();expect(gsap.getTweensOf(alert)).toHaveLength(1);expect(alert.getAttribute('role')).toBe('alert');
  motion.destroy();expect(gsap.getTweensOf(alert)).toHaveLength(0);expect(alert.style.opacity).toBe('');
  const notice=document.createElement('p');notice.className='notice';root().append(notice);
  await Promise.resolve();expect(gsap.getTweensOf(notice)).toHaveLength(0);
});
