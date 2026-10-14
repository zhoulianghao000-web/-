import type {components} from '../../api-client/src';
export type PricePoint=components['schemas']['PriceHistoryPoint'];
export function quotationPlot(points:PricePoint[],member=false){
 const values=points.flatMap(p=>[p.sale_price_fen,p.member_price_fen]).filter((x):x is number=>x!==null);
 if(!values.length)return {paths:[] as string[],dots:[] as {x:number;y:number}[]};
 const min=Math.min(...values),max=Math.max(...values),padding=Math.max(max-min,100)*.1,low=min-padding,high=max+padding;
 const paths:string[]=[],dots:{x:number;y:number}[]=[];let segment='';
 for(const [i,p] of points.entries()){
  const value=member?p.member_price_fen:p.sale_price_fen;
  if(value===null){if(segment)paths.push(segment);segment='';continue;}
  const x=10+580*i/Math.max(points.length-1,1),y=170-160*(value-low)/(high-low);
  dots.push({x,y});segment+=`${segment?'L':'M'}${x.toFixed(2)},${y.toFixed(2)} `;
 }
 if(segment)paths.push(segment);
 return {paths,dots};
}
