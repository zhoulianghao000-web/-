-- M4.5 paid cancellation, after-sale and frozen-unit refunds.
-- Refund quota per logical unit is frozen at order creation; claims occupy units once.
CREATE TABLE order_item_refund_units (
 order_item_id uuid NOT NULL REFERENCES order_items(id),unit_index integer NOT NULL CHECK(unit_index>=1),
 paid_amount_fen bigint NOT NULL CHECK(paid_amount_fen>=0),PRIMARY KEY(order_item_id,unit_index)
);
INSERT INTO order_item_refund_units(order_item_id,unit_index,paid_amount_fen)
SELECT i.id,s.idx,i.payable_amount_fen/i.quantity+CASE WHEN s.idx<=i.payable_amount_fen%i.quantity THEN 1 ELSE 0 END
FROM order_items i CROSS JOIN LATERAL generate_series(1,i.quantity) s(idx);
CREATE TRIGGER immutable_refund_units BEFORE UPDATE OR DELETE ON order_item_refund_units FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

CREATE TABLE refunds (
 id uuid PRIMARY KEY,refund_no varchar(48) NOT NULL UNIQUE,
 payment_id uuid NOT NULL REFERENCES payments(id),payment_attempt_id uuid NOT NULL REFERENCES payment_attempts(id),
 cancellation_id uuid REFERENCES order_cancellations(id),aftersale_id uuid,
 amount_fen bigint NOT NULL CHECK(amount_fen>0),channel_refund_no varchar(100),
 status varchar(20) NOT NULL DEFAULT 'CREATED' CHECK(status IN ('CREATED','PROCESSING','SUCCEEDED','FAILED_RETRYABLE','FAILED_FINAL','CANCELLED')),
 attempt_count integer NOT NULL DEFAULT 0,next_retry_at timestamptz,last_error_code varchar(80),
 created_at timestamptz NOT NULL DEFAULT now(),decided_at timestamptz,
 CHECK((cancellation_id IS NULL)<>(aftersale_id IS NULL))
);
CREATE INDEX ix_refunds_due ON refunds(next_retry_at) WHERE status IN ('CREATED','PROCESSING','FAILED_RETRYABLE');
CREATE FUNCTION protect_refund() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','attempt_count','next_retry_at','last_error_code','channel_refund_no','decided_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','attempt_count','next_retry_at','last_error_code','channel_refund_no','decided_at'])
 OR OLD.status IN ('SUCCEEDED','FAILED_FINAL','CANCELLED')
 OR NOT ((OLD.status='CREATED' AND NEW.status='PROCESSING') OR (OLD.status='PROCESSING' AND NEW.status IN ('PROCESSING','SUCCEEDED','FAILED_RETRYABLE','FAILED_FINAL')) OR (OLD.status='FAILED_RETRYABLE' AND NEW.status IN ('PROCESSING','FAILED_RETRYABLE','FAILED_FINAL'))) THEN RAISE EXCEPTION 'invalid refund mutation'; END IF; RETURN NEW; END $$;
CREATE TRIGGER refund_guard BEFORE UPDATE ON refunds FOR EACH ROW EXECUTE FUNCTION protect_refund();
CREATE TRIGGER refund_no_delete BEFORE DELETE ON refunds FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE FUNCTION verify_refund_consistency() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE total bigint; cap bigint; BEGIN
 SELECT coalesce(sum(amount_fen),0) INTO total FROM refunds WHERE payment_id=NEW.payment_id AND status<>'CANCELLED';
 SELECT amount_fen INTO cap FROM payments WHERE id=NEW.payment_id;
 IF total>cap THEN RAISE EXCEPTION 'refund exceeds collected amount'; END IF; RETURN NULL; END $$;
CREATE CONSTRAINT TRIGGER refund_consistency AFTER INSERT ON refunds DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_refund_consistency();

