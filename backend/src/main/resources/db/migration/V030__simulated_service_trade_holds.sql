-- V3.1.3-B1: explicit synthetic terms, quotes and unpaid holds; no financial authority.
INSERT INTO permission(code,description) VALUES
 ('service.terms.write','Draft synthetic service trade terms'),
 ('service.terms.review','Review synthetic service trade terms'),
 ('service.trade.read','Read store scoped synthetic service trades') ON CONFLICT(code) DO NOTHING;
CREATE TABLE service_trade_terms (
 id uuid PRIMARY KEY, service_id uuid NOT NULL, store_id uuid NOT NULL,
 snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object'),
 terms_sha256 varchar(64) NOT NULL CHECK(terms_sha256 ~ '^[0-9a-f]{64}$'),
 policy_snapshot_sha256 varchar(64) NOT NULL CHECK(policy_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 state varchar(16) NOT NULL DEFAULT 'DRAFT' CHECK(state IN ('DRAFT','REVIEWED','REJECTED','RETIRED')),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
 created_by uuid NOT NULL REFERENCES identity_principal(id), created_at timestamptz NOT NULL,
 reviewed_by uuid REFERENCES identity_principal(id), reviewed_at timestamptz,
 FOREIGN KEY(service_id,store_id) REFERENCES booking_services(id,store_id), UNIQUE(id,service_id,store_id),
 CHECK((state='DRAFT')=(reviewed_by IS NULL AND reviewed_at IS NULL))
);
CREATE UNIQUE INDEX service_terms_current ON service_trade_terms(service_id) WHERE state='REVIEWED';
CREATE INDEX service_terms_store ON service_trade_terms(store_id,id);
CREATE TABLE service_trade_quotes (
 id uuid PRIMARY KEY, terms_id uuid NOT NULL, slot_id uuid NOT NULL, service_id uuid NOT NULL, store_id uuid NOT NULL,
 user_id uuid NOT NULL REFERENCES app_user(id), terms_version bigint NOT NULL, service_version bigint NOT NULL,
 terms_sha256 varchar(64) NOT NULL, policy_snapshot_sha256 varchar(64) NOT NULL,
 payable_fen integer NOT NULL CHECK(payable_fen BETWEEN 1 AND 1000000000),
 created_at timestamptz NOT NULL, expires_at timestamptz NOT NULL CHECK(expires_at>created_at),
 FOREIGN KEY(terms_id,service_id,store_id) REFERENCES service_trade_terms(id,service_id,store_id),
 FOREIGN KEY(slot_id,service_id) REFERENCES booking_slots(id,service_id)
);
CREATE TABLE service_trade_orders (
 id uuid PRIMARY KEY, quote_id uuid NOT NULL UNIQUE REFERENCES service_trade_quotes(id),
 slot_id uuid NOT NULL, service_id uuid NOT NULL, store_id uuid NOT NULL, terms_id uuid NOT NULL,
 user_id uuid NOT NULL REFERENCES app_user(id), snapshot jsonb NOT NULL,
 terms_sha256 varchar(64) NOT NULL, policy_snapshot_sha256 varchar(64) NOT NULL,
 payable_fen integer NOT NULL CHECK(payable_fen BETWEEN 1 AND 1000000000),
 order_state varchar(24) NOT NULL DEFAULT 'AWAITING_PAYMENT' CHECK(order_state IN ('AWAITING_PAYMENT','CANCELLED','EXPIRED')),
 payment_state varchar(16) NOT NULL DEFAULT 'PENDING' CHECK(payment_state IN ('PENDING','CLOSED')),
 capacity_state varchar(16) NOT NULL DEFAULT 'HELD' CHECK(capacity_state IN ('HELD','RELEASED')),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0), created_at timestamptz NOT NULL,
 hold_expires_at timestamptz NOT NULL CHECK(hold_expires_at>created_at), closed_at timestamptz,
 FOREIGN KEY(slot_id,service_id) REFERENCES booking_slots(id,service_id),
 FOREIGN KEY(terms_id,service_id,store_id) REFERENCES service_trade_terms(id,service_id,store_id),
 CHECK((order_state='AWAITING_PAYMENT' AND payment_state='PENDING' AND capacity_state='HELD' AND closed_at IS NULL)
 OR (order_state IN ('CANCELLED','EXPIRED') AND payment_state='CLOSED' AND capacity_state='RELEASED' AND closed_at IS NOT NULL))
);
CREATE UNIQUE INDEX service_trade_one_hold ON service_trade_orders(user_id,slot_id) WHERE capacity_state='HELD';
CREATE INDEX service_trade_capacity ON service_trade_orders(slot_id) WHERE capacity_state='HELD';
CREATE INDEX service_trade_expiry ON service_trade_orders(hold_expires_at,id) WHERE capacity_state='HELD';
CREATE INDEX service_trade_user ON service_trade_orders(user_id,id);
CREATE INDEX service_trade_store ON service_trade_orders(store_id,id);
CREATE FUNCTION protect_service_terms() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' OR NEW.version<>OLD.version+1
 OR NOT ((OLD.state='DRAFT' AND NEW.state IN ('REVIEWED','REJECTED')) OR (OLD.state='REVIEWED' AND NEW.state='RETIRED'))
 OR (to_jsonb(NEW)-ARRAY['state','version','reviewed_by','reviewed_at']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['state','version','reviewed_by','reviewed_at'])
 THEN RAISE EXCEPTION 'immutable synthetic terms'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_service_terms BEFORE UPDATE OR DELETE ON service_trade_terms FOR EACH ROW EXECUTE FUNCTION protect_service_terms();
