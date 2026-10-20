-- Every balance source remains in the service domain. No goods policy fallback.
INSERT INTO permission(code,description) VALUES
 ('service.trade.ledger.read','Read scoped synthetic service ledger'),
 ('service.trade.settle','Preview and execute synthetic service settlements after reverify') ON CONFLICT DO NOTHING;
CREATE TABLE service_trade_allocations (
 trade_id uuid PRIMARY KEY REFERENCES service_trade_orders(id),merchant_id uuid NOT NULL REFERENCES merchant(id),
 receipt_id uuid NOT NULL UNIQUE REFERENCES payment_receipts(id),collection_event_id uuid NOT NULL UNIQUE REFERENCES service_trade_money_events(id),
 policy_snapshot_sha256 varchar(64) NOT NULL,paid_fen bigint NOT NULL CHECK(paid_fen BETWEEN 1 AND 1000000000),
 commission_basis_points integer NOT NULL CHECK(commission_basis_points BETWEEN 0 AND 10000),
 commission_fen bigint NOT NULL CHECK(commission_fen BETWEEN 0 AND paid_fen),
 settlement_buffer_minutes integer NOT NULL CHECK(settlement_buffer_minutes BETWEEN 0 AND 129600),created_at timestamptz NOT NULL
);
CREATE TABLE service_trade_settlement_previews (
 id uuid PRIMARY KEY,merchant_id uuid NOT NULL REFERENCES merchant(id),snapshot jsonb NOT NULL,
 net_fen bigint NOT NULL CHECK(net_fen BETWEEN 0 AND 1000000000),ledger_sha256 varchar(64) NOT NULL,
 eligible boolean NOT NULL,blocked_reasons jsonb NOT NULL CHECK(jsonb_typeof(blocked_reasons)='array'),
 entry_count integer NOT NULL CHECK(entry_count BETWEEN 0 AND 10000),created_by uuid NOT NULL REFERENCES identity_principal(id),
 created_at timestamptz NOT NULL,expires_at timestamptz NOT NULL CHECK(expires_at=created_at+interval '5 minutes')
);
CREATE TABLE service_trade_settlements (
 id uuid PRIMARY KEY,preview_id uuid NOT NULL UNIQUE REFERENCES service_trade_settlement_previews(id),
 merchant_id uuid NOT NULL REFERENCES merchant(id),net_fen bigint NOT NULL CHECK(net_fen BETWEEN 1 AND 1000000000),
 state varchar(16) NOT NULL CHECK(state='SETTLED'),version bigint NOT NULL DEFAULT 0 CHECK(version=0),
 channel_reference varchar(100) NOT NULL UNIQUE CHECK(channel_reference LIKE 'SIM-SERVICE-%'),
 ledger_sha256 varchar(64) NOT NULL,created_by uuid NOT NULL REFERENCES identity_principal(id),settled_at timestamptz NOT NULL
);
CREATE TABLE service_trade_settlement_items (
 settlement_id uuid NOT NULL REFERENCES service_trade_settlements(id),trade_id uuid NOT NULL REFERENCES service_trade_allocations(trade_id),
 net_fen bigint NOT NULL CHECK(net_fen<>0),PRIMARY KEY(settlement_id,trade_id)
);
CREATE TABLE service_trade_ledger_entries (
 id uuid PRIMARY KEY,trade_id uuid NOT NULL REFERENCES service_trade_allocations(trade_id),merchant_id uuid NOT NULL REFERENCES merchant(id),
 source_event_id uuid REFERENCES service_trade_money_events(id),settlement_id uuid REFERENCES service_trade_settlements(id),
 entry_type varchar(40) NOT NULL CHECK(entry_type IN ('SERVICE_COLLECTION','SERVICE_COMMISSION','SERVICE_REFUND','SERVICE_COMMISSION_REVERSAL','SERVICE_SETTLEMENT','SERVICE_SETTLED_REFUND_ADJUSTMENT')),
 direction varchar(6) NOT NULL CHECK(direction IN ('CREDIT','DEBIT')),amount_fen bigint NOT NULL CHECK(amount_fen BETWEEN 1 AND 1000000000),
 affects_balance boolean NOT NULL,occurred_at timestamptz NOT NULL,
 CHECK((entry_type='SERVICE_SETTLEMENT')=(settlement_id IS NOT NULL)),
 CHECK((entry_type='SERVICE_SETTLEMENT')=(source_event_id IS NULL)),
 CHECK(affects_balance=(entry_type<>'SERVICE_SETTLED_REFUND_ADJUSTMENT')),
 CHECK(entry_type='SERVICE_SETTLEMENT' OR (direction='CREDIT')=(entry_type IN ('SERVICE_COLLECTION','SERVICE_COMMISSION_REVERSAL')))
);
CREATE UNIQUE INDEX service_ledger_money_source ON service_trade_ledger_entries(source_event_id,entry_type) WHERE source_event_id IS NOT NULL;
CREATE UNIQUE INDEX service_ledger_settlement_source ON service_trade_ledger_entries(settlement_id,trade_id) WHERE settlement_id IS NOT NULL;
CREATE INDEX service_ledger_merchant ON service_trade_ledger_entries(merchant_id,trade_id,id);
-- Read-only union: each source has exactly one owning domain and original entry id.
CREATE VIEW merchant_finance_balance_sources AS
 SELECT 'GOODS'::text AS business_type,id,merchant_id,direction,amount_fen FROM merchant_ledger_entries WHERE affects_balance
 UNION ALL SELECT 'SERVICE_TRADE'::text,id,merchant_id,direction,amount_fen FROM service_trade_ledger_entries WHERE affects_balance;
