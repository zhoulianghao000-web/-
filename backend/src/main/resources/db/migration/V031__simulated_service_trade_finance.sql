-- B2 is synthetic engineering only. Existing free bookings remain free.
INSERT INTO permission(code,description) VALUES
 ('service.trade.cancel','Cancel scoped synthetic service trades'),
 ('service.trade.refund.assess','Assess synthetic service refunds'),
 ('service.trade.refund.review','Review synthetic service refunds after reverify') ON CONFLICT DO NOTHING;
ALTER TABLE payments ADD service_trade_id uuid UNIQUE REFERENCES service_trade_orders(id);
ALTER TABLE payments DROP CONSTRAINT payments_exactly_one_owner;
ALTER TABLE payments ADD CONSTRAINT payments_exactly_one_owner CHECK(num_nonnulls(order_id,membership_order_id,service_trade_id)=1);
ALTER TABLE payment_attempts DROP CONSTRAINT payment_attempts_channel_check;
ALTER TABLE payment_attempts ADD CHECK(channel IN ('WECHAT','ALIPAY','SIMULATED_TEST'));
ALTER TABLE service_trade_orders ADD receipt_id uuid UNIQUE REFERENCES payment_receipts(id), ADD confirmed_at timestamptz,
 ADD fulfillment_state varchar(20) NOT NULL DEFAULT 'NOT_STARTED' CHECK(fulfillment_state='NOT_STARTED'),
 ADD cancel_reason varchar(32);
ALTER TABLE service_trade_orders DISABLE TRIGGER immutable_service_trade;
UPDATE service_trade_orders SET cancel_reason=CASE order_state WHEN 'CANCELLED' THEN 'CONSUMER_CANCELLED' WHEN 'EXPIRED' THEN 'PAYMENT_WINDOW_EXPIRED' END WHERE order_state<>'AWAITING_PAYMENT';
ALTER TABLE service_trade_orders ENABLE TRIGGER immutable_service_trade;
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='service_trade_orders'::regclass AND contype='c'
 AND pg_get_constraintdef(oid) ~ '(order_state|payment_state|capacity_state)' LOOP
 EXECUTE format('ALTER TABLE service_trade_orders DROP CONSTRAINT %I',c.conname); END LOOP;
END $$;
ALTER TABLE service_trade_orders ADD CHECK(order_state IN ('AWAITING_PAYMENT','CONFIRMED','CANCELLED','EXPIRED')),
 ADD CHECK(payment_state IN ('PENDING','SUCCEEDED','CLOSED')), ADD CHECK(capacity_state IN ('HELD','CONFIRMED','RELEASED')),
 ADD CHECK((order_state='AWAITING_PAYMENT' AND payment_state='PENDING' AND capacity_state='HELD' AND closed_at IS NULL AND receipt_id IS NULL AND confirmed_at IS NULL AND cancel_reason IS NULL)
 OR (order_state='CONFIRMED' AND payment_state='SUCCEEDED' AND capacity_state='CONFIRMED' AND closed_at IS NULL AND receipt_id IS NOT NULL AND confirmed_at IS NOT NULL AND cancel_reason IS NULL)
 OR (order_state='CANCELLED' AND payment_state='SUCCEEDED' AND capacity_state='RELEASED' AND closed_at IS NOT NULL AND receipt_id IS NOT NULL AND confirmed_at IS NOT NULL AND cancel_reason IN ('CONSUMER_CANCELLED','SERVICE_UNAVAILABLE'))
 OR (order_state IN ('CANCELLED','EXPIRED') AND payment_state='CLOSED' AND capacity_state='RELEASED' AND closed_at IS NOT NULL AND receipt_id IS NULL AND confirmed_at IS NULL AND cancel_reason IN ('CONSUMER_CANCELLED','SERVICE_UNAVAILABLE','PAYMENT_WINDOW_EXPIRED')));
