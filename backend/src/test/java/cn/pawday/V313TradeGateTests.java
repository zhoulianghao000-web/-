package cn.pawday;
import cn.pawday.booking.ServiceTradeService;
import cn.pawday.common.Api.Failure;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import static org.junit.jupiter.api.Assertions.*;
class V313TradeGateTests {
 @Test void serviceTradeNeedsBothFlagsAndCannotRunInProduction(){
  var prod=new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true").withProperty("pawday.service-trade.simulation-enabled","true");prod.setActiveProfiles("production");
  for(var env:new MockEnvironment[]{new MockEnvironment(),new MockEnvironment().withProperty("pawday.service-trade.simulation-enabled","true"),new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true"),new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true").withProperty("pawday.service-trade.simulation-enabled","true").withProperty("pawday.deployment-mode","production"),prod}){
   var service=new ServiceTradeService(null,null,null,null,null,null,null,null,null,env);assertEquals("SERVICE_TRADE_SIMULATION_DISABLED",assertThrows(Failure.class,()->service.trades(null,null,null,10)).code);
  }
 }
}
