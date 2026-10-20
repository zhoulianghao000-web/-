package cn.pawday.payment;

import cn.pawday.common.Api.Failure;
import java.util.Map;
import java.util.UUID;

/** Explicit business ownership; an absent goods order must never select a fallback business. */
record PaymentOwnership(Kind kind, UUID id) {
 enum Kind { GOODS_ORDER, MEMBERSHIP_ORDER, SERVICE_TRADE }

 static PaymentOwnership from(Map<String,Object> payment) {
  UUID goods=reference(payment.get("order_id"));
  UUID membership=reference(payment.get("membership_order_id"));
  UUID service=reference(payment.get("service_trade_id"));
  int owners=(goods==null?0:1)+(membership==null?0:1)+(service==null?0:1);
  if(owners!=1)throw new Failure(409,"PAYMENT_OWNER_INCONSISTENT");
  if(goods!=null)return new PaymentOwnership(Kind.GOODS_ORDER,goods);
  if(membership!=null)return new PaymentOwnership(Kind.MEMBERSHIP_ORDER,membership);
  return new PaymentOwnership(Kind.SERVICE_TRADE,service);
 }

 /** B2 preparation only. A service owner requires the later migration and atomic confirmation branch. */
 PaymentOwnership supported() {
  if(kind==Kind.SERVICE_TRADE)throw new Failure(503,"SERVICE_PAYMENT_NOT_IMPLEMENTED");
  return this;
 }

 private static UUID reference(Object value) {
  if(value==null)return null;
  if(value instanceof UUID id)return id;
  throw new Failure(409,"PAYMENT_OWNER_INCONSISTENT");
 }
}
