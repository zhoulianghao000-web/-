-- V3.2-B2. Synthetic GOODS only; no backfill, PII, stock ACK or financial mutation.
CREATE TABLE integration_order_deliveries (
 id uuid PRIMARY KEY, connection_id uuid NOT NULL REFERENCES integration_connections(id),
 order_id uuid NOT NULL REFERENCES orders(id), suborder_id uuid NOT NULL REFERENCES suborders(id),
 payment_id uuid NOT NULL REFERENCES payments(id), merchant_id uuid NOT NULL REFERENCES merchant(id),
 store_id uuid NOT NULL REFERENCES merchant_store(id), business_key varchar(110) NOT NULL UNIQUE,
 frozen_payload jsonb NOT NULL, payload_sha256 varchar(64) NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
 state varchar(20) NOT NULL DEFAULT 'READY' CHECK(state IN ('READY','PROCESSING','UNKNOWN','ACCEPTED','REJECTED','NEEDS_REVIEW')),
 attempt_count integer NOT NULL DEFAULT 0 CHECK(attempt_count BETWEEN 0 AND 8),
 lease_token uuid, lease_until timestamptz, next_attempt_at timestamptz NOT NULL DEFAULT now(),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0), created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(suborder_id,connection_id), CHECK(business_key='TEST_ONLY_ORDER_'||suborder_id::text||'_'||connection_id::text),
 CHECK((state='PROCESSING' AND lease_token IS NOT NULL AND lease_until IS NOT NULL) OR
       (state<>'PROCESSING' AND lease_token IS NULL AND lease_until IS NULL))
);
CREATE TABLE integration_delivery_attempts (
 id uuid PRIMARY KEY, delivery_id uuid NOT NULL REFERENCES integration_order_deliveries(id),
 attempt_no integer NOT NULL CHECK(attempt_no BETWEEN 1 AND 8), lease_token uuid NOT NULL UNIQUE,
 action varchar(12) NOT NULL CHECK(action IN ('REQUERY','RETRY')), claimed_at timestamptz NOT NULL,
 lease_until timestamptz NOT NULL, UNIQUE(delivery_id,attempt_no), CHECK(lease_until=claimed_at+interval '60 seconds')
);
CREATE TABLE integration_delivery_receipts (
 id uuid PRIMARY KEY, attempt_id uuid NOT NULL UNIQUE REFERENCES integration_delivery_attempts(id),
 delivery_id uuid NOT NULL REFERENCES integration_order_deliveries(id),
 result varchar(20) NOT NULL CHECK(result IN ('ACCEPTED','REJECTED','UNKNOWN','NOT_CREATED','INVALID')),
 evidence_sha256 varchar(64) NOT NULL CHECK(evidence_sha256 ~ '^[0-9a-f]{64}$'),
 matched boolean NOT NULL, no_external_order boolean NOT NULL,
 provider_reference varchar(110), received_at timestamptz NOT NULL,
 CHECK(provider_reference IS NULL OR provider_reference ~ '^TEST_ONLY_[A-Za-z0-9_.:-]{1,100}$'),
 CHECK(result<>'REJECTED' OR matched AND no_external_order), CHECK(result<>'ACCEPTED' OR matched AND NOT no_external_order)
);
-- The synthetic channel has its own durable idempotency store. It is NOT a business receipt.
-- Separating it from business transactions permits real response-loss/restart recovery tests.
CREATE TABLE integration_delivery_fixture_orders (
 business_key varchar(110) PRIMARY KEY, connection_id uuid NOT NULL REFERENCES integration_connections(id),
 merchant_id uuid NOT NULL REFERENCES merchant(id), payload_sha256 varchar(64) NOT NULL,
 result varchar(12) NOT NULL CHECK(result IN ('ACCEPTED','REJECTED')),
 provider_reference varchar(110) NOT NULL UNIQUE, no_external_order boolean NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(business_key ~ '^TEST_ONLY_ORDER_'), CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
 CHECK(provider_reference ~ '^TEST_ONLY_[A-Za-z0-9_.:-]{1,100}$'),
 CHECK(no_external_order=(result='REJECTED'))
);
CREATE INDEX integration_delivery_due ON integration_order_deliveries(next_attempt_at,id) WHERE state IN ('READY','PROCESSING','UNKNOWN');