CREATE FUNCTION guard_service_allocation() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t service_trade_orders;e service_trade_money_events;BEGIN
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id;
 SELECT * INTO STRICT e FROM service_trade_money_events WHERE id=NEW.collection_event_id;
 IF t.payment_state<>'SUCCEEDED' OR t.receipt_id<>NEW.receipt_id OR e.entry_type<>'SERVICE_COLLECTION' OR e.trade_id<>t.id OR e.receipt_id<>NEW.receipt_id
 OR NEW.paid_fen<>e.amount_fen OR NEW.policy_snapshot_sha256<>t.policy_snapshot_sha256
 OR NOT EXISTS(SELECT 1 FROM merchant_store WHERE id=t.store_id AND merchant_id=NEW.merchant_id)
 OR NOT EXISTS(SELECT 1 FROM service_trade_terms WHERE id=t.terms_id AND snapshot=t.snapshot AND policy_snapshot_sha256=t.policy_snapshot_sha256)
 OR NEW.commission_basis_points IS DISTINCT FROM (t.snapshot->>'commission_basis_points')::integer
 OR NEW.settlement_buffer_minutes IS DISTINCT FROM (t.snapshot->>'settlement_buffer_minutes')::integer
 OR NEW.commission_fen<>round(NEW.paid_fen::numeric*NEW.commission_basis_points/10000)::bigint
 THEN RAISE EXCEPTION 'service allocation source';END IF;RETURN NEW;
END $$;
CREATE TRIGGER service_allocation_source BEFORE INSERT ON service_trade_allocations FOR EACH ROW EXECUTE FUNCTION guard_service_allocation();
CREATE FUNCTION service_trade_balance(tid uuid) RETURNS bigint LANGUAGE sql STABLE AS $$
 SELECT coalesce(sum(CASE direction WHEN 'CREDIT' THEN amount_fen ELSE -amount_fen END),0)::bigint FROM service_trade_ledger_entries WHERE trade_id=tid AND affects_balance
