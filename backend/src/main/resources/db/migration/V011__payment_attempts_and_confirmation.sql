ALTER TABLE orders DROP CONSTRAINT orders_status_check;
ALTER TABLE orders ADD CHECK(status IN ('PENDING_PAYMENT','FULFILLING','CANCELLED'));
ALTER TABLE payments DROP CONSTRAINT payments_status_check;
ALTER TABLE payments ADD CHECK(status IN ('PENDING','PROCESSING','SUCCEEDED','CLOSED'));
ALTER TABLE suborders DROP CONSTRAINT suborders_fulfillment_status_check;
ALTER TABLE suborders ADD CHECK(fulfillment_status IN ('PENDING_PAYMENT','PAID_WAITING_FULFILLMENT','CANCELLED'));
ALTER TABLE inventory_reservation_events DROP CONSTRAINT inventory_reservation_events_operation_check;
ALTER TABLE inventory_reservation_events ADD CHECK(operation IN ('RESERVE','RELEASE','EXPIRE','CONSUME'));
CREATE TABLE payment_attempts (
 id uuid PRIMARY KEY,payment_id uuid NOT NULL REFERENCES payments(id),attempt_no varchar(48) NOT NULL UNIQUE,
 channel varchar(16) NOT NULL CHECK(channel IN ('WECHAT','ALIPAY')),
 client_platform varchar(16) NOT NULL CHECK(client_platform IN ('IOS','ANDROID','WEB')),
 status varchar(32) NOT NULL DEFAULT 'CREATED' CHECK(status IN ('CREATED','CHANNEL_PENDING','UNKNOWN','CHANNEL_SUCCEEDED','CHANNEL_FAILED','CANCELLED')),
 version bigint NOT NULL DEFAULT 0,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,payment_id)
);
CREATE TABLE payment_requery_schedule (attempt_id uuid PRIMARY KEY REFERENCES payment_attempts(id),next_query_at timestamptz NOT NULL DEFAULT now(),failure_count integer NOT NULL DEFAULT 0);
CREATE UNIQUE INDEX uq_payment_active_attempt ON payment_attempts(payment_id) WHERE status IN ('CREATED','CHANNEL_PENDING','UNKNOWN');
CREATE TABLE payment_receipts (
 id uuid PRIMARY KEY,attempt_id uuid NOT NULL REFERENCES payment_attempts(id),provider varchar(32) NOT NULL,
 channel_transaction_id varchar(100) NOT NULL,amount_fen bigint NOT NULL CHECK(amount_fen>0),currency varchar(8) NOT NULL,
 received_at timestamptz NOT NULL DEFAULT now(),UNIQUE(provider,channel_transaction_id),UNIQUE(id,attempt_id)
);
ALTER TABLE payments ADD COLUMN successful_attempt_id uuid;
ALTER TABLE payments ADD COLUMN successful_receipt_id uuid UNIQUE;
ALTER TABLE payments ADD COLUMN paid_at timestamptz;
ALTER TABLE payments ADD CONSTRAINT fk_payment_success_attempt FOREIGN KEY(successful_attempt_id,id) REFERENCES payment_attempts(id,payment_id);
ALTER TABLE payments ADD CONSTRAINT fk_payment_success_receipt FOREIGN KEY(successful_receipt_id,successful_attempt_id) REFERENCES payment_receipts(id,attempt_id);
ALTER TABLE payments ADD CHECK((status='SUCCEEDED' AND successful_attempt_id IS NOT NULL AND successful_receipt_id IS NOT NULL AND paid_at IS NOT NULL) OR (status<>'SUCCEEDED' AND successful_attempt_id IS NULL AND successful_receipt_id IS NULL AND paid_at IS NULL));
CREATE TABLE inventory_sale_events (
 id uuid PRIMARY KEY,reservation_id uuid NOT NULL UNIQUE REFERENCES inventory_reservations(id),payment_id uuid NOT NULL REFERENCES payments(id),
 offer_id uuid NOT NULL REFERENCES offers(id),quantity bigint NOT NULL CHECK(quantity>0),
 before_on_hand_qty bigint NOT NULL,resulting_on_hand_qty bigint NOT NULL CHECK(resulting_on_hand_qty>=0),
 before_reserved_qty bigint NOT NULL,resulting_reserved_qty bigint NOT NULL CHECK(resulting_reserved_qty>=0),
 resulting_inventory_version bigint NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(before_on_hand_qty-quantity=resulting_on_hand_qty),CHECK(before_reserved_qty-quantity=resulting_reserved_qty)
);
CREATE TABLE coupon_redemption_events (
 id uuid PRIMARY KEY,coupon_id uuid NOT NULL REFERENCES user_coupons(id),order_id uuid NOT NULL REFERENCES orders(id),
 payment_id uuid NOT NULL REFERENCES payments(id),created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(coupon_id,order_id)
);
CREATE TABLE payment_cases (
 id uuid PRIMARY KEY,payment_id uuid NOT NULL REFERENCES payments(id),attempt_id uuid NOT NULL REFERENCES payment_attempts(id),
 receipt_id uuid NOT NULL UNIQUE REFERENCES payment_receipts(id),reason_code varchar(32) NOT NULL CHECK(reason_code IN ('LATE_COLLECTION','DUPLICATE_COLLECTION','AMOUNT_MISMATCH','CURRENCY_MISMATCH')),
 refund_no varchar(48) NOT NULL UNIQUE,status varchar(24) NOT NULL DEFAULT 'REFUND_PENDING' CHECK(status IN ('REFUND_PENDING','REFUNDED','NEEDS_REVIEW')),
 attempt_count integer NOT NULL DEFAULT 0,next_retry_at timestamptz NOT NULL DEFAULT now(),last_error_code varchar(80),created_at timestamptz NOT NULL DEFAULT now()
);
-- The simulator is a durable stand-in for a channel, isolated from the core transaction.
-- These records never imply collection by a real provider.
CREATE TABLE simulated_payment_transactions (
 attempt_no varchar(48) PRIMARY KEY,channel varchar(16) NOT NULL,amount_fen bigint NOT NULL CHECK(amount_fen>0),currency varchar(8) NOT NULL,
 status varchar(16) NOT NULL CHECK(status IN ('PENDING','SUCCEEDED','FAILED','CLOSED','UNKNOWN')),
 transaction_id varchar(100) UNIQUE,updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE simulated_payment_refunds (
 refund_no varchar(48) PRIMARY KEY,transaction_id varchar(100) NOT NULL UNIQUE,amount_fen bigint NOT NULL CHECK(amount_fen>0),currency varchar(8) NOT NULL,
 status varchar(16) NOT NULL CHECK(status='SUCCEEDED'),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION protect_order_state() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version'])
 OR OLD.status<>'PENDING_PAYMENT' OR NEW.status NOT IN ('CANCELLED','FULFILLING') OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid order mutation'; END IF; RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION protect_suborder_state() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['fulfillment_status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['fulfillment_status','version'])
 OR OLD.fulfillment_status<>'PENDING_PAYMENT' OR NEW.fulfillment_status NOT IN ('CANCELLED','PAID_WAITING_FULFILLMENT') OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid suborder mutation'; END IF; RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION protect_inventory_reservation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version'])
 OR OLD.status<>'ACTIVE' OR NEW.status NOT IN ('RELEASED','EXPIRED','CONSUMED') OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid reservation mutation'; END IF; RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION protect_payment_intent() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version','successful_attempt_id','successful_receipt_id','paid_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','successful_attempt_id','successful_receipt_id','paid_at'])
 OR OLD.status IN ('SUCCEEDED','CLOSED') OR NEW.version<>OLD.version+1
 OR NOT ((OLD.status='PENDING' AND NEW.status IN ('PROCESSING','CLOSED')) OR (OLD.status='PROCESSING' AND NEW.status IN ('PENDING','SUCCEEDED')))
 THEN RAISE EXCEPTION 'invalid payment mutation'; END IF; RETURN NEW; END $$;