CREATE TABLE order_refund_unit_claims (
 id uuid PRIMARY KEY,order_item_id uuid NOT NULL,unit_index integer NOT NULL,
 source_type varchar(16) NOT NULL CHECK(source_type IN ('CANCELLATION','AFTERSALE')),
 source_item_id uuid NOT NULL,refund_id uuid REFERENCES refunds(id),
 status varchar(16) NOT NULL DEFAULT 'RESERVED' CHECK(status IN ('RESERVED','REFUNDED','RELEASED')),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(order_item_id,unit_index) REFERENCES order_item_refund_units(order_item_id,unit_index)
);
CREATE UNIQUE INDEX uq_claim_active_unit ON order_refund_unit_claims(order_item_id,unit_index) WHERE status IN ('RESERVED','REFUNDED');
CREATE UNIQUE INDEX uq_claim_source_item ON order_refund_unit_claims(source_type,source_item_id,unit_index);
CREATE FUNCTION protect_claim() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','refund_id']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','refund_id'])
 OR OLD.status<>'RESERVED'
 OR (OLD.refund_id IS NOT NULL AND NEW.refund_id IS DISTINCT FROM OLD.refund_id) THEN RAISE EXCEPTION 'invalid claim mutation'; END IF; RETURN NEW; END $$;
CREATE TRIGGER claim_guard BEFORE UPDATE ON order_refund_unit_claims FOR EACH ROW EXECUTE FUNCTION protect_claim();
CREATE TRIGGER claim_no_delete BEFORE DELETE ON order_refund_unit_claims FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

-- Cancellation orders become per-suborder, multi-status authoritative records.
DROP TRIGGER immutable_record ON order_cancellations;
ALTER TABLE order_cancellations DROP CONSTRAINT order_cancellations_order_id_key;
ALTER TABLE order_cancellations DROP CONSTRAINT order_cancellations_actor_type_check;
ALTER TABLE order_cancellations DROP CONSTRAINT order_cancellations_reason_code_check;
ALTER TABLE order_cancellations DROP CONSTRAINT order_cancellations_status_check;
ALTER TABLE order_cancellations ADD COLUMN suborder_id uuid REFERENCES suborders(id);
ALTER TABLE order_cancellations ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE order_cancellations ADD CHECK(actor_type IN ('CONSUMER','SYSTEM','MERCHANT','ADMIN'));
ALTER TABLE order_cancellations ADD CHECK(reason_code IN ('CONSUMER_CANCELLED','PAYMENT_WINDOW_EXPIRED','MERCHANT_OUT_OF_STOCK','PLATFORM_DECISION'));
ALTER TABLE order_cancellations ADD CHECK(status IN ('REQUESTED','ACCEPTED','REFUND_PENDING','COMPLETED','REJECTED'));
CREATE INDEX ix_cancellations_suborder ON order_cancellations(suborder_id,created_at,id);
CREATE TRIGGER cancellation_no_delete BEFORE DELETE ON order_cancellations FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE FUNCTION protect_cancellation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version']) OR NEW.version<>OLD.version+1
 OR OLD.status IN ('COMPLETED','REJECTED')
 OR NOT ((OLD.status='REQUESTED' AND NEW.status IN ('ACCEPTED','REFUND_PENDING','COMPLETED','REJECTED')) OR (OLD.status='ACCEPTED' AND NEW.status IN ('REFUND_PENDING','COMPLETED')) OR (OLD.status='REFUND_PENDING' AND NEW.status='COMPLETED')) THEN RAISE EXCEPTION 'invalid cancellation mutation'; END IF; RETURN NEW; END $$;
CREATE TRIGGER cancellation_guard BEFORE UPDATE ON order_cancellations FOR EACH ROW EXECUTE FUNCTION protect_cancellation();
ALTER TABLE order_cancellation_items DROP CONSTRAINT order_cancellation_items_item_payable_refund_fen_check;
ALTER TABLE order_cancellation_items DROP CONSTRAINT order_cancellation_items_shipping_refund_fen_check;
ALTER TABLE order_cancellation_items ADD COLUMN refund_id uuid REFERENCES refunds(id);
ALTER TABLE order_cancellation_items ADD CHECK(item_payable_refund_fen>=0);
ALTER TABLE order_cancellation_items ADD CHECK(shipping_refund_fen>=0);
ALTER TABLE order_cancellation_events DROP CONSTRAINT order_cancellation_events_cancellation_id_key;
ALTER TABLE order_cancellation_events DROP CONSTRAINT order_cancellation_events_to_status_check;
ALTER TABLE order_cancellation_events ADD CHECK(to_status IN ('ACCEPTED','REFUND_PENDING','COMPLETED','REJECTED'));