DROP INDEX service_trade_one_hold; DROP INDEX service_trade_capacity;
CREATE UNIQUE INDEX service_trade_one_hold ON service_trade_orders(user_id,slot_id) WHERE capacity_state IN ('HELD','CONFIRMED');
CREATE INDEX service_trade_capacity ON service_trade_orders(slot_id) WHERE capacity_state IN ('HELD','CONFIRMED');
CREATE OR REPLACE FUNCTION protect_service_trade_hold() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF TG_OP='DELETE' OR NEW.version<>OLD.version+1
 OR (to_jsonb(NEW)-ARRAY['order_state','payment_state','capacity_state','version','closed_at','receipt_id','confirmed_at','cancel_reason']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['order_state','payment_state','capacity_state','version','closed_at','receipt_id','confirmed_at','cancel_reason'])
 OR NOT ((OLD.order_state='AWAITING_PAYMENT' AND NEW.order_state IN ('CONFIRMED','CANCELLED','EXPIRED'))
 OR (OLD.payment_state='SUCCEEDED' AND NEW.payment_state='SUCCEEDED' AND NEW.receipt_id=OLD.receipt_id AND NEW.confirmed_at=OLD.confirmed_at
 AND ((OLD.order_state='CONFIRMED' AND NEW.order_state IN ('CONFIRMED','CANCELLED')) OR (OLD.order_state='CANCELLED' AND NEW.order_state='CANCELLED' AND NEW.closed_at=OLD.closed_at AND NEW.cancel_reason=OLD.cancel_reason))))
 THEN RAISE EXCEPTION 'immutable service trade state'; END IF; RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION guard_shared_service_capacity() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE maximum integer; used integer; BEGIN
 SELECT capacity INTO STRICT maximum FROM booking_slots WHERE id=NEW.slot_id FOR UPDATE;
 SELECT (SELECT count(*) FROM service_bookings WHERE slot_id=NEW.slot_id AND status='BOOKED')+
 (SELECT count(*) FROM service_trade_orders WHERE slot_id=NEW.slot_id AND capacity_state IN ('HELD','CONFIRMED')) INTO used;
 IF used>=maximum THEN RAISE EXCEPTION 'service slot full'; END IF;
 IF EXISTS(SELECT 1 FROM service_bookings WHERE slot_id=NEW.slot_id AND user_id=NEW.user_id AND status='BOOKED')
 OR EXISTS(SELECT 1 FROM service_trade_orders WHERE slot_id=NEW.slot_id AND user_id=NEW.user_id AND capacity_state IN ('HELD','CONFIRMED'))
 THEN RAISE EXCEPTION 'duplicate service slot owner'; END IF; RETURN NEW;
END $$;
-- Intents are not collections: backfill no attempts, receipts, refunds or ledger.
INSERT INTO payments(id,payment_no,service_trade_id,amount_fen,currency,status,expires_at,created_at)
 SELECT gen_random_uuid(),'SP'||replace(id::text,'-',''),id,payable_fen,'CNY',CASE WHEN order_state='AWAITING_PAYMENT' THEN 'PENDING' ELSE 'CLOSED' END,hold_expires_at,created_at FROM service_trade_orders;
