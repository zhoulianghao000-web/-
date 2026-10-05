CREATE TABLE order_policy_versions (
 id uuid PRIMARY KEY, version_no bigserial UNIQUE NOT NULL, version_code varchar(80) NOT NULL UNIQUE,
 reservation_ttl_seconds integer NOT NULL CHECK(reservation_ttl_seconds BETWEEN 60 AND 3600),
 created_by uuid REFERENCES identity_principal(id),created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO order_policy_versions(id,version_code,reservation_ttl_seconds) VALUES ('40000000-0000-0000-0000-000000000001','ORDER_V1_1',900);
CREATE TABLE orders (
 id uuid PRIMARY KEY,order_no varchar(40) NOT NULL UNIQUE,user_id uuid NOT NULL REFERENCES app_user(id),
 quote_id uuid NOT NULL UNIQUE REFERENCES pricing_quotes(id),currency varchar(3) NOT NULL CHECK(currency='CNY'),
 goods_amount_fen bigint NOT NULL CHECK(goods_amount_fen>=0),shipping_amount_fen bigint NOT NULL CHECK(shipping_amount_fen>=0),
 discount_amount_fen bigint NOT NULL CHECK(discount_amount_fen>=0),payable_amount_fen bigint NOT NULL CHECK(payable_amount_fen>=1),
 pricing_snapshot jsonb NOT NULL,policy_version_id uuid NOT NULL REFERENCES order_policy_versions(id),
 reservation_expires_at timestamptz NOT NULL,status varchar(32) NOT NULL DEFAULT 'PENDING_PAYMENT' CHECK(status IN ('PENDING_PAYMENT','CANCELLED')),
 version bigint NOT NULL DEFAULT 0,created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(goods_amount_fen+shipping_amount_fen-discount_amount_fen=payable_amount_fen)
);
ALTER TABLE pricing_quotes ADD CONSTRAINT fk_quote_consumed_order FOREIGN KEY(consumed_order_id) REFERENCES orders(id);
CREATE INDEX ix_orders_owner ON orders(user_id,created_at,id);
CREATE INDEX ix_orders_expiry ON orders(reservation_expires_at) WHERE status='PENDING_PAYMENT';
CREATE TABLE payments (
 id uuid PRIMARY KEY,payment_no varchar(40) NOT NULL UNIQUE,order_id uuid NOT NULL UNIQUE REFERENCES orders(id),
 amount_fen bigint NOT NULL CHECK(amount_fen>=1),currency varchar(3) NOT NULL CHECK(currency='CNY'),
 status varchar(16) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','CLOSED')),
 expires_at timestamptz NOT NULL,version bigint NOT NULL DEFAULT 0,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE suborders (
 id uuid PRIMARY KEY,order_id uuid NOT NULL REFERENCES orders(id),merchant_id uuid NOT NULL REFERENCES merchant(id),
 suborder_no varchar(40) NOT NULL UNIQUE,merchant_name varchar(160) NOT NULL,
 fulfillment_status varchar(32) NOT NULL DEFAULT 'PENDING_PAYMENT' CHECK(fulfillment_status IN ('PENDING_PAYMENT','CANCELLED')),
 goods_amount_fen bigint NOT NULL CHECK(goods_amount_fen>=0),shipping_amount_fen bigint NOT NULL CHECK(shipping_amount_fen>=0),
 discount_amount_fen bigint NOT NULL CHECK(discount_amount_fen>=0),payable_amount_fen bigint NOT NULL CHECK(payable_amount_fen>=0),
 shipping_snapshot jsonb NOT NULL,version bigint NOT NULL DEFAULT 0,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(order_id,merchant_id),CHECK(goods_amount_fen+shipping_amount_fen-discount_amount_fen=payable_amount_fen)
);
CREATE TABLE order_items (
 id uuid PRIMARY KEY,suborder_id uuid NOT NULL REFERENCES suborders(id),allocation_key varchar(12) NOT NULL,
 offer_id uuid NOT NULL REFERENCES offers(id),sku_id uuid NOT NULL REFERENCES skus(id),merchant_id uuid NOT NULL REFERENCES merchant(id),store_id uuid,
 quantity integer NOT NULL CHECK(quantity>0),cancelled_qty integer NOT NULL DEFAULT 0 CHECK(cancelled_qty BETWEEN 0 AND quantity),
 unit_price_fen bigint NOT NULL CHECK(unit_price_fen>=0),goods_amount_fen bigint NOT NULL CHECK(goods_amount_fen>=0),
 discount_amount_fen bigint NOT NULL CHECK(discount_amount_fen>=0),payable_amount_fen bigint NOT NULL CHECK(payable_amount_fen>=0),
 product_snapshot jsonb NOT NULL,UNIQUE(suborder_id,allocation_key),
 CHECK(goods_amount_fen=quantity*unit_price_fen),CHECK(goods_amount_fen-discount_amount_fen=payable_amount_fen),
 FOREIGN KEY(store_id,merchant_id) REFERENCES merchant_store(id,merchant_id)
);
CREATE TABLE order_address_snapshots (order_id uuid PRIMARY KEY REFERENCES orders(id),snapshot jsonb NOT NULL);
CREATE TABLE inventory_reservations (
 id uuid PRIMARY KEY,order_id uuid NOT NULL REFERENCES orders(id),offer_id uuid NOT NULL REFERENCES offers(id),
 quantity bigint NOT NULL CHECK(quantity>0),status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','CONSUMED','RELEASED','EXPIRED')),
 reservation_generation integer NOT NULL DEFAULT 1 CHECK(reservation_generation=1),expires_at timestamptz NOT NULL,
 version bigint NOT NULL DEFAULT 0,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(order_id,offer_id,reservation_generation)
);
CREATE TABLE inventory_reservation_events (
 id uuid PRIMARY KEY,reservation_id uuid NOT NULL REFERENCES inventory_reservations(id),order_id uuid NOT NULL REFERENCES orders(id),
 offer_id uuid NOT NULL REFERENCES offers(id),operation varchar(16) NOT NULL CHECK(operation IN ('RESERVE','RELEASE','EXPIRE')),
 delta_reserved_qty bigint NOT NULL CHECK(delta_reserved_qty<>0),before_reserved_qty bigint NOT NULL CHECK(before_reserved_qty>=0),
 resulting_reserved_qty bigint NOT NULL CHECK(resulting_reserved_qty>=0),resulting_inventory_version bigint NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(reservation_id,operation),CHECK(before_reserved_qty+delta_reserved_qty=resulting_reserved_qty)
);
CREATE TABLE order_coupon_snapshots (
 order_id uuid NOT NULL REFERENCES orders(id),coupon_id uuid NOT NULL REFERENCES user_coupons(id),snapshot jsonb NOT NULL,PRIMARY KEY(order_id,coupon_id)
);
ALTER TABLE user_coupons ADD CONSTRAINT fk_coupon_reserved_order FOREIGN KEY(reserved_order_id) REFERENCES orders(id);
ALTER TABLE user_coupons ADD CONSTRAINT ck_coupon_reservation_fields CHECK(
 (status='RESERVED' AND reserved_order_id IS NOT NULL AND reserved_from_status IN ('AVAILABLE','RETURNED') AND reservation_expires_at IS NOT NULL)
 OR (status<>'RESERVED' AND reserved_order_id IS NULL AND reserved_from_status IS NULL AND reservation_expires_at IS NULL));
CREATE TABLE order_cancellations (
 id uuid PRIMARY KEY,order_id uuid NOT NULL UNIQUE REFERENCES orders(id),actor_type varchar(16) NOT NULL CHECK(actor_type IN ('CONSUMER','SYSTEM')),
 actor_id uuid REFERENCES identity_principal(id),reason_code varchar(48) NOT NULL CHECK(reason_code IN ('CONSUMER_CANCELLED','PAYMENT_WINDOW_EXPIRED')),
 status varchar(16) NOT NULL CHECK(status='COMPLETED'),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE order_cancellation_items (
 id uuid PRIMARY KEY,cancellation_id uuid NOT NULL REFERENCES order_cancellations(id),order_item_id uuid NOT NULL REFERENCES order_items(id),
 quantity integer NOT NULL CHECK(quantity>0),item_payable_refund_fen bigint NOT NULL DEFAULT 0 CHECK(item_payable_refund_fen=0),
 shipping_refund_fen bigint NOT NULL DEFAULT 0 CHECK(shipping_refund_fen=0),allocation_snapshot jsonb NOT NULL,UNIQUE(cancellation_id,order_item_id)
);
CREATE TABLE order_cancellation_events (
 id uuid PRIMARY KEY,cancellation_id uuid NOT NULL UNIQUE REFERENCES order_cancellations(id),from_status varchar(32) NOT NULL,
 to_status varchar(16) NOT NULL CHECK(to_status='COMPLETED'),reason_code varchar(48) NOT NULL,occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION protect_order_state() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version'])
 OR OLD.status<>'PENDING_PAYMENT' OR NEW.status<>'CANCELLED' OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid order mutation'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER order_state_guard BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION protect_order_state();
CREATE FUNCTION protect_suborder_state() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (to_jsonb(NEW)-ARRAY['fulfillment_status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['fulfillment_status','version'])
 OR OLD.fulfillment_status<>'PENDING_PAYMENT' OR NEW.fulfillment_status<>'CANCELLED' OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid suborder mutation'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER suborder_state_guard BEFORE UPDATE ON suborders FOR EACH ROW EXECUTE FUNCTION protect_suborder_state();
CREATE FUNCTION protect_order_item() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (to_jsonb(NEW)-'cancelled_qty') IS DISTINCT FROM (to_jsonb(OLD)-'cancelled_qty') OR NEW.cancelled_qty<>NEW.quantity OR OLD.cancelled_qty<>0 THEN RAISE EXCEPTION 'invalid item mutation'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER order_item_guard BEFORE UPDATE ON order_items FOR EACH ROW EXECUTE FUNCTION protect_order_item();
CREATE FUNCTION protect_payment_intent() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version']) OR OLD.status<>'PENDING' OR NEW.status<>'CLOSED' OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid payment intent mutation'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER payment_intent_guard BEFORE UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION protect_payment_intent();
CREATE FUNCTION protect_inventory_reservation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version']) OR OLD.status<>'ACTIVE' OR NEW.status NOT IN ('RELEASED','EXPIRED') OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid reservation mutation'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER reservation_state_guard BEFORE UPDATE ON inventory_reservations FOR EACH ROW EXECUTE FUNCTION protect_inventory_reservation();
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['order_policy_versions','order_address_snapshots','order_coupon_snapshots','inventory_reservation_events','order_cancellations','order_cancellation_items','order_cancellation_events'] LOOP
 EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['orders','suborders','order_items','payments','inventory_reservations'] LOOP
 EXECUTE format('CREATE TRIGGER no_record_delete BEFORE DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 END LOOP;
END $$;
INSERT INTO permission(code,description) VALUES ('order.read','Read merchant orders within all item scopes'),('order.default-scope','Read orders containing default fulfillment scope'),('order.admin.read','Read platform order facts'),('order.policy.manage','Publish reservation policy after reverify');

ALTER TABLE orders ADD CONSTRAINT uq_order_quote_pair UNIQUE(id,quote_id);
ALTER TABLE pricing_quotes ADD CONSTRAINT fk_quote_order_pair FOREIGN KEY(consumed_order_id,id) REFERENCES orders(id,quote_id);
ALTER TABLE suborders ADD CONSTRAINT uq_suborder_merchant_pair UNIQUE(id,merchant_id);
ALTER TABLE order_items ADD CONSTRAINT fk_item_suborder_merchant FOREIGN KEY(suborder_id,merchant_id) REFERENCES suborders(id,merchant_id);
ALTER TABLE order_items ADD CONSTRAINT fk_item_offer_merchant FOREIGN KEY(offer_id,merchant_id) REFERENCES offers(id,merchant_id);
CREATE FUNCTION verify_order_commit() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE q pricing_quotes%ROWTYPE; totals record; payment payments%ROWTYPE;
BEGIN
 SELECT * INTO q FROM pricing_quotes WHERE id=NEW.quote_id;
 IF q.status<>'CONSUMED' OR q.consumed_order_id<>NEW.id OR q.user_id<>NEW.user_id
 OR q.payable_amount_fen<>NEW.payable_amount_fen OR q.result_snapshot IS DISTINCT FROM NEW.pricing_snapshot THEN RAISE EXCEPTION 'order quote consistency'; END IF;
 SELECT coalesce(sum(goods_amount_fen),0) goods,coalesce(sum(shipping_amount_fen),0) shipping,coalesce(sum(discount_amount_fen),0) discount,coalesce(sum(payable_amount_fen),0) payable INTO totals FROM suborders WHERE order_id=NEW.id;
 IF totals.goods<>NEW.goods_amount_fen OR totals.shipping<>NEW.shipping_amount_fen OR totals.discount<>NEW.discount_amount_fen OR totals.payable<>NEW.payable_amount_fen THEN RAISE EXCEPTION 'order group conservation'; END IF;
 SELECT * INTO payment FROM payments WHERE order_id=NEW.id;
 IF payment.id IS NULL OR payment.amount_fen<>NEW.payable_amount_fen OR payment.currency<>NEW.currency OR payment.expires_at<>NEW.reservation_expires_at THEN RAISE EXCEPTION 'order payment consistency'; END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER order_commit_consistency AFTER INSERT ON orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_order_commit();
CREATE FUNCTION verify_cancelled_quantity() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE accepted bigint;
BEGIN
 SELECT coalesce(sum(i.quantity),0) INTO accepted FROM order_cancellation_items i JOIN order_cancellations c ON c.id=i.cancellation_id WHERE i.order_item_id=NEW.id AND c.status='COMPLETED';
 IF accepted<>NEW.cancelled_qty THEN RAISE EXCEPTION 'cancelled quantity cache has no cancellation evidence'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER cancellation_cache_guard BEFORE UPDATE ON order_items FOR EACH ROW EXECUTE FUNCTION verify_cancelled_quantity();
