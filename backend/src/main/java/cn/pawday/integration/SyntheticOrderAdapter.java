package cn.pawday.integration;

import java.nio.charset.StandardCharsets;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** Explicit non-production fixed fixture. Durable channel idempotency is separate from local receipts. */
@Component class SyntheticOrderAdapter implements IntegrationOrderAdapter {
 private final IntegrationPolicy policy;private final JdbcTemplate db;
 SyntheticOrderAdapter(IntegrationPolicy policy,JdbcTemplate db){this.policy=policy;this.db=db;}
 private void gate(){policy.requireEnabled();if(TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("External I/O inside business transaction");}
 private Observation result(Instruction i){var rows=db.queryForList("SELECT * FROM integration_delivery_fixture_orders WHERE business_key=?",i.businessKey());
  if(rows.isEmpty())return new Observation("NOT_CREATED",i.connection(),i.merchant(),i.businessKey(),i.payloadSha256(),null,true);
  var r=rows.getFirst();return new Observation(r.get("result").toString(),(UUID)r.get("connection_id"),(UUID)r.get("merchant_id"),r.get("business_key").toString(),r.get("payload_sha256").toString(),r.get("provider_reference").toString(),Boolean.TRUE.equals(r.get("no_external_order")));
 }
 public Observation query(Instruction i){gate();if(policy.deliveryScenario().equals("TEST_UNKNOWN"))return unknown(i);return result(i);}
 public Observation submit(Instruction i){gate();String scenario=policy.deliveryScenario();
  if(scenario.equals("EMPTY")||scenario.equals("TEST_UNKNOWN"))return unknown(i);
  String status=scenario.equals("TEST_REJECTED")?"REJECTED":"ACCEPTED";
  String reference="TEST_ONLY_ERP_"+UUID.nameUUIDFromBytes(i.businessKey().getBytes(StandardCharsets.UTF_8));
  db.update("INSERT INTO integration_delivery_fixture_orders(business_key,connection_id,merchant_id,payload_sha256,result,provider_reference,no_external_order) VALUES (?,?,?,?,?,?,?) ON CONFLICT(business_key) DO NOTHING",i.businessKey(),i.connection(),i.merchant(),i.payloadSha256(),status,reference,status.equals("REJECTED"));
  return scenario.equals("TEST_RESPONSE_LOST")?unknown(i):result(i);
 }
 private Observation unknown(Instruction i){return new Observation("UNKNOWN",i.connection(),i.merchant(),i.businessKey(),i.payloadSha256(),null,false);}
}