CREATE TABLE service_trade_refunds (
 id uuid PRIMARY KEY,trade_id uuid NOT NULL REFERENCES service_trade_orders(id),payment_id uuid NOT NULL REFERENCES payments(id),
 receipt_id uuid NOT NULL REFERENCES payment_receipts(id),payment_case_id uuid UNIQUE REFERENCES payment_cases(id),
 business_key varchar(160) NOT NULL UNIQUE,refund_no varchar(48) NOT NULL UNIQUE,
 source_kind varchar(20) NOT NULL CHECK(source_kind IN ('CANCELLATION','ADMIN','COMPENSATION','TEST_INTERNAL')),
 amount_fen bigint NOT NULL CHECK(amount_fen>0),currency varchar(8) NOT NULL,
 state varchar(24) NOT NULL DEFAULT 'RESERVED' CHECK(state IN ('RESERVED','PROCESSING','UNKNOWN','SUCCEEDED','FAILED_RETRYABLE','NEEDS_REVIEW')),
 attempt_count integer NOT NULL DEFAULT 0 CHECK(attempt_count BETWEEN 0 AND 8),version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
 lease_token uuid,lease_until timestamptz,next_retry_at timestamptz NOT NULL DEFAULT now(),last_error_code varchar(80),
 channel_refund_no varchar(100),created_at timestamptz NOT NULL,decided_at timestamptz,
 CHECK((state='PROCESSING')=(lease_token IS NOT NULL AND lease_until IS NOT NULL)),
 CHECK((state='SUCCEEDED')=(channel_refund_no IS NOT NULL AND decided_at IS NOT NULL)),
 CHECK((source_kind='COMPENSATION')=(payment_case_id IS NOT NULL))
);
CREATE INDEX service_refund_due ON service_trade_refunds(next_retry_at,id) WHERE state NOT IN ('SUCCEEDED','NEEDS_REVIEW');
CREATE TABLE service_trade_money_events (
 id uuid PRIMARY KEY,trade_id uuid NOT NULL REFERENCES service_trade_orders(id),payment_id uuid NOT NULL REFERENCES payments(id),
 receipt_id uuid NOT NULL REFERENCES payment_receipts(id),refund_id uuid UNIQUE REFERENCES service_trade_refunds(id),
 entry_type varchar(24) NOT NULL CHECK(entry_type IN ('SERVICE_COLLECTION','SERVICE_REFUND')),
 amount_fen bigint NOT NULL CHECK(amount_fen BETWEEN 1 AND 1000000000),currency varchar(3) NOT NULL CHECK(currency='CNY'),occurred_at timestamptz NOT NULL,
 CHECK((entry_type='SERVICE_REFUND')=(refund_id IS NOT NULL))
);
CREATE UNIQUE INDEX service_one_collection ON service_trade_money_events(payment_id) WHERE entry_type='SERVICE_COLLECTION';
CREATE TABLE service_trade_refund_assessments (
 id uuid PRIMARY KEY,trade_id uuid NOT NULL REFERENCES service_trade_orders(id),trade_version bigint NOT NULL,
 terms_sha256 varchar(64) NOT NULL,receipt_id uuid REFERENCES payment_receipts(id),proposed_refund_fen bigint NOT NULL CHECK(proposed_refund_fen BETWEEN 0 AND 1000000000),
 basis_code varchar(32) NOT NULL CHECK(basis_code IN ('BEFORE_CUTOFF','MERCHANT_CANCEL','MANUAL_REVIEW_REQUIRED')),
 eligible_for_approval boolean NOT NULL,created_by uuid NOT NULL REFERENCES identity_principal(id),created_at timestamptz NOT NULL,expires_at timestamptz NOT NULL,
 CHECK(expires_at=created_at+interval '5 minutes'),CHECK(NOT eligible_for_approval OR (receipt_id IS NOT NULL AND proposed_refund_fen>0 AND basis_code<>'MANUAL_REVIEW_REQUIRED'))
);
CREATE TABLE service_trade_refund_decisions (
 id uuid PRIMARY KEY,trade_id uuid NOT NULL REFERENCES service_trade_orders(id),assessment_id uuid NOT NULL UNIQUE REFERENCES service_trade_refund_assessments(id),
 decision varchar(8) NOT NULL CHECK(decision IN ('APPROVE','REJECT')),reason_code varchar(32) NOT NULL CHECK(reason_code IN ('SNAPSHOT_RULES_APPLY','EVIDENCE_INSUFFICIENT')),
 refund_id uuid UNIQUE REFERENCES service_trade_refunds(id),version bigint NOT NULL,created_by uuid NOT NULL REFERENCES identity_principal(id),decided_at timestamptz NOT NULL,
 CHECK((decision='APPROVE')=(refund_id IS NOT NULL))
);
CREATE FUNCTION guard_service_refund_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t service_trade_orders; p payments; r payment_receipts; used bigint; BEGIN
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id;
 PERFORM id FROM booking_slots WHERE id=t.slot_id FOR UPDATE; PERFORM id FROM service_trade_orders WHERE id=t.id FOR UPDATE;
 SELECT * INTO STRICT p FROM payments WHERE id=NEW.payment_id FOR UPDATE;
 SELECT * INTO STRICT r FROM payment_receipts WHERE id=NEW.receipt_id FOR UPDATE;
 IF p.service_trade_id IS DISTINCT FROM t.id OR NOT EXISTS(SELECT 1 FROM payment_attempts a WHERE a.id=r.attempt_id AND a.payment_id=p.id)
 OR NEW.currency<>r.currency OR NEW.state<>'RESERVED' OR NEW.attempt_count<>0 OR NEW.version<>0
 THEN RAISE EXCEPTION 'service refund ownership'; END IF;
 IF NEW.source_kind='COMPENSATION' THEN
  IF NOT EXISTS(SELECT 1 FROM payment_cases c WHERE c.id=NEW.payment_case_id AND c.payment_id=p.id AND c.receipt_id=r.id AND c.refund_no=NEW.refund_no)
  OR p.successful_receipt_id=r.id THEN RAISE EXCEPTION 'service compensation source'; END IF;
 ELSIF p.status<>'SUCCEEDED' OR p.successful_receipt_id IS DISTINCT FROM r.id OR EXISTS(SELECT 1 FROM payment_cases WHERE receipt_id=r.id)
 THEN RAISE EXCEPTION 'service refundable collection missing'; END IF;
 SELECT coalesce(sum(amount_fen),0) INTO used FROM service_trade_refunds WHERE receipt_id=r.id;
 IF used+NEW.amount_fen>r.amount_fen THEN RAISE EXCEPTION 'service refund cap exceeded'; END IF; RETURN NEW;
