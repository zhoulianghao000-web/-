package cn.pawday;
import cn.pawday.checkout.PricingEngine;
import cn.pawday.common.Api.Failure;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class PricingEngineTests {
 @Test void stableLargestRemainderExamples(){assertEquals(Map.of("1",1L,"2",1L,"3",0L),PricingEngine.allocate(Map.of("3",1L,"1",1L,"2",1L),2));assertEquals(Map.of("1",1200L,"2",800L),PricingEngine.allocate(Map.of("1",6000L,"2",4000L),2000));}
 @Test void multiplicationDoesNotOverflow(){var bases=Map.of("a",3000000000000000000L,"b",3000000000000000000L);assertEquals(Map.of("a",1500000000000000000L,"b",1500000000000000000L),PricingEngine.allocate(bases,3000000000000000000L));}
 @Test void zeroBaseAndInvalidAmounts(){assertEquals(Map.of("a",0L),PricingEngine.allocate(Map.of("a",0L),0));assertThrows(IllegalArgumentException.class,()->PricingEngine.allocate(Map.of("a",0L),1));assertThrows(Failure.class,()->new PricingEngine().price(List.of(new PricingEngine.Line("1","m",0)),Map.of("m",0L),List.of()));}
 @Test void deterministicRandomizedConservation(){var random=new Random(41);for(int round=0;round<2000;round++){var base=new TreeMap<String,Long>();for(int i=0;i<1+random.nextInt(12);i++)base.put(String.format("%06d",i),(long)random.nextInt(1000000));long total=base.values().stream().mapToLong(x->x).sum(),discount=total==0?0:random.nextLong(total+1);var a=PricingEngine.allocate(base,discount);assertEquals(discount,a.values().stream().mapToLong(x->x).sum());for(String k:base.keySet())assertTrue(a.get(k)>=0&&a.get(k)<=base.get(k));var reverse=new LinkedHashMap<String,Long>();base.descendingMap().forEach(reverse::put);assertEquals(a,PricingEngine.allocate(reverse,discount));}}
 @Test void orderedStagesAndInverseMinimumRollback(){var e=new PricingEngine();var lines=List.of(new PricingEngine.Line("1","m",1),new PricingEngine.Line("2","m",1),new PricingEngine.Line("3","m",1));var result=e.price(lines,Map.of("m",0L),List.of(new PricingEngine.Discount("platform",5,"GOODS",Set.of("1","2","3"),0,999),new PricingEngine.Discount("merchant",3,"GOODS",Set.of("1","2","3"),0,2)));assertEquals(1,result.payable());assertEquals(2,result.discount());assertEquals(Map.of("1",0L,"2",0L,"3",1L),result.goodsPayable());assertEquals(0,result.allocations().stream().filter(x->x.source().equals("platform")).mapToLong(PricingEngine.Allocation::discount).sum());}
 @Test void laterCouponThresholdUsesRemainingBalance(){assertThrows(Failure.class,()->new PricingEngine().price(List.of(new PricingEngine.Line("1","m",1000)),Map.of("m",0L),List.of(new PricingEngine.Discount("merchant",3,"GOODS",Set.of("1"),1000,300),new PricingEngine.Discount("platform",5,"GOODS",Set.of("1"),1000,100))));}
}
