package cn.pawday;
import cn.pawday.payment.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.core.env.MapPropertySource;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;
class PaymentProductionBoundaryTests {
 @ParameterizedTest @ValueSource(booleans={false,true}) void productionExcludesSimulatorEvenWithLocalProfileAndFlag(boolean local){
  try(var context=new AnnotationConfigApplicationContext()){
   context.getEnvironment().setActiveProfiles(local?new String[]{"production","local"}:new String[]{"production"});
   context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("test",Map.of("pawday.payment.simulation-enabled",true)));
   context.register(SimulatedPaymentGateway.class,SimulationController.class);context.refresh();
   assertTrue(context.getBeansOfType(PaymentGateway.class).isEmpty());assertTrue(context.getBeansOfType(SimulationController.class).isEmpty());
  }
 }
}