END $$;
CREATE TRIGGER service_refund_insert_guard BEFORE INSERT ON service_trade_refunds FOR EACH ROW EXECUTE FUNCTION guard_service_refund_insert();
CREATE FUNCTION protect_service_refund() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 -- Scheduling a retry does not change the instruction, result, or lease ownership.
 IF TG_OP='UPDATE' AND OLD.state<>'SUCCEEDED' AND NEW.version=OLD.version+1
 AND (to_jsonb(NEW)-ARRAY['version','next_retry_at'])=(to_jsonb(OLD)-ARRAY['version','next_retry_at']) THEN RETURN NEW; END IF;
 IF TG_OP='DELETE' OR OLD.state='SUCCEEDED' OR NEW.version<>OLD.version+1
 OR (to_jsonb(NEW)-ARRAY['state','attempt_count','version','lease_token','lease_until','next_retry_at','last_error_code','channel_refund_no','decided_at']) IS DISTINCT FROM
 (to_jsonb(OLD)-ARRAY['state','attempt_count','version','lease_token','lease_until','next_retry_at','last_error_code','channel_refund_no','decided_at'])
 OR (NEW.state='PROCESSING' AND (NEW.attempt_count<>OLD.attempt_count+1 OR (OLD.lease_until IS NOT NULL AND OLD.lease_until>clock_timestamp())))
 OR (NEW.state IN ('SUCCEEDED','UNKNOWN','NEEDS_REVIEW') AND OLD.state<>'PROCESSING')
 OR (NEW.state='FAILED_RETRYABLE' AND OLD.state NOT IN ('PROCESSING','NEEDS_REVIEW'))
 OR (OLD.state='NEEDS_REVIEW' AND NOT(NEW.state='FAILED_RETRYABLE' AND NEW.attempt_count=0))
 THEN RAISE EXCEPTION 'immutable service refund instruction'; END IF; RETURN NEW;
