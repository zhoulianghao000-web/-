package cn.pawday.integration;
import cn.pawday.publishing.PublishingSupport;
import java.util.UUID;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
/** No customer-controlled input or real supplier. One explicit fixed scenario per mapping. */
@Component public class IntegrationFixtureWorker {
 private final IntegrationPolicy policy;private final IntegrationInventoryService service;private final PublishingSupport p;
 public IntegrationFixtureWorker(IntegrationPolicy policy,IntegrationInventoryService service,PublishingSupport p){this.policy=policy;this.service=service;this.p=p;}
 @Scheduled(fixedDelayString="${pawday.erp-wms.fixture-delay-ms:1000}") public void receive(){if(!policy.automaticFixture())return;
  for(var row:p.db.queryForList("SELECT m.id,m.connection_id,c.store_id FROM integration_mappings m JOIN integration_connections c ON c.id=m.connection_id WHERE c.state='ACTIVE' AND m.state='ACTIVE' AND NOT EXISTS(SELECT 1 FROM integration_inventory_events e WHERE e.mapping_id=m.id) ORDER BY c.id,m.id LIMIT 100")){
   try{service.acceptFixtureEvent((UUID)row.get("store_id"),(UUID)row.get("connection_id"),(UUID)row.get("id"),"TEST_ONLY_REPLENISH_10",1,10,0,null);}
   catch(cn.pawday.common.Api.Failure e){if(!java.util.Set.of(404,409,503).contains(e.status))throw e;}
  }
 }
}
