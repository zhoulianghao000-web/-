package cn.pawday.checkout;

import cn.pawday.common.Api.Failure;
import java.math.BigInteger;
import java.util.*;

/** PRICING_V1_1: exact fen arithmetic and immutable stage allocations. */
public final class PricingEngine {
 public static final String RULE="PRICING_V1_1", ALGORITHM="LARGEST_REMAINDER_V1";
 public record Line(String key,String merchant,long amount) {}
 public record Discount(String source,int sequence,String scope,Set<String> keys,long threshold,long amount) {}
 public record Allocation(String source,int sequence,String scope,String key,long eligibleBase,long discount) {}
 public record Result(long goods,long shipping,long discount,long payable,Map<String,Long> goodsPayable,Map<String,Long> shippingPayable,List<Allocation> allocations) {}
 private static long sum(Collection<Long> values){try{long n=0;for(long v:values)n=Math.addExact(n,v);return n;}catch(ArithmeticException e){throw new Failure(422,"AMOUNT_LIMIT_EXCEEDED");}}
 public static Map<String,Long> allocate(Map<String,Long> bases,long discount){
  if(discount<0||bases.values().stream().anyMatch(v->v<0))throw new IllegalArgumentException("negative amount");
  long total=sum(bases.values());if(discount>total)throw new IllegalArgumentException("discount exceeds base");
  var out=new TreeMap<String,Long>();var remainders=new HashMap<String,BigInteger>();long used=0;
  for(var e:bases.entrySet()){
   BigInteger[] qr=total==0?new BigInteger[]{BigInteger.ZERO,BigInteger.ZERO}:BigInteger.valueOf(discount).multiply(BigInteger.valueOf(e.getValue())).divideAndRemainder(BigInteger.valueOf(total));
   long n=qr[0].longValueExact();out.put(e.getKey(),n);used=Math.addExact(used,n);remainders.put(e.getKey(),qr[1]);
  }
  var keys=new ArrayList<>(out.keySet());keys.sort(Comparator.<String,BigInteger>comparing(remainders::get).reversed().thenComparing(Comparator.naturalOrder()));
  for(int i=0;i<discount-used;i++)out.compute(keys.get(i),(k,v)->v+1);
  return Collections.unmodifiableMap(out);
 }
 public Result price(List<Line> lines,Map<String,Long> shipping,List<Discount> discounts){
  var original=new TreeMap<String,Long>();for(Line l:lines){if(l.amount<0||original.put(l.key,l.amount)!=null)throw new IllegalArgumentException("invalid line");}
  if(lines.isEmpty()||shipping.values().stream().anyMatch(v->v<0))throw new IllegalArgumentException("invalid basket");
  if(sum(original.values())>9007199254740991L||sum(shipping.values())>9007199254740991L)throw new Failure(422,"AMOUNT_LIMIT_EXCEEDED");
  var ordered=new ArrayList<>(discounts);ordered.sort(Comparator.comparingInt(Discount::sequence).thenComparing(Discount::source));
  Set<String> sources=new HashSet<>();for(var d:ordered){if(!sources.add(d.source)||d.amount<0||d.threshold<0||!Set.of("GOODS","SHIPPING").contains(d.scope))throw new Failure(422,"COUPON_STACKING_CONFLICT");}
  var totals=new HashMap<String,Long>();Result result=calculate(original,shipping,ordered,totals,false);
  if(result.payable==0){
   Discount last=null;for(var d:ordered)if(totals.getOrDefault(d.source,0L)>0)last=d;
   if(last==null)throw new Failure(422,"ZERO_PAYABLE_ORDER_NOT_SUPPORTED");
   totals.put(last.source,totals.get(last.source)-1);result=calculate(original,shipping,ordered,totals,true);
  }
  return result;
 }
 private Result calculate(Map<String,Long> original,Map<String,Long> originalShipping,List<Discount> discounts,Map<String,Long> frozenTotals,boolean replay){
  var goods=new TreeMap<>(original);var shipping=new TreeMap<>(originalShipping);var allocations=new ArrayList<Allocation>();
  for(var d:discounts){
   var target=d.scope.equals("GOODS")?goods:shipping;var base=new TreeMap<String,Long>();for(String k:d.keys)if(target.containsKey(k))base.put(k,target.get(k));
   long eligible=sum(base.values());if(!replay&&eligible<d.threshold)throw new Failure(422,"COUPON_NOT_ELIGIBLE");
   long total=replay?frozenTotals.get(d.source):Math.min(d.amount,eligible);if(!replay)frozenTotals.put(d.source,total);
   if(total>eligible)throw new IllegalStateException("stage replay changed eligibility");
   for(var e:allocate(base,total).entrySet()){target.put(e.getKey(),target.get(e.getKey())-e.getValue());allocations.add(new Allocation(d.source,d.sequence,d.scope,e.getKey(),base.get(e.getKey()),e.getValue()));}
  }
  long g=sum(original.values()),s=sum(originalShipping.values()),p=Math.addExact(sum(goods.values()),sum(shipping.values()));
  return new Result(g,s,Math.subtractExact(Math.addExact(g,s),p),p,Collections.unmodifiableMap(goods),Collections.unmodifiableMap(shipping),List.copyOf(allocations));
 }
}