-- Cancelled quantity cache follows accepted-or-later cancellation items, not only completed ones.
CREATE OR REPLACE FUNCTION verify_cancelled_quantity() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE accepted bigint; BEGIN
 SELECT coalesce(sum(i.quantity),0) INTO accepted FROM order_cancellation_items i JOIN order_cancellations c ON c.id=i.cancellation_id WHERE i.order_item_id=NEW.id AND c.status IN ('ACCEPTED','REFUND_PENDING','COMPLETED');
 IF accepted<>NEW.cancelled_qty THEN RAISE EXCEPTION 'cancelled quantity cache has no cancellation evidence'; END IF;
 RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION protect_order_item() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-'cancelled_qty') IS DISTINCT FROM (to_jsonb(OLD)-'cancelled_qty') OR NEW.cancelled_qty<OLD.cancelled_qty OR NEW.cancelled_qty>NEW.quantity THEN RAISE EXCEPTION 'invalid item mutation'; END IF;
 RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION protect_order_state() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version']) OR NEW.version<>OLD.version+1
 OR NOT ((OLD.status='PENDING_PAYMENT' AND NEW.status IN ('CANCELLED','FULFILLING')) OR (OLD.status='FULFILLING' AND NEW.status IN ('FULFILLING','CANCELLED'))) THEN RAISE EXCEPTION 'invalid order mutation'; END IF; RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION protect_suborder_state() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE total bigint; shipped bigint; received bigint; expected text; BEGIN
 IF (to_jsonb(NEW)-ARRAY['fulfillment_status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['fulfillment_status','version']) OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid suborder mutation'; END IF;
 IF OLD.fulfillment_status='PENDING_PAYMENT' AND NEW.fulfillment_status IN ('CANCELLED','PAID_WAITING_FULFILLMENT') THEN RETURN NEW; END IF;
 IF OLD.fulfillment_status IN ('PENDING_PAYMENT','CANCELLED','COMPLETED') THEN RAISE EXCEPTION 'terminal suborder'; END IF;
 SELECT coalesce(sum(quantity-cancelled_qty),0) INTO total FROM order_items WHERE suborder_id=NEW.id;
 SELECT coalesce(sum(i.quantity),0),coalesce(sum(i.quantity) FILTER(WHERE r.shipment_id IS NOT NULL),0) INTO shipped,received FROM shipment_items i LEFT JOIN shipment_receipts r ON r.shipment_id=i.shipment_id WHERE i.suborder_id=NEW.id;
 expected:=CASE WHEN total=0 THEN 'CANCELLED' WHEN received=total THEN 'COMPLETED' WHEN received>0 THEN 'PARTIALLY_COMPLETED' WHEN shipped=total THEN 'SHIPPED_WAITING_RECEIPT' WHEN shipped>0 THEN 'PARTIALLY_SHIPPED' ELSE 'PAID_WAITING_FULFILLMENT' END;
 IF NEW.fulfillment_status<>expected THEN RAISE EXCEPTION 'fulfillment state lacks quantity evidence'; END IF; RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION verify_fulfillment_commit() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE sub uuid; total bigint; shipped bigint; received bigint; expected text; actual text; BEGIN
 IF TG_TABLE_NAME='shipment_receipts' THEN SELECT suborder_id INTO sub FROM shipments WHERE id=NEW.shipment_id; ELSE sub:=NEW.suborder_id; END IF;
 SELECT coalesce(sum(quantity-cancelled_qty),0) INTO total FROM order_items WHERE suborder_id=sub;
 SELECT coalesce(sum(i.quantity),0),coalesce(sum(i.quantity) FILTER(WHERE r.shipment_id IS NOT NULL),0) INTO shipped,received FROM shipment_items i LEFT JOIN shipment_receipts r ON r.shipment_id=i.shipment_id WHERE i.suborder_id=sub;
 expected:=CASE WHEN total=0 THEN 'CANCELLED' WHEN received=total THEN 'COMPLETED' WHEN received>0 THEN 'PARTIALLY_COMPLETED' WHEN shipped=total THEN 'SHIPPED_WAITING_RECEIPT' WHEN shipped>0 THEN 'PARTIALLY_SHIPPED' ELSE 'PAID_WAITING_FULFILLMENT' END;
 SELECT fulfillment_status INTO actual FROM suborders WHERE id=sub;
 IF actual<>expected OR EXISTS(SELECT 1 FROM shipments h WHERE h.suborder_id=sub AND NOT EXISTS(SELECT 1 FROM shipment_items i WHERE i.shipment_id=h.id)) THEN RAISE EXCEPTION 'fulfillment commit consistency'; END IF;RETURN NULL;END $$;

-- Accepted cancellation and accepted after-sale returns restock exactly once per source line.
CREATE TABLE inventory_restock_events (
 id uuid PRIMARY KEY,source_type varchar(24) NOT NULL CHECK(source_type IN ('CANCELLATION_ITEM','AFTERSALE_ITEM')),
 source_id uuid NOT NULL UNIQUE,order_item_id uuid NOT NULL REFERENCES order_items(id),offer_id uuid NOT NULL REFERENCES offers(id),
 quantity bigint NOT NULL CHECK(quantity>0),before_on_hand_qty bigint NOT NULL CHECK(before_on_hand_qty>=0),
 resulting_on_hand_qty bigint NOT NULL,resulting_inventory_version bigint NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(before_on_hand_qty+quantity=resulting_on_hand_qty)
);
CREATE TRIGGER immutable_restock BEFORE UPDATE OR DELETE ON inventory_restock_events FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

-- Whole-scope cancellation returns the coupon once, after the original refund completed.
CREATE TABLE coupon_return_events (
 id uuid PRIMARY KEY,coupon_id uuid NOT NULL REFERENCES user_coupons(id),order_id uuid NOT NULL REFERENCES orders(id),
 cancellation_id uuid NOT NULL REFERENCES order_cancellations(id),
 resulting_status varchar(16) NOT NULL CHECK(resulting_status IN ('RETURNED','EXPIRED')),
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(coupon_id,order_id)
);
CREATE TRIGGER immutable_coupon_return BEFORE UPDATE OR DELETE ON coupon_return_events FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

CREATE TABLE aftersales (
 id uuid PRIMARY KEY,suborder_id uuid NOT NULL REFERENCES suborders(id),order_id uuid NOT NULL REFERENCES orders(id),
 user_id uuid NOT NULL REFERENCES app_user(id),merchant_id uuid NOT NULL REFERENCES merchant(id),
 type varchar(20) NOT NULL CHECK(type IN ('REFUND_ONLY','RETURN_REFUND')),
 reason_code varchar(48) NOT NULL CHECK(reason_code IN ('QUALITY_ISSUE','WRONG_ITEM','DAMAGED','NOT_RECEIVED','CONSUMER_REGRET','OTHER')),
 reason_text varchar(500) NOT NULL,
 status varchar(24) NOT NULL DEFAULT 'PENDING_MERCHANT' CHECK(status IN ('PENDING_MERCHANT','WAITING_RETURN','RETURN_IN_TRANSIT','WAITING_INSPECTION','REFUND_PENDING','PLATFORM_ESCALATED','COMPLETED','REJECTED','CANCELLED')),
 return_carrier_code varchar(24),return_tracking_no varchar(80),
 version bigint NOT NULL DEFAULT 0,created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE refunds ADD CONSTRAINT fk_refund_aftersale FOREIGN KEY(aftersale_id) REFERENCES aftersales(id);
CREATE INDEX ix_aftersales_suborder ON aftersales(suborder_id,created_at,id);
CREATE INDEX ix_aftersales_status ON aftersales(status,created_at,id);
CREATE FUNCTION protect_aftersale() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version','return_carrier_code','return_tracking_no']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','return_carrier_code','return_tracking_no']) OR NEW.version<>OLD.version+1
 OR OLD.status IN ('COMPLETED','CANCELLED')
 OR NOT ((OLD.status='PENDING_MERCHANT' AND NEW.status IN ('WAITING_RETURN','REFUND_PENDING','COMPLETED','REJECTED','CANCELLED')) OR (OLD.status='WAITING_RETURN' AND NEW.status IN ('RETURN_IN_TRANSIT','CANCELLED')) OR (OLD.status='RETURN_IN_TRANSIT' AND NEW.status='WAITING_INSPECTION') OR (OLD.status='WAITING_INSPECTION' AND NEW.status IN ('REFUND_PENDING','REJECTED','COMPLETED')) OR (OLD.status='REFUND_PENDING' AND NEW.status='COMPLETED') OR (OLD.status='REJECTED' AND NEW.status='PLATFORM_ESCALATED') OR (OLD.status='PLATFORM_ESCALATED' AND NEW.status IN ('REFUND_PENDING','REJECTED','COMPLETED'))) THEN RAISE EXCEPTION 'invalid aftersale mutation'; END IF; RETURN NEW; END $$;
CREATE TRIGGER aftersale_guard BEFORE UPDATE ON aftersales FOR EACH ROW EXECUTE FUNCTION protect_aftersale();
CREATE TRIGGER aftersale_no_delete BEFORE DELETE ON aftersales FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE aftersale_items (
 id uuid PRIMARY KEY,aftersale_id uuid NOT NULL REFERENCES aftersales(id),order_item_id uuid NOT NULL REFERENCES order_items(id),
 quantity integer NOT NULL CHECK(quantity>0),item_payable_refund_fen bigint NOT NULL CHECK(item_payable_refund_fen>=0),
 refund_id uuid REFERENCES refunds(id),UNIQUE(aftersale_id,order_item_id)
);
CREATE FUNCTION protect_aftersale_item() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-'refund_id') IS DISTINCT FROM (to_jsonb(OLD)-'refund_id') OR OLD.refund_id IS NOT NULL OR NEW.refund_id IS NULL THEN RAISE EXCEPTION 'invalid aftersale item mutation'; END IF; RETURN NEW; END $$;
CREATE TRIGGER aftersale_item_guard BEFORE UPDATE ON aftersale_items FOR EACH ROW EXECUTE FUNCTION protect_aftersale_item();
CREATE TRIGGER aftersale_item_no_delete BEFORE DELETE ON aftersale_items FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE aftersale_events (
 id uuid PRIMARY KEY,aftersale_id uuid NOT NULL REFERENCES aftersales(id),from_status varchar(24) NOT NULL,to_status varchar(24) NOT NULL,
 actor_type varchar(16) NOT NULL CHECK(actor_type IN ('CONSUMER','MERCHANT','ADMIN','SYSTEM')),actor_id uuid,reason varchar(500),
 occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_aftersale_events BEFORE UPDATE OR DELETE ON aftersale_events FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE aftersale_evidence (
 id uuid PRIMARY KEY,aftersale_id uuid NOT NULL REFERENCES aftersales(id),actor_type varchar(16) NOT NULL CHECK(actor_type IN ('CONSUMER','MERCHANT','ADMIN')),
 actor_id uuid NOT NULL,kind varchar(8) NOT NULL CHECK(kind IN ('TEXT','ASSET')),content varchar(1000),asset_id uuid,
 created_at timestamptz NOT NULL DEFAULT now(),CHECK((kind='TEXT' AND content IS NOT NULL AND asset_id IS NULL) OR (kind='ASSET' AND asset_id IS NOT NULL))
);
CREATE TRIGGER immutable_aftersale_evidence BEFORE UPDATE OR DELETE ON aftersale_evidence FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE aftersale_decisions (
 id uuid PRIMARY KEY,aftersale_id uuid NOT NULL REFERENCES aftersales(id),decision varchar(20) NOT NULL CHECK(decision IN ('REFUND_APPROVED','REJECTED')),
 decided_by uuid NOT NULL REFERENCES identity_principal(id),reason varchar(500) NOT NULL,amount_fen bigint NOT NULL CHECK(amount_fen>=0),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_aftersale_decisions BEFORE UPDATE OR DELETE ON aftersale_decisions FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

-- The development channel now supports several partial refunds against one collected transaction.
CREATE TABLE simulated_payment_refund_requests (
 refund_no varchar(48) PRIMARY KEY,transaction_id varchar(100) NOT NULL,amount_fen bigint NOT NULL CHECK(amount_fen>0),
 currency varchar(8) NOT NULL,status varchar(16) NOT NULL CHECK(status='SUCCEEDED'),
 channel_refund_no varchar(100) NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_simulated_refunds BEFORE UPDATE OR DELETE ON simulated_payment_refund_requests FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE simulated_refund_directives (
 refund_no varchar(48) PRIMARY KEY,outcome varchar(20) NOT NULL CHECK(outcome IN ('SUCCEED','FAIL_TRANSIENT','FAIL_FINAL'))
);
INSERT INTO permission(code,description) VALUES
 ('order.cancel.handle','Cancel paid unshipped quantities within authorized scopes'),
 ('aftersale.handle','Decide, receive and inspect after-sale requests within authorized scopes'),
 ('aftersale.arbitrate','Arbitrate escalated after-sale requests after reverify');