$$;
CREATE FUNCTION guard_service_ledger_source() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE a service_trade_allocations;e service_trade_money_events;expected bigint;refunded bigint;prior bigint;item service_trade_settlement_items;BEGIN
 SELECT * INTO STRICT a FROM service_trade_allocations WHERE trade_id=NEW.trade_id;
 IF NEW.merchant_id<>a.merchant_id THEN RAISE EXCEPTION 'service ledger merchant';END IF;
 IF NEW.entry_type='SERVICE_SETTLEMENT' THEN
  SELECT * INTO STRICT item FROM service_trade_settlement_items WHERE settlement_id=NEW.settlement_id AND trade_id=NEW.trade_id;
  IF abs(item.net_fen)<>NEW.amount_fen OR (item.net_fen>0)<>(NEW.direction='DEBIT')
  OR service_trade_balance(NEW.trade_id)<>item.net_fen THEN RAISE EXCEPTION 'service settlement debit source';END IF;
 ELSE
  SELECT * INTO STRICT e FROM service_trade_money_events WHERE id=NEW.source_event_id AND trade_id=NEW.trade_id;
  IF NEW.entry_type IN ('SERVICE_COLLECTION','SERVICE_COMMISSION') THEN
   IF e.entry_type<>'SERVICE_COLLECTION' THEN RAISE EXCEPTION 'service collection source';END IF;
   expected:=CASE NEW.entry_type WHEN 'SERVICE_COLLECTION' THEN a.paid_fen ELSE a.commission_fen END;
  ELSE
   IF e.entry_type<>'SERVICE_REFUND' THEN RAISE EXCEPTION 'service refund source';END IF;
   IF NEW.entry_type='SERVICE_COMMISSION_REVERSAL' THEN
    -- Prior ledger debits are the already projected prefix; include this event once.
    SELECT coalesce(sum(amount_fen),0) INTO refunded FROM service_trade_ledger_entries WHERE trade_id=NEW.trade_id AND entry_type='SERVICE_REFUND';
    SELECT coalesce(sum(amount_fen),0) INTO prior FROM service_trade_ledger_entries WHERE trade_id=NEW.trade_id AND entry_type='SERVICE_COMMISSION_REVERSAL';
    expected:=round(a.commission_fen::numeric*least(a.paid_fen,refunded)/a.paid_fen)::bigint-prior;
   ELSE expected:=e.amount_fen;END IF;
   IF NEW.entry_type='SERVICE_SETTLED_REFUND_ADJUSTMENT' AND NOT EXISTS(SELECT 1 FROM service_trade_settlement_items WHERE trade_id=NEW.trade_id)
   THEN RAISE EXCEPTION 'service settled refund source';END IF;
  END IF;
  IF NEW.amount_fen<>expected THEN RAISE EXCEPTION 'service ledger amount';END IF;
 END IF;RETURN NEW;
