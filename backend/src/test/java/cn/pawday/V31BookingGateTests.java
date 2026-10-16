package cn.pawday;
import cn.pawday.booking.ServiceBookingService;
import cn.pawday.common.Api.Failure;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import static org.junit.jupiter.api.Assertions.*;
class V31BookingGateTests {
 @Test void disabledByDefaultAndCannotBeEnabledInProduction(){
  var productionProfile=new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true");productionProfile.setActiveProfiles("production");
  for(var env:new MockEnvironment[]{new MockEnvironment(),new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true").withProperty("pawday.deployment-mode","production"),new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true").withProperty("pawday.deployment-mode","unknown"),productionProfile}){
   var service=new ServiceBookingService(null,null,null,null,null,null,env,null);
   var error=assertThrows(Failure.class,()->service.services(null,null,false,null,10));assertEquals("BOOKING_SIMULATION_DISABLED",error.code);
  }
 }
}
