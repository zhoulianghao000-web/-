-- Paid service fulfillment is independent of legacy free bookings and their credentials.
INSERT INTO permission(code,description) VALUES
 ('service.trade.fulfill','Record scoped paid synthetic service fulfillment'),
 ('service.trade.dispute.read','Read scoped synthetic service disputes'),
 ('service.trade.dispute.review','Resolve synthetic disputes without financial decisions after reverify') ON CONFLICT DO NOTHING;
DO $$ DECLARE c record;BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='service_trade_orders'::regclass AND contype='c'
 AND pg_get_constraintdef(oid) LIKE '%fulfillment_state%' LOOP
 EXECUTE format('ALTER TABLE service_trade_orders DROP CONSTRAINT %I',c.conname);END LOOP;
END $$;
ALTER TABLE service_trade_orders ADD CHECK(fulfillment_state IN ('NOT_STARTED','CHECKED_IN','COMPLETED','NO_SHOW','EXCEPTION')),
 ADD CHECK(fulfillment_state='NOT_STARTED' OR (order_state='CONFIRMED' AND payment_state='SUCCEEDED' AND capacity_state='CONFIRMED'));
CREATE TABLE service_trade_fulfillment_events (
 id uuid PRIMARY KEY,trade_id uuid NOT NULL REFERENCES service_trade_orders(id),version bigint NOT NULL CHECK(version>0),
 status varchar(16) NOT NULL CHECK(status IN ('CHECKED_IN','COMPLETED','NO_SHOW','EXCEPTION')),
 reason_code varchar(32) NOT NULL CHECK(reason_code IN ('','SERVICE_UNAVAILABLE','SAFETY_STOP','CUSTOMER_DISPUTE')),
 actor_id uuid NOT NULL REFERENCES identity_principal(id),occurred_at timestamptz NOT NULL,
 UNIQUE(trade_id,version),CHECK((status='EXCEPTION')=(reason_code<>''))
);
CREATE TABLE service_trade_disputes (
 id uuid PRIMARY KEY,trade_id uuid NOT NULL REFERENCES service_trade_orders(id),version bigint NOT NULL CHECK(version>0),
 reason_code varchar(32) NOT NULL CHECK(reason_code IN ('SERVICE_QUALITY','BOOKING_MISMATCH','SAFETY_CONCERN')),
 evidence_refs jsonb NOT NULL CHECK(jsonb_typeof(evidence_refs)='array' AND jsonb_array_length(evidence_refs) BETWEEN 1 AND 20),
 opened_by uuid NOT NULL REFERENCES identity_principal(id),opened_at timestamptz NOT NULL,UNIQUE(trade_id,version),UNIQUE(id,trade_id)
);
CREATE TABLE service_trade_dispute_decisions (
 id uuid PRIMARY KEY,dispute_id uuid NOT NULL UNIQUE,trade_id uuid NOT NULL REFERENCES service_trade_orders(id),version bigint NOT NULL CHECK(version>0),
 decision varchar(40) NOT NULL CHECK(decision='RESOLVE_NO_FINANCIAL_CHANGE'),reason_code varchar(32) NOT NULL CHECK(reason_code='TEST_SCENARIO_REVIEWED'),
 evidence_refs jsonb NOT NULL CHECK(jsonb_typeof(evidence_refs)='array' AND jsonb_array_length(evidence_refs) BETWEEN 1 AND 20),
 decided_by uuid NOT NULL REFERENCES identity_principal(id),decided_at timestamptz NOT NULL,
 FOREIGN KEY(dispute_id,trade_id) REFERENCES service_trade_disputes(id,trade_id),UNIQUE(trade_id,version)
);
CREATE INDEX service_dispute_trade ON service_trade_disputes(trade_id,id);
CREATE FUNCTION service_trade_open_dispute(tid uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM service_trade_disputes d WHERE d.trade_id=tid AND NOT EXISTS(SELECT 1 FROM service_trade_dispute_decisions x WHERE x.dispute_id=d.id))
$$;
CREATE FUNCTION guard_paid_service_fulfillment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t service_trade_orders;s booking_slots;p payments;BEGIN
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id;
 SELECT * INTO STRICT s FROM booking_slots WHERE id=t.slot_id FOR UPDATE;
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id FOR UPDATE;
 SELECT * INTO STRICT p FROM payments WHERE service_trade_id=t.id FOR UPDATE;
 IF t.order_state<>'CONFIRMED' OR t.capacity_state<>'CONFIRMED' OR t.payment_state<>'SUCCEEDED' OR p.status<>'SUCCEEDED'
 OR t.receipt_id IS DISTINCT FROM p.successful_receipt_id OR NEW.version<>t.version+1
 OR service_trade_open_dispute(t.id)
 OR EXISTS(SELECT 1 FROM service_trade_refunds WHERE trade_id=t.id AND source_kind<>'COMPENSATION')
 OR EXISTS(SELECT 1 FROM payment_attempts WHERE payment_id=p.id AND status IN ('CREATED','CHANNEL_PENDING','UNKNOWN'))
 OR EXISTS(SELECT 1 FROM payment_cases WHERE payment_id=p.id AND status<>'REFUNDED')
 OR NOT((t.fulfillment_state='NOT_STARTED' AND NEW.status IN ('CHECKED_IN','NO_SHOW','EXCEPTION'))
 OR (t.fulfillment_state='CHECKED_IN' AND NEW.status IN ('COMPLETED','EXCEPTION')))
 OR (NEW.status='CHECKED_IN' AND (NEW.occurred_at<s.starts_at-interval '30 minutes' OR NEW.occurred_at>=s.ends_at))
 OR (NEW.status='COMPLETED' AND NEW.occurred_at<s.starts_at)
 OR (NEW.status='NO_SHOW' AND NEW.occurred_at<s.ends_at)
 OR (NEW.status='EXCEPTION' AND NEW.occurred_at<s.starts_at-interval '30 minutes')
 OR EXISTS(SELECT 1 FROM service_trade_fulfillment_events WHERE trade_id=t.id AND occurred_at>NEW.occurred_at)
 THEN RAISE EXCEPTION 'invalid paid service fulfillment';END IF;RETURN NEW;