-- Canonical, minimal frozen payload. Names, phones and addresses are never copied here.
CREATE FUNCTION integration_order_payload(sid uuid,cid uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('order_id',o.id,'suborder_id',s.id,'connection_id',c.id,'connection_version',c.version,
 'merchant_id',c.merchant_id,'store_id',c.store_id,'payment_id',p.id,'receipt_id',p.successful_receipt_id,
 'address_sha256',encode(digest(a.snapshot::text,'sha256'),'hex'),
 'lines',(SELECT jsonb_agg(jsonb_build_object('order_item_id',i.id,'offer_id',i.offer_id,
   'quantity',i.quantity-i.cancelled_qty,'mapping_id',m.id,'mapping_version',m.version,
   'external_sku',m.external_sku,'external_warehouse',m.external_warehouse,'unit',m.unit) ORDER BY i.id)
   FROM order_items i JOIN integration_mappings m ON m.offer_id=i.offer_id AND m.connection_id=c.id AND m.state='ACTIVE'
   WHERE i.suborder_id=s.id AND i.quantity>i.cancelled_qty))
 FROM suborders s JOIN orders o ON o.id=s.order_id JOIN payments p ON p.order_id=o.id
 JOIN payment_receipts r ON r.id=p.successful_receipt_id AND r.attempt_id=p.successful_attempt_id
 JOIN integration_connections c ON c.id=cid AND c.merchant_id=s.merchant_id
 JOIN merchant merchant ON merchant.id=c.merchant_id AND merchant.status='ACTIVE'
 JOIN order_address_snapshots a ON a.order_id=o.id
 WHERE s.id=sid AND o.status='FULFILLING' AND s.fulfillment_status='PAID_WAITING_FULFILLMENT'
 AND p.status='SUCCEEDED' AND r.amount_fen=p.amount_fen AND r.currency=p.currency
 AND c.state='ACTIVE' AND c.mode='SIMULATED_TEST'
 AND EXISTS(SELECT 1 FROM order_items i JOIN integration_mappings m ON m.offer_id=i.offer_id AND m.connection_id=c.id AND m.state='ACTIVE'
   WHERE i.suborder_id=s.id AND i.store_id=c.store_id AND i.quantity>i.cancelled_qty)
 AND NOT EXISTS(SELECT 1 FROM order_items i JOIN integration_mappings m ON m.offer_id=i.offer_id AND m.connection_id=c.id AND m.state='ACTIVE'
   WHERE i.suborder_id=s.id AND (i.store_id IS DISTINCT FROM c.store_id OR i.merchant_id<>c.merchant_id OR
   coalesce((SELECT sum(x.quantity) FROM inventory_sale_events x WHERE x.payment_id=p.id AND x.offer_id=i.offer_id),0)<i.quantity))
 AND NOT EXISTS(SELECT 1 FROM shipments h WHERE h.suborder_id=s.id)
 AND NOT EXISTS(SELECT 1 FROM aftersales f WHERE f.suborder_id=s.id AND f.status NOT IN ('COMPLETED','CANCELLED'))
 AND NOT EXISTS(SELECT 1 FROM order_cancellations x WHERE x.suborder_id=s.id AND x.status NOT IN ('COMPLETED','REJECTED'))
 AND NOT EXISTS(SELECT 1 FROM refunds f WHERE f.payment_id=p.id AND f.status NOT IN ('SUCCEEDED','CANCELLED'))
$$;

CREATE FUNCTION integration_delivery_insert_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE canonical jsonb; s suborders; c integration_connections; BEGIN
 -- Same linearization as native writes: original order chain BEFORE connection/mapping/stock.
 PERFORM id FROM orders WHERE id=NEW.order_id FOR UPDATE;
 SELECT * INTO STRICT s FROM suborders WHERE id=NEW.suborder_id FOR UPDATE;
 PERFORM id FROM payments WHERE id=NEW.payment_id FOR UPDATE;
 SELECT * INTO STRICT c FROM integration_connections WHERE id=NEW.connection_id FOR UPDATE;
 PERFORM id FROM integration_mappings WHERE connection_id=c.id AND state='ACTIVE' ORDER BY id FOR UPDATE;
 PERFORM f.id FROM offers f JOIN order_items i ON i.offer_id=f.id WHERE i.suborder_id=s.id ORDER BY f.id FOR UPDATE OF f;
 PERFORM b.offer_id FROM inventory_balances b JOIN order_items i ON i.offer_id=b.offer_id WHERE i.suborder_id=s.id ORDER BY b.offer_id FOR UPDATE OF b;
 PERFORM id FROM order_items WHERE suborder_id=s.id ORDER BY id FOR UPDATE;
 canonical:=integration_order_payload(s.id,c.id);
 IF canonical IS NULL OR canonical<>NEW.frozen_payload OR NEW.payload_sha256<>encode(digest(canonical::text,'sha256'),'hex')
 OR s.order_id<>NEW.order_id OR c.merchant_id<>NEW.merchant_id OR c.store_id<>NEW.store_id
 OR canonical->>'payment_id'<>NEW.payment_id::text OR NEW.state<>'READY' OR NEW.attempt_count<>0 OR NEW.version<>0
 THEN RAISE EXCEPTION 'integration declaration requires canonical collected goods'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER integration_delivery_insert BEFORE INSERT ON integration_order_deliveries FOR EACH ROW EXECUTE FUNCTION integration_delivery_insert_guard();

CREATE FUNCTION integration_delivery_update_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (to_jsonb(NEW)-ARRAY['state','attempt_count','lease_token','lease_until','next_attempt_at','version']) <>
    (to_jsonb(OLD)-ARRAY['state','attempt_count','lease_token','lease_until','next_attempt_at','version'])
 OR NEW.version<>OLD.version+1 OR OLD.state IN ('ACCEPTED','REJECTED') OR
 NEW.attempt_count<OLD.attempt_count OR NEW.attempt_count>OLD.attempt_count+1
 THEN RAISE EXCEPTION 'integration immutable delivery identity or terminal result';END IF;
 IF NEW.state='PROCESSING' THEN
   IF NEW.attempt_count<>OLD.attempt_count+1 OR OLD.state='NEEDS_REVIEW' OR
     OLD.lease_until>NEW.lease_until-interval '60 seconds' THEN RAISE EXCEPTION 'integration delivery lease conflict';END IF;
 ELSIF NEW.state IN ('ACCEPTED','REJECTED') THEN
   IF NOT EXISTS(SELECT 1 FROM integration_delivery_receipts r JOIN integration_delivery_attempts a ON a.id=r.attempt_id
     WHERE r.delivery_id=NEW.id AND a.delivery_id=NEW.id AND a.lease_token=OLD.lease_token
     AND r.matched AND r.result=NEW.state AND (NEW.state<>'REJECTED' OR r.no_external_order))
   THEN RAISE EXCEPTION 'integration result needs matching source receipt';END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER integration_delivery_update BEFORE UPDATE ON integration_order_deliveries FOR EACH ROW EXECUTE FUNCTION integration_delivery_update_guard();

CREATE FUNCTION integration_delivery_attempt_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM integration_order_deliveries d WHERE d.id=NEW.delivery_id AND d.state='PROCESSING'
 AND d.attempt_count=NEW.attempt_no AND d.lease_token=NEW.lease_token AND d.lease_until=NEW.lease_until)
 THEN RAISE EXCEPTION 'integration attempt needs current committed claim';END IF;RETURN NEW;