END $$;
CREATE TRIGGER service_refund_state_guard BEFORE UPDATE OR DELETE ON service_trade_refunds FOR EACH ROW EXECUTE FUNCTION protect_service_refund();
CREATE FUNCTION guard_service_money_event() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM payments p JOIN payment_receipts r ON r.id=NEW.receipt_id
 WHERE p.id=NEW.payment_id AND p.service_trade_id=NEW.trade_id AND p.status='SUCCEEDED' AND p.successful_receipt_id=r.id AND p.currency=NEW.currency
 AND ((NEW.entry_type='SERVICE_COLLECTION' AND NEW.amount_fen=p.amount_fen)
 OR (NEW.entry_type='SERVICE_REFUND' AND EXISTS(SELECT 1 FROM service_trade_refunds f WHERE f.id=NEW.refund_id AND f.receipt_id=r.id AND f.payment_id=p.id AND f.trade_id=NEW.trade_id AND f.state='SUCCEEDED' AND f.amount_fen=NEW.amount_fen AND f.source_kind<>'COMPENSATION'))))
 THEN RAISE EXCEPTION 'service money event source'; END IF; RETURN NEW;
END $$;
CREATE TRIGGER service_money_event_guard BEFORE INSERT ON service_trade_money_events FOR EACH ROW EXECUTE FUNCTION guard_service_money_event();
CREATE FUNCTION verify_service_trade_finance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t service_trade_orders;p payments; tid uuid; BEGIN
 tid=CASE WHEN TG_TABLE_NAME='payments' THEN (to_jsonb(NEW)->>'service_trade_id')::uuid ELSE NEW.id END;
 IF tid IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=tid;SELECT * INTO STRICT p FROM payments WHERE service_trade_id=tid;
 IF p.amount_fen<>t.payable_fen OR p.currency<>'CNY' OR p.expires_at<>t.hold_expires_at
 OR (t.order_state='AWAITING_PAYMENT' AND p.status NOT IN ('PENDING','PROCESSING'))
 OR (t.payment_state='CLOSED' AND p.status<>'CLOSED')
 OR (t.order_state='CANCELLED' AND t.payment_state='SUCCEEDED' AND (SELECT coalesce(sum(amount_fen),0) FROM service_trade_refunds WHERE trade_id=t.id AND source_kind<>'COMPENSATION')<>p.amount_fen)
 OR (t.payment_state='SUCCEEDED' AND (p.status<>'SUCCEEDED' OR p.successful_receipt_id IS DISTINCT FROM t.receipt_id OR NOT EXISTS
 (SELECT 1 FROM service_trade_money_events e WHERE e.trade_id=t.id AND e.payment_id=p.id AND e.receipt_id=t.receipt_id AND e.entry_type='SERVICE_COLLECTION' AND e.amount_fen=p.amount_fen)))
 THEN RAISE EXCEPTION 'service trade finance consistency'; END IF; RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER service_trade_finance_commit AFTER INSERT OR UPDATE ON service_trade_orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_service_trade_finance();
