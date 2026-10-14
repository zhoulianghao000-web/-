import {describe,it,expect} from 'vitest';
import {quotationPlot,type PricePoint} from '../packages/web-shell/src/price-history';
const point=(sale:number|null,member:number|null=null):PricePoint=>({date:'2026-10-14',sale_price_fen:sale,member_price_fen:member,sale_status:sale===null?null:'ACTIVE',publicly_recorded:sale===null?null:true,recorded_at:sale===null?null:'2026-10-14T01:00:00Z'});
describe('observed quotation chart',()=>{
 it('never joins across missing or nonpublic quotations',()=>{
  const result=quotationPlot([point(1000),point(1200),point(null),point(900)]);
  expect(result.paths).toHaveLength(2);expect(result.dots).toHaveLength(3);
  expect(result.paths[1]).not.toContain('L');
 });
 it('does not invent a trend for unknown history and displays an isolated known point',()=>{
  expect(quotationPlot([point(null),point(null)]).paths).toEqual([]);
  const result=quotationPlot([point(null),point(1000)]);
  expect(result.paths).toHaveLength(1);expect(result.paths[0]).not.toContain('L');expect(result.dots.every(x=>Number.isFinite(x.x)&&Number.isFinite(x.y))).toBe(true);
 });
 it('member quotation gaps are independent of ordinary quotation changes',()=>{
  const values=[point(1000,900),point(1200),point(1300,950)];
  expect(quotationPlot(values).paths).toHaveLength(1);expect(quotationPlot(values,true).paths).toHaveLength(2);
 });
});