END $$;
CREATE TRIGGER integration_delivery_attempt BEFORE INSERT ON integration_delivery_attempts FOR EACH ROW EXECUTE FUNCTION integration_delivery_attempt_guard();
CREATE FUNCTION integration_delivery_receipt_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d integration_order_deliveries; a integration_delivery_attempts; BEGIN
 SELECT * INTO STRICT d FROM integration_order_deliveries WHERE id=NEW.delivery_id;
 SELECT * INTO STRICT a FROM integration_delivery_attempts WHERE id=NEW.attempt_id;
 IF a.delivery_id<>d.id OR d.state<>'PROCESSING' OR a.lease_token IS DISTINCT FROM d.lease_token
 OR NEW.received_at<a.claimed_at OR NEW.received_at>=d.lease_until
 THEN RAISE EXCEPTION 'integration receipt lease expired or superseded';END IF;
 IF NEW.result IN ('ACCEPTED','REJECTED') AND NOT EXISTS(SELECT 1 FROM integration_delivery_fixture_orders f
 WHERE f.business_key=d.business_key AND f.connection_id=d.connection_id AND f.merchant_id=d.merchant_id
 AND f.payload_sha256=d.payload_sha256 AND f.result=NEW.result AND f.provider_reference=NEW.provider_reference
 AND f.no_external_order=NEW.no_external_order)
 THEN RAISE EXCEPTION 'integration result not backed by matching synthetic channel';END IF;RETURN NEW;