CREATE CONSTRAINT TRIGGER service_payment_finance_commit AFTER INSERT OR UPDATE ON payments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_service_trade_finance();
CREATE OR REPLACE FUNCTION verify_payment_success_commit() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE a payment_attempts;r payment_receipts; BEGIN
 IF NEW.status<>'SUCCEEDED' THEN RETURN NULL; END IF;
 SELECT * INTO STRICT a FROM payment_attempts WHERE id=NEW.successful_attempt_id;SELECT * INTO STRICT r FROM payment_receipts WHERE id=NEW.successful_receipt_id;
 IF a.payment_id<>NEW.id OR r.attempt_id<>a.id OR a.status<>'CHANNEL_SUCCEEDED' OR r.amount_fen<>NEW.amount_fen OR r.currency<>NEW.currency THEN RAISE EXCEPTION 'payment success consistency'; END IF;
 IF NEW.service_trade_id IS NOT NULL THEN
  IF a.channel<>'SIMULATED_TEST' OR NOT EXISTS(SELECT 1 FROM service_trade_orders t WHERE t.id=NEW.service_trade_id AND t.payment_state='SUCCEEDED' AND t.receipt_id=r.id)
  THEN RAISE EXCEPTION 'service payment success consistency'; END IF; RETURN NULL; END IF;
 IF NEW.membership_order_id IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM membership_orders mo WHERE mo.id=NEW.membership_order_id AND mo.payment_id=NEW.id AND mo.status='PAID' AND mo.amount_fen=NEW.amount_fen) THEN RAISE EXCEPTION 'payment success consistency'; END IF; RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM orders WHERE id=NEW.order_id AND status='FULFILLING')
 OR EXISTS(SELECT 1 FROM suborders WHERE order_id=NEW.order_id AND fulfillment_status<>'PAID_WAITING_FULFILLMENT')
 OR EXISTS(SELECT 1 FROM inventory_reservations v WHERE v.order_id=NEW.order_id AND (v.status<>'CONSUMED' OR NOT EXISTS(SELECT 1 FROM inventory_sale_events e WHERE e.reservation_id=v.id AND e.payment_id=NEW.id AND e.offer_id=v.offer_id AND e.quantity=v.quantity)))
 OR EXISTS(SELECT 1 FROM order_coupon_snapshots c WHERE c.order_id=NEW.order_id AND NOT EXISTS(SELECT 1 FROM coupon_redemption_events e JOIN user_coupons u ON u.id=e.coupon_id WHERE e.order_id=c.order_id AND e.coupon_id=c.coupon_id AND e.payment_id=NEW.id AND u.status='USED'))
 THEN RAISE EXCEPTION 'payment success consistency'; END IF; RETURN NULL;
END $$;
CREATE FUNCTION service_refund_success_commit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.state='SUCCEEDED' AND ((NEW.source_kind='COMPENSATION' AND NOT EXISTS(SELECT 1 FROM payment_cases WHERE id=NEW.payment_case_id AND status='REFUNDED'))
 OR (NEW.source_kind<>'COMPENSATION' AND NOT EXISTS(SELECT 1 FROM service_trade_money_events WHERE refund_id=NEW.id AND entry_type='SERVICE_REFUND' AND amount_fen=NEW.amount_fen)))
 THEN RAISE EXCEPTION 'service refund success evidence'; END IF; RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER service_refund_success_consistency AFTER UPDATE ON service_trade_refunds DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION service_refund_success_commit();
CREATE FUNCTION reject_service_in_goods_refund() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM payments WHERE id=NEW.payment_id AND service_trade_id IS NOT NULL) THEN RAISE EXCEPTION 'service refund cannot use goods pipeline'; END IF;RETURN NEW;
END $$;
CREATE TRIGGER goods_refund_owner_guard BEFORE INSERT ON refunds FOR EACH ROW EXECUTE FUNCTION reject_service_in_goods_refund();
CREATE FUNCTION guard_service_attempt_owner() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE service uuid; BEGIN
 SELECT service_trade_id INTO STRICT service FROM payments WHERE id=NEW.payment_id;
 IF (service IS NOT NULL AND (NEW.channel<>'SIMULATED_TEST' OR NEW.client_platform NOT IN ('ANDROID','WEB')))
 OR (service IS NULL AND NEW.channel='SIMULATED_TEST') THEN RAISE EXCEPTION 'service channel ownership'; END IF;RETURN NEW;
