package cn.pawday.integration;
import cn.pawday.common.Api.Failure;
import java.util.*;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;
@Component public class IntegrationPolicy {
 private final boolean enabled;private final String scenario;
 public IntegrationPolicy(Environment env){
  boolean requested=env.getProperty("pawday.erp-wms.simulation-enabled",Boolean.class,false);
  enabled=requested&&Set.of("development","test","pilot").contains(env.getProperty("pawday.deployment-mode","development"))&&Arrays.stream(env.getActiveProfiles()).noneMatch(Set.of("production","prod")::contains);
  scenario=env.getProperty("pawday.erp-wms.fixture-scenario","EMPTY");
  if(!Set.of("EMPTY","TEST_REPLENISH_10").contains(scenario)||!scenario.equals("EMPTY")&&!enabled)throw new IllegalArgumentException("ERP fixture requires explicit non-production simulation");
  if(requested&&!"SIMULATED_TEST".equals(env.getProperty("pawday.erp-wms.provider","SIMULATED_TEST")))throw new IllegalArgumentException("Only the synthetic ERP provider is permitted");
 }
 public void requireEnabled(){if(!enabled)throw new Failure(404,"ERP_WMS_SIMULATION_DISABLED");}
 public boolean automaticFixture(){return enabled&&scenario.equals("TEST_REPLENISH_10");}
}