CREATE TRIGGER no_truncate_service_terms BEFORE TRUNCATE ON service_trade_terms FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER immutable_service_quote BEFORE UPDATE OR DELETE ON service_trade_quotes FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER no_truncate_service_quote BEFORE TRUNCATE ON service_trade_quotes FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE FUNCTION protect_service_trade_hold() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' OR OLD.order_state<>'AWAITING_PAYMENT' OR NEW.order_state NOT IN ('CANCELLED','EXPIRED')
 OR NEW.version<>OLD.version+1
 OR (to_jsonb(NEW)-ARRAY['order_state','payment_state','capacity_state','version','closed_at']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['order_state','payment_state','capacity_state','version','closed_at'])
 THEN RAISE EXCEPTION 'immutable unpaid service trade'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_service_trade BEFORE UPDATE OR DELETE ON service_trade_orders FOR EACH ROW EXECUTE FUNCTION protect_service_trade_hold();
CREATE TRIGGER no_truncate_service_trade BEFORE TRUNCATE ON service_trade_orders FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
-- Shared lock and capacity fence for old free bookings and new unpaid holds, including SQL inserts.
CREATE FUNCTION guard_shared_service_capacity() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE seats integer; occupied bigint;
BEGIN
 SELECT capacity INTO STRICT seats FROM booking_slots WHERE id=NEW.slot_id FOR UPDATE;
 SELECT (SELECT count(*) FROM service_bookings WHERE slot_id=NEW.slot_id AND status='BOOKED')+
        (SELECT count(*) FROM service_trade_orders WHERE slot_id=NEW.slot_id AND capacity_state='HELD') INTO occupied;
 IF occupied>=seats THEN RAISE EXCEPTION 'service slot capacity exhausted'; END IF;
 IF EXISTS(SELECT 1 FROM service_bookings WHERE slot_id=NEW.slot_id AND user_id=NEW.user_id AND status='BOOKED')
 OR EXISTS(SELECT 1 FROM service_trade_orders WHERE slot_id=NEW.slot_id AND user_id=NEW.user_id AND capacity_state='HELD')
 THEN RAISE EXCEPTION 'duplicate service slot owner'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER shared_capacity_booking BEFORE INSERT ON service_bookings FOR EACH ROW EXECUTE FUNCTION guard_shared_service_capacity();
CREATE TRIGGER shared_capacity_trade BEFORE INSERT ON service_trade_orders FOR EACH ROW EXECUTE FUNCTION guard_shared_service_capacity();
CREATE FUNCTION guard_service_trade_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE q service_trade_quotes; t service_trade_terms; s booking_slots; b booking_services;
BEGIN
 SELECT * INTO STRICT q FROM service_trade_quotes WHERE id=NEW.quote_id;
 SELECT * INTO STRICT t FROM service_trade_terms WHERE id=q.terms_id;
 SELECT * INTO STRICT s FROM booking_slots WHERE id=q.slot_id;
 SELECT * INTO STRICT b FROM booking_services WHERE id=q.service_id;
 IF NEW.order_state<>'AWAITING_PAYMENT' OR NEW.version<>0 OR t.state<>'REVIEWED' OR b.status<>'ACTIVE'
 OR (NEW.slot_id,NEW.service_id,NEW.store_id,NEW.terms_id,NEW.user_id,NEW.terms_sha256,NEW.policy_snapshot_sha256,NEW.payable_fen)
 IS DISTINCT FROM (q.slot_id,q.service_id,q.store_id,q.terms_id,q.user_id,q.terms_sha256,q.policy_snapshot_sha256,q.payable_fen)
 OR NEW.snapshot IS DISTINCT FROM t.snapshot OR q.terms_version<>t.version OR q.service_version<>b.version
 OR NEW.created_at<q.created_at OR NEW.created_at>=q.expires_at
 OR NEW.hold_expires_at>least(s.starts_at,NEW.created_at+interval '10 minutes')
 THEN RAISE EXCEPTION 'invalid synthetic service quote snapshot'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER valid_service_trade_snapshot BEFORE INSERT ON service_trade_orders FOR EACH ROW EXECUTE FUNCTION guard_service_trade_snapshot();