END $$;
CREATE TRIGGER service_attempt_owner BEFORE INSERT ON payment_attempts FOR EACH ROW EXECUTE FUNCTION guard_service_attempt_owner();
CREATE FUNCTION guard_service_assessment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t service_trade_orders;p payments; start_time timestamptz; used bigint;BEGIN
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id;SELECT * INTO STRICT p FROM payments WHERE service_trade_id=t.id;
 SELECT starts_at INTO STRICT start_time FROM booking_slots WHERE id=t.slot_id;
 SELECT coalesce(sum(amount_fen),0) INTO used FROM service_trade_refunds WHERE receipt_id=p.successful_receipt_id;
 IF NEW.trade_version<>t.version OR NEW.terms_sha256<>t.terms_sha256 OR NEW.receipt_id IS DISTINCT FROM p.successful_receipt_id
 OR (NOT NEW.eligible_for_approval AND NEW.proposed_refund_fen<>0)
 OR (NEW.eligible_for_approval AND (NOT coalesce(t.snapshot->>'currency'='CNY' AND t.snapshot->>'billing_unit'='WHOLE_SLOT' AND t.snapshot->>'merchant_cancel'='FULL_REFUND' AND t.snapshot->>'consumer_late_cancel'='MANUAL_REVIEW' AND t.snapshot->>'no_show'='MANUAL_REVIEW' AND jsonb_typeof(t.snapshot->'cancel_cutoff_minutes')='number',false) OR p.status<>'SUCCEEDED' OR t.fulfillment_state<>'NOT_STARTED' OR NEW.proposed_refund_fen<>p.amount_fen-used
 OR NOT ((NEW.basis_code='BEFORE_CUTOFF' AND NEW.created_at<start_time-make_interval(mins=>(t.snapshot->>'cancel_cutoff_minutes')::integer))
 OR (NEW.basis_code='MERCHANT_CANCEL' AND t.cancel_reason='SERVICE_UNAVAILABLE'))))
 THEN RAISE EXCEPTION 'service assessment source'; END IF;RETURN NEW;
END $$;
CREATE TRIGGER service_assessment_source BEFORE INSERT ON service_trade_refund_assessments FOR EACH ROW EXECUTE FUNCTION guard_service_assessment();
CREATE FUNCTION guard_service_refund_decision() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE a service_trade_refund_assessments;t service_trade_orders;start_time timestamptz;BEGIN
 SELECT * INTO STRICT a FROM service_trade_refund_assessments WHERE id=NEW.assessment_id;SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id;
 SELECT starts_at INTO STRICT start_time FROM booking_slots WHERE id=t.slot_id;
 IF a.trade_id<>t.id OR a.terms_sha256<>t.terms_sha256 OR NEW.decided_at<a.created_at OR NEW.decided_at>=a.expires_at
 OR NEW.version<>t.version OR t.version<>a.trade_version+(CASE WHEN NEW.decision='APPROVE' THEN 1 ELSE 0 END)
 OR (NEW.decision='APPROVE' AND (NOT a.eligible_for_approval OR t.fulfillment_state<>'NOT_STARTED'
 OR (a.basis_code='BEFORE_CUTOFF' AND NEW.decided_at>=start_time-make_interval(mins=>(t.snapshot->>'cancel_cutoff_minutes')::integer))
 OR NOT EXISTS(SELECT 1 FROM service_trade_refunds f WHERE f.id=NEW.refund_id AND f.trade_id=t.id AND f.receipt_id=a.receipt_id AND f.amount_fen=a.proposed_refund_fen AND f.source_kind='ADMIN' AND f.business_key='assessment:'||a.id::text)))
 THEN RAISE EXCEPTION 'service refund decision source'; END IF;RETURN NEW;
END $$;
CREATE TRIGGER service_refund_decision_source BEFORE INSERT ON service_trade_refund_decisions FOR EACH ROW EXECUTE FUNCTION guard_service_refund_decision();
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['service_trade_refunds','service_trade_money_events','service_trade_refund_assessments','service_trade_refund_decisions'] LOOP
 EXECUTE format('CREATE TRIGGER no_truncate_service_finance BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 IF t<>'service_trade_refunds' THEN EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);END IF;
 END LOOP;
END $$;
