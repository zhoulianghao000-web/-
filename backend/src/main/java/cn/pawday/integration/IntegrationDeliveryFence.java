package cn.pawday.integration;

import cn.pawday.common.Api.Failure;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** Independent of feature switches: old external responsibilities survive pause and restart. */
@Component public class IntegrationDeliveryFence {
 private final JdbcTemplate db;
 public IntegrationDeliveryFence(JdbcTemplate db){this.db=db;}
 /** Caller already holds original order/suborder locks; call before item or stock locks. */
 public void requireNative(UUID suborder){
  db.queryForList("SELECT c.id FROM integration_connections c WHERE c.id IN (SELECT connection_id FROM integration_order_deliveries WHERE suborder_id=?) ORDER BY c.id FOR UPDATE",suborder);
  if(Boolean.TRUE.equals(db.queryForObject("SELECT integration_delivery_open(?)",Boolean.class,suborder)))
   throw new Failure(409,"INTEGRATION_EXTERNAL_FULFILLMENT_REVIEW_REQUIRED");
 }
}