END $$;
CREATE TRIGGER service_ledger_source BEFORE INSERT ON service_trade_ledger_entries FOR EACH ROW EXECUTE FUNCTION guard_service_ledger_source();
CREATE FUNCTION project_service_money_event(eid uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE e service_trade_money_events;t service_trade_orders;a service_trade_allocations;m uuid;refunded bigint;reversed bigint;delta bigint;BEGIN
 SELECT * INTO STRICT e FROM service_trade_money_events WHERE id=eid;
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=e.trade_id;
 IF e.entry_type='SERVICE_COLLECTION' THEN
  SELECT merchant_id INTO STRICT m FROM merchant_store WHERE id=t.store_id;
  INSERT INTO service_trade_allocations VALUES(t.id,m,e.receipt_id,e.id,t.policy_snapshot_sha256,e.amount_fen,
   (t.snapshot->>'commission_basis_points')::integer,round(e.amount_fen::numeric*(t.snapshot->>'commission_basis_points')::integer/10000)::bigint,
   (t.snapshot->>'settlement_buffer_minutes')::integer,e.occurred_at);
 END IF;
 SELECT * INTO STRICT a FROM service_trade_allocations WHERE trade_id=t.id;
 INSERT INTO service_trade_ledger_entries VALUES(gen_random_uuid(),t.id,a.merchant_id,e.id,NULL,e.entry_type,
  CASE e.entry_type WHEN 'SERVICE_COLLECTION' THEN 'CREDIT' ELSE 'DEBIT' END,e.amount_fen,true,e.occurred_at);
 IF e.entry_type='SERVICE_COLLECTION' THEN
  IF a.commission_fen>0 THEN INSERT INTO service_trade_ledger_entries VALUES(gen_random_uuid(),t.id,a.merchant_id,e.id,NULL,'SERVICE_COMMISSION','DEBIT',a.commission_fen,true,e.occurred_at);END IF;
 ELSE
  SELECT coalesce(sum(amount_fen),0) INTO refunded FROM service_trade_ledger_entries WHERE trade_id=t.id AND entry_type='SERVICE_REFUND';
  SELECT coalesce(sum(amount_fen),0) INTO reversed FROM service_trade_ledger_entries WHERE trade_id=t.id AND entry_type='SERVICE_COMMISSION_REVERSAL';
  delta:=round(a.commission_fen::numeric*least(a.paid_fen,refunded)/a.paid_fen)::bigint-reversed;
  IF delta>0 THEN INSERT INTO service_trade_ledger_entries VALUES(gen_random_uuid(),t.id,a.merchant_id,e.id,NULL,'SERVICE_COMMISSION_REVERSAL','CREDIT',delta,true,e.occurred_at);END IF;
  -- The debit and reversal above affect balance. This immutable marker carries provenance only.
  IF EXISTS(SELECT 1 FROM service_trade_settlement_items WHERE trade_id=t.id) THEN
   INSERT INTO service_trade_ledger_entries VALUES(gen_random_uuid(),t.id,a.merchant_id,e.id,NULL,'SERVICE_SETTLED_REFUND_ADJUSTMENT','DEBIT',e.amount_fen,false,e.occurred_at);
  END IF;
 END IF;
END $$;
CREATE FUNCTION project_service_money_event_trigger() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN PERFORM project_service_money_event(NEW.id);RETURN NEW;END $$;
-- Upgrade only existing successful collection/refund facts, never pending payment intents.
DO $$ DECLARE e record;BEGIN FOR e IN SELECT id FROM service_trade_money_events ORDER BY CASE entry_type WHEN 'SERVICE_COLLECTION' THEN 0 ELSE 1 END,occurred_at,id LOOP PERFORM project_service_money_event(e.id);END LOOP;END $$;
CREATE TRIGGER service_financial_projection AFTER INSERT ON service_trade_money_events FOR EACH ROW EXECUTE FUNCTION project_service_money_event_trigger();
CREATE FUNCTION guard_service_settlement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p service_trade_settlement_previews;BEGIN
 SELECT * INTO STRICT p FROM service_trade_settlement_previews WHERE id=NEW.preview_id;
 IF NOT p.eligible OR p.merchant_id<>NEW.merchant_id OR p.net_fen<>NEW.net_fen OR p.ledger_sha256<>NEW.ledger_sha256
 OR NEW.created_by<>p.created_by OR NEW.settled_at>=p.expires_at OR NEW.settled_at<p.created_at
 THEN RAISE EXCEPTION 'service settlement snapshot';END IF;RETURN NEW;
END $$;
CREATE TRIGGER service_settlement_source BEFORE INSERT ON service_trade_settlements FOR EACH ROW EXECUTE FUNCTION guard_service_settlement();
CREATE FUNCTION guard_service_settlement_item() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t service_trade_orders;a service_trade_allocations;s service_trade_settlements;p service_trade_settlement_previews;completed timestamptz;BEGIN
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id;
 PERFORM id FROM booking_slots WHERE id=t.slot_id FOR UPDATE;
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=NEW.trade_id FOR UPDATE;
 PERFORM id FROM payments WHERE service_trade_id=t.id FOR UPDATE;
 SELECT * INTO STRICT a FROM service_trade_allocations WHERE trade_id=t.id;
 SELECT * INTO STRICT s FROM service_trade_settlements WHERE id=NEW.settlement_id;
 SELECT * INTO STRICT p FROM service_trade_settlement_previews WHERE id=s.preview_id;
 IF a.merchant_id<>s.merchant_id OR service_trade_balance(t.id)<>NEW.net_fen
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p.snapshot->'items') i WHERE i->>'trade_id'=t.id::text AND (i->>'net_fen')::bigint=NEW.net_fen)
 OR service_trade_open_dispute(t.id)
 OR EXISTS(SELECT 1 FROM service_trade_refunds WHERE trade_id=t.id AND state<>'SUCCEEDED')
 OR EXISTS(SELECT 1 FROM payment_attempts x JOIN payments y ON y.id=x.payment_id WHERE y.service_trade_id=t.id AND x.status IN ('CREATED','CHANNEL_PENDING','UNKNOWN'))
 OR EXISTS(SELECT 1 FROM payment_cases x JOIN payments y ON y.id=x.payment_id WHERE y.service_trade_id=t.id AND x.status<>'REFUNDED')
 THEN RAISE EXCEPTION 'service settlement item source';END IF;
 IF NEW.net_fen>0 THEN
  SELECT max(occurred_at) INTO completed FROM service_trade_fulfillment_events WHERE trade_id=t.id AND status='COMPLETED';
  IF t.order_state<>'CONFIRMED' OR t.fulfillment_state<>'COMPLETED' OR completed IS NULL
  OR completed+make_interval(mins=>a.settlement_buffer_minutes)>s.settled_at
  THEN RAISE EXCEPTION 'service settlement fulfillment';END IF;
 END IF;RETURN NEW;