END $$;
CREATE TRIGGER paid_service_fulfillment_source BEFORE INSERT ON service_trade_fulfillment_events FOR EACH ROW EXECUTE FUNCTION guard_paid_service_fulfillment();
CREATE FUNCTION guard_service_dispute_fact() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t service_trade_orders;d service_trade_disputes;BEGIN
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id;
 PERFORM id FROM booking_slots WHERE id=t.slot_id FOR UPDATE;
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id FOR UPDATE;
 PERFORM id FROM payments WHERE service_trade_id=t.id FOR UPDATE;
 IF t.payment_state<>'SUCCEEDED' OR NEW.version<>t.version+1 THEN RAISE EXCEPTION 'invalid service dispute source';END IF;
 IF TG_TABLE_NAME='service_trade_disputes' THEN
  IF service_trade_open_dispute(t.id) THEN RAISE EXCEPTION 'service dispute already open';END IF;
 ELSE
  SELECT * INTO STRICT d FROM service_trade_disputes WHERE id=NEW.dispute_id AND trade_id=t.id;
  IF NEW.decided_at<d.opened_at THEN RAISE EXCEPTION 'service dispute decision time';END IF;
 END IF;RETURN NEW;
END $$;
CREATE TRIGGER service_dispute_source BEFORE INSERT ON service_trade_disputes FOR EACH ROW EXECUTE FUNCTION guard_service_dispute_fact();
CREATE TRIGGER service_dispute_decision_source BEFORE INSERT ON service_trade_dispute_decisions FOR EACH ROW EXECUTE FUNCTION guard_service_dispute_fact();
CREATE OR REPLACE FUNCTION protect_service_trade_hold() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF TG_OP='DELETE' OR NEW.version<>OLD.version+1
 OR (to_jsonb(NEW)-ARRAY['order_state','payment_state','capacity_state','fulfillment_state','version','closed_at','receipt_id','confirmed_at','cancel_reason']) IS DISTINCT FROM
 (to_jsonb(OLD)-ARRAY['order_state','payment_state','capacity_state','fulfillment_state','version','closed_at','receipt_id','confirmed_at','cancel_reason'])
 OR NOT((OLD.order_state='AWAITING_PAYMENT' AND NEW.order_state IN ('CONFIRMED','CANCELLED','EXPIRED') AND NEW.fulfillment_state=OLD.fulfillment_state)
 OR (OLD.payment_state='SUCCEEDED' AND NEW.payment_state='SUCCEEDED' AND NEW.receipt_id=OLD.receipt_id AND NEW.confirmed_at=OLD.confirmed_at
 AND ((OLD.order_state='CONFIRMED' AND NEW.order_state IN ('CONFIRMED','CANCELLED'))
 OR (OLD.order_state='CANCELLED' AND NEW.order_state='CANCELLED' AND NEW.closed_at=OLD.closed_at AND NEW.cancel_reason=OLD.cancel_reason))))
 OR (NEW.fulfillment_state<>OLD.fulfillment_state AND NOT EXISTS(SELECT 1 FROM service_trade_fulfillment_events WHERE trade_id=NEW.id AND version=NEW.version AND status=NEW.fulfillment_state))
 OR (OLD.order_state='CONFIRMED' AND NEW.order_state='CANCELLED' AND (OLD.fulfillment_state<>'NOT_STARTED' OR service_trade_open_dispute(OLD.id)))
 THEN RAISE EXCEPTION 'immutable service trade state';END IF;RETURN NEW;
END $$;
CREATE FUNCTION verify_service_operational_fact() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t service_trade_orders;BEGIN
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id;
 IF t.version<NEW.version OR (TG_TABLE_NAME='service_trade_fulfillment_events' AND t.fulfillment_state IS DISTINCT FROM
 (SELECT status FROM service_trade_fulfillment_events WHERE trade_id=t.id ORDER BY version DESC LIMIT 1))
 THEN RAISE EXCEPTION 'service operational fact commit';END IF;RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER service_fulfillment_commit AFTER INSERT ON service_trade_fulfillment_events DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_service_operational_fact();
CREATE CONSTRAINT TRIGGER service_dispute_commit AFTER INSERT ON service_trade_disputes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_service_operational_fact();
CREATE CONSTRAINT TRIGGER service_dispute_decision_commit AFTER INSERT ON service_trade_dispute_decisions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_service_operational_fact();
DO $$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['service_trade_fulfillment_events','service_trade_disputes','service_trade_dispute_decisions'] LOOP
 EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 EXECUTE format('CREATE TRIGGER no_truncate_service_operations BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 END LOOP;
END $$;
