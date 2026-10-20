package cn.pawday.payment;

import cn.pawday.common.Api.Failure;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaymentOwnershipTests {
 @Test void legacyOwnersAreExplicitAndRetainTheirIdentifiers() {
  UUID goods=UUID.randomUUID(),member=UUID.randomUUID();
  assertEquals(new PaymentOwnership(PaymentOwnership.Kind.GOODS_ORDER,goods),PaymentOwnership.from(Map.of("order_id",goods)).supported());
  assertEquals(new PaymentOwnership(PaymentOwnership.Kind.MEMBERSHIP_ORDER,member),PaymentOwnership.from(Map.of("membership_order_id",member)).supported());
 }

 @ParameterizedTest @ValueSource(ints={0,3,5,6,7})
 void absentOrMultipleOwnersFailClosed(int mask) {
  Map<String,Object> row=new HashMap<>();
  if((mask&1)!=0)row.put("order_id",UUID.randomUUID());
  if((mask&2)!=0)row.put("membership_order_id",UUID.randomUUID());
  if((mask&4)!=0)row.put("service_trade_id",UUID.randomUUID());
  Failure failure=assertThrows(Failure.class,()->PaymentOwnership.from(row));
  assertEquals(409,failure.status);assertEquals("PAYMENT_OWNER_INCONSISTENT",failure.code);
 }

 @Test void malformedOwnerIsRejectedEvenAlongsideAValidOwner() {
  assertEquals("PAYMENT_OWNER_INCONSISTENT",assertThrows(Failure.class,()->PaymentOwnership.from(Map.of("order_id",UUID.randomUUID(),"membership_order_id","invalid"))).code);
 }

 @Test void serviceOwnerCannotFallThroughToExistingBusiness() {
  UUID service=UUID.randomUUID();
  var owner=PaymentOwnership.from(Map.of("service_trade_id",service));
  assertEquals(PaymentOwnership.Kind.SERVICE_TRADE,owner.kind());assertEquals(service,owner.id());
  Failure failure=assertThrows(Failure.class,owner::supported);
  assertEquals(503,failure.status);assertEquals("SERVICE_PAYMENT_NOT_IMPLEMENTED",failure.code);
 }

 @ParameterizedTest @ValueSource(booleans={false,true})
 void unsupportedServiceRecoveryAndCloseDoNotCallProviderOrWriteFacts(boolean close) {
  JdbcTemplate db=mock(JdbcTemplate.class);
  @SuppressWarnings("unchecked") ObjectProvider<PaymentGateway> provider=mock(ObjectProvider.class);
  UUID attempt=UUID.randomUUID(),payment=UUID.randomUUID();
  when(db.queryForList("SELECT payment_id FROM payment_attempts WHERE id=?",attempt)).thenReturn(List.of(Map.of("payment_id",payment)));
  when(db.queryForList("SELECT * FROM payments WHERE id=?",payment)).thenReturn(List.of(Map.of("service_trade_id",UUID.randomUUID())));
  var service=new PaymentService(db,null,null,provider,null,null,null,null,null,null,null,null);
  assertEquals("SERVICE_PAYMENT_NOT_IMPLEMENTED",assertThrows(Failure.class,()->service.refresh(attempt,close)).code);
  verifyNoInteractions(provider);
  verify(db).queryForList("SELECT payment_id FROM payment_attempts WHERE id=?",attempt);
  verify(db).queryForList("SELECT * FROM payments WHERE id=?",payment);
  verifyNoMoreInteractions(db);
 }
}