CREATE FUNCTION protect_payment_attempt() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version']) OR NEW.version<>OLD.version+1
 OR OLD.status='CHANNEL_SUCCEEDED' OR NEW.status='CREATED' THEN RAISE EXCEPTION 'invalid attempt mutation'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER payment_attempt_guard BEFORE UPDATE ON payment_attempts FOR EACH ROW EXECUTE FUNCTION protect_payment_attempt();
CREATE FUNCTION protect_payment_case() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','last_error_code','attempt_count','next_retry_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','last_error_code','attempt_count','next_retry_at']) OR OLD.status='REFUNDED'
 THEN RAISE EXCEPTION 'invalid case mutation'; END IF; RETURN NEW; END $$;
CREATE TRIGGER payment_case_guard BEFORE UPDATE ON payment_cases FOR EACH ROW EXECUTE FUNCTION protect_payment_case();
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['payment_receipts','inventory_sale_events','coupon_redemption_events','simulated_payment_refunds'] LOOP
 EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t); END LOOP;
 FOREACH t IN ARRAY ARRAY['payment_attempts','payment_cases'] LOOP
 EXECUTE format('CREATE TRIGGER no_record_delete BEFORE DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t); END LOOP;
END $$;
CREATE FUNCTION verify_payment_success_commit() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE a payment_attempts%ROWTYPE;r payment_receipts%ROWTYPE; BEGIN
 IF NEW.status<>'SUCCEEDED' THEN RETURN NULL; END IF;
 SELECT * INTO a FROM payment_attempts WHERE id=NEW.successful_attempt_id;SELECT * INTO r FROM payment_receipts WHERE id=NEW.successful_receipt_id;
 IF a.status<>'CHANNEL_SUCCEEDED' OR r.amount_fen<>NEW.amount_fen OR r.currency<>NEW.currency
 OR NOT EXISTS(SELECT 1 FROM orders WHERE id=NEW.order_id AND status='FULFILLING')
 OR EXISTS(SELECT 1 FROM suborders WHERE order_id=NEW.order_id AND fulfillment_status<>'PAID_WAITING_FULFILLMENT')
 OR EXISTS(SELECT 1 FROM inventory_reservations WHERE order_id=NEW.order_id AND status<>'CONSUMED')
 THEN RAISE EXCEPTION 'payment success consistency'; END IF; RETURN NULL; END $$;
CREATE CONSTRAINT TRIGGER payment_success_consistency AFTER UPDATE ON payments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_payment_success_commit();
INSERT INTO permission(code,description) VALUES ('payment.read','Read payment facts'),('payment.requery','Requery payment after reverify');