END $$;
CREATE TRIGGER service_settlement_item_source BEFORE INSERT ON service_trade_settlement_items FOR EACH ROW EXECUTE FUNCTION guard_service_settlement_item();
CREATE FUNCTION verify_service_settlement_commit() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE sid uuid;s service_trade_settlements;BEGIN
 sid:=(to_jsonb(NEW)->>(CASE WHEN TG_TABLE_NAME='service_trade_settlements' THEN 'id' ELSE 'settlement_id' END))::uuid;
 SELECT * INTO STRICT s FROM service_trade_settlements WHERE id=sid;
 IF s.net_fen<>(SELECT coalesce(sum(net_fen),0) FROM service_trade_settlement_items WHERE settlement_id=s.id)
 OR EXISTS(SELECT 1 FROM service_trade_settlement_items i WHERE i.settlement_id=s.id AND NOT EXISTS(SELECT 1 FROM service_trade_ledger_entries e WHERE e.settlement_id=s.id AND e.trade_id=i.trade_id AND e.amount_fen=abs(i.net_fen) AND (e.direction='DEBIT')=(i.net_fen>0)))
 THEN RAISE EXCEPTION 'service settlement balance commit';END IF;RETURN NULL;
END $$;
CREATE FUNCTION service_trade_settlement_state(tid uuid,at_time timestamptz) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE t service_trade_orders;a service_trade_allocations;completed timestamptz;balance bigint;BEGIN
 SELECT * INTO STRICT t FROM service_trade_orders WHERE id=tid;
 SELECT * INTO a FROM service_trade_allocations WHERE trade_id=tid;
 IF a.trade_id IS NULL THEN RETURN 'NOT_PAYABLE';END IF;
 IF service_trade_open_dispute(tid)
 OR EXISTS(SELECT 1 FROM service_trade_refunds WHERE trade_id=tid AND state<>'SUCCEEDED')
 OR EXISTS(SELECT 1 FROM payment_attempts x JOIN payments p ON p.id=x.payment_id WHERE p.service_trade_id=tid AND x.status IN ('CREATED','CHANNEL_PENDING','UNKNOWN'))
 OR EXISTS(SELECT 1 FROM payment_cases x JOIN payments p ON p.id=x.payment_id WHERE p.service_trade_id=tid AND x.status<>'REFUNDED') THEN RETURN 'FROZEN';END IF;
 balance:=service_trade_balance(tid);
 IF EXISTS(SELECT 1 FROM service_trade_settlement_items WHERE trade_id=tid) THEN
  IF balance<>0 THEN RETURN 'ADJUSTED';ELSE RETURN 'SETTLED';END IF;
 END IF;
 IF balance<=0 OR t.order_state<>'CONFIRMED' THEN RETURN 'NOT_PAYABLE';END IF;
 IF t.fulfillment_state IN ('NO_SHOW','EXCEPTION') THEN RETURN 'FROZEN';END IF;
 IF t.fulfillment_state<>'COMPLETED' THEN RETURN 'WAITING_COMPLETION';END IF;
 SELECT max(occurred_at) INTO completed FROM service_trade_fulfillment_events WHERE trade_id=tid AND status='COMPLETED';
 IF completed IS NULL THEN RETURN 'FROZEN';END IF;
 IF at_time<completed+make_interval(mins=>a.settlement_buffer_minutes) THEN RETURN 'BUFFERING';END IF;
 RETURN 'ELIGIBLE';
END $$;
CREATE CONSTRAINT TRIGGER service_settlement_commit AFTER INSERT ON service_trade_settlements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_service_settlement_commit();
CREATE CONSTRAINT TRIGGER service_settlement_item_commit AFTER INSERT ON service_trade_settlement_items DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_service_settlement_commit();
DO $$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['service_trade_allocations','service_trade_ledger_entries','service_trade_settlement_previews','service_trade_settlements','service_trade_settlement_items'] LOOP
 EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 EXECUTE format('CREATE TRIGGER no_truncate_service_settlement BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 END LOOP;
END $$;
