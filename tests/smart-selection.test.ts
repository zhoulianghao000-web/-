import {expect,it} from 'vitest';
import {mount} from '@vue/test-utils';
import SmartSelectionEntry from '../packages/web-shell/src/SmartSelectionEntry.vue';
it('staff smart selection opens the consumer AI route without sharing staff identity',()=>{
 const w=mount(SmartSelectionEntry,{props:{pilot:true}});
 const a=w.get('a');expect(a.text()).toContain('智能选品');expect(a.attributes('href')).toBe('http://127.0.0.1:4175/#/ai');
 expect(a.attributes('target')).toBe('_blank');expect(a.attributes('rel')).toContain('noopener');expect(a.attributes('href')).not.toMatch(/token|session|merchant|admin/);w.unmount();
});
it('ordinary deployments use the consumer preview entry on their own origin',()=>{
 const w=mount(SmartSelectionEntry,{props:{pilot:false}});expect(w.get('a').attributes('href')).toBe('/consumer-preview/#/ai');w.unmount();
});