END $$;
CREATE TRIGGER integration_delivery_receipt BEFORE INSERT ON integration_delivery_receipts FOR EACH ROW EXECUTE FUNCTION integration_delivery_receipt_guard();

CREATE FUNCTION integration_delivery_open(sid uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM integration_order_deliveries WHERE suborder_id=sid AND state<>'REJECTED')
$$;
-- Defense in depth: these triggers never acquire connection/mapping locks behind inventory locks.
-- Native services lock the original order first; declaration uses that same original order lock.
CREATE FUNCTION integration_native_delivery_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE sid uuid; BEGIN
 IF TG_TABLE_NAME IN ('shipments','order_cancellations') THEN sid:=NEW.suborder_id;
 ELSIF TG_TABLE_NAME='inventory_restock_events' THEN SELECT suborder_id INTO STRICT sid FROM order_items WHERE id=NEW.order_item_id;
 ELSIF TG_TABLE_NAME='refunds' THEN
   SELECT coalesce(c.suborder_id,a.suborder_id) INTO sid FROM payments p
   LEFT JOIN order_cancellations c ON c.id=NEW.cancellation_id LEFT JOIN aftersales a ON a.id=NEW.aftersale_id WHERE p.id=NEW.payment_id;
 END IF;
 IF sid IS NOT NULL THEN
   -- Reentrant for native services; also serializes a direct insert with declaration.
   PERFORM o.id FROM orders o JOIN suborders s ON s.order_id=o.id WHERE s.id=sid FOR UPDATE OF o;
   PERFORM id FROM suborders WHERE id=sid FOR UPDATE;
   IF integration_delivery_open(sid) THEN RAISE EXCEPTION 'integration external fulfillment responsibility open';END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER integration_native_ship BEFORE INSERT ON shipments FOR EACH ROW EXECUTE FUNCTION integration_native_delivery_guard();
CREATE TRIGGER integration_native_cancel BEFORE INSERT ON order_cancellations FOR EACH ROW EXECUTE FUNCTION integration_native_delivery_guard();
CREATE TRIGGER integration_native_refund BEFORE INSERT ON refunds FOR EACH ROW EXECUTE FUNCTION integration_native_delivery_guard();
CREATE TRIGGER integration_native_restock BEFORE INSERT ON inventory_restock_events FOR EACH ROW EXECUTE FUNCTION integration_native_delivery_guard();
CREATE FUNCTION integration_mapping_delivery_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.state='RETIRED' AND EXISTS(SELECT 1 FROM integration_order_deliveries d,
 jsonb_array_elements(d.frozen_payload->'lines') l WHERE d.connection_id=NEW.connection_id AND d.state<>'REJECTED' AND l->>'mapping_id'=NEW.id::text)
 THEN RAISE EXCEPTION 'integration mapping delivery responsibility open';END IF;RETURN NEW;
END $$;
CREATE TRIGGER integration_mapping_delivery BEFORE UPDATE ON integration_mappings FOR EACH ROW EXECUTE FUNCTION integration_mapping_delivery_guard();
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['integration_order_deliveries','integration_delivery_attempts','integration_delivery_receipts','integration_delivery_fixture_orders'] LOOP
 EXECUTE format('CREATE TRIGGER integration_no_truncate BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 IF t='integration_order_deliveries' THEN EXECUTE format('CREATE TRIGGER integration_no_delete BEFORE DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 ELSE EXECUTE format('CREATE TRIGGER integration_immutable BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);END IF;
 END LOOP;
END $$;
INSERT INTO permission(code,description) VALUES
 ('integration.delivery.requery','Query scoped synthetic goods order delivery'),
 ('integration.delivery.retry','Retry scoped synthetic goods order with fixed identity');
