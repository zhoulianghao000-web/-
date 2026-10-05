CREATE TABLE shipments (
 id uuid PRIMARY KEY,suborder_id uuid NOT NULL REFERENCES suborders(id),carrier_code varchar(24) NOT NULL,
 tracking_no varchar(80) NOT NULL,created_by uuid NOT NULL REFERENCES identity_principal(id),created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,suborder_id),UNIQUE(carrier_code,tracking_no)
);
ALTER TABLE order_items ADD CONSTRAINT uq_fulfillment_item UNIQUE(id,suborder_id);
CREATE TABLE shipment_items (
 shipment_id uuid NOT NULL,suborder_id uuid NOT NULL,order_item_id uuid NOT NULL,quantity bigint NOT NULL CHECK(quantity>0),
 PRIMARY KEY(shipment_id,order_item_id),FOREIGN KEY(shipment_id,suborder_id) REFERENCES shipments(id,suborder_id),
 FOREIGN KEY(order_item_id,suborder_id) REFERENCES order_items(id,suborder_id)
);
CREATE TABLE shipment_receipts (
 shipment_id uuid PRIMARY KEY REFERENCES shipments(id),user_id uuid NOT NULL REFERENCES app_user(id),confirmed_at timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION verify_shipment_quantity() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE item order_items%ROWTYPE; shipped bigint; BEGIN
 SELECT * INTO item FROM order_items WHERE id=NEW.order_item_id FOR UPDATE;
 SELECT coalesce(sum(quantity),0) INTO shipped FROM shipment_items WHERE order_item_id=item.id;
 IF shipped+NEW.quantity>item.quantity-item.cancelled_qty OR NOT EXISTS(
 SELECT 1 FROM suborders s JOIN payments p ON p.order_id=s.order_id WHERE s.id=item.suborder_id AND p.status='SUCCEEDED'
 AND s.fulfillment_status IN ('PAID_WAITING_FULFILLMENT','PARTIALLY_SHIPPED','PARTIALLY_COMPLETED')) THEN RAISE EXCEPTION 'invalid shipment quantity or payment'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER shipment_quantity_guard BEFORE INSERT ON shipment_items FOR EACH ROW EXECUTE FUNCTION verify_shipment_quantity();
CREATE FUNCTION verify_receipt_owner() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM shipments h JOIN suborders s ON s.id=h.suborder_id JOIN orders o ON o.id=s.order_id WHERE h.id=NEW.shipment_id AND o.user_id=NEW.user_id)
 OR NOT EXISTS(SELECT 1 FROM shipment_items WHERE shipment_id=NEW.shipment_id) THEN RAISE EXCEPTION 'invalid receipt owner'; END IF; RETURN NEW; END $$;
CREATE TRIGGER receipt_owner_guard BEFORE INSERT ON shipment_receipts FOR EACH ROW EXECUTE FUNCTION verify_receipt_owner();
DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['shipments','shipment_items','shipment_receipts'] LOOP
 EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t); END LOOP; END $$;
ALTER TABLE suborders DROP CONSTRAINT suborders_fulfillment_status_check;
ALTER TABLE suborders ADD CHECK(fulfillment_status IN ('PENDING_PAYMENT','PAID_WAITING_FULFILLMENT','PARTIALLY_SHIPPED','SHIPPED_WAITING_RECEIPT','PARTIALLY_COMPLETED','COMPLETED','CANCELLED'));
CREATE OR REPLACE FUNCTION protect_order_state() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version']) OR NEW.version<>OLD.version+1
 OR NOT ((OLD.status='PENDING_PAYMENT' AND NEW.status IN ('CANCELLED','FULFILLING')) OR (OLD.status='FULFILLING' AND NEW.status='FULFILLING')) THEN RAISE EXCEPTION 'invalid order mutation'; END IF; RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION protect_suborder_state() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE total bigint; shipped bigint; received bigint; expected text; BEGIN
 IF (to_jsonb(NEW)-ARRAY['fulfillment_status','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['fulfillment_status','version']) OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid suborder mutation'; END IF;
 IF OLD.fulfillment_status='PENDING_PAYMENT' AND NEW.fulfillment_status IN ('CANCELLED','PAID_WAITING_FULFILLMENT') THEN RETURN NEW; END IF;
 IF OLD.fulfillment_status IN ('PENDING_PAYMENT','CANCELLED','COMPLETED') THEN RAISE EXCEPTION 'terminal suborder'; END IF;
 SELECT coalesce(sum(quantity-cancelled_qty),0) INTO total FROM order_items WHERE suborder_id=NEW.id;
 SELECT coalesce(sum(i.quantity),0),coalesce(sum(i.quantity) FILTER(WHERE r.shipment_id IS NOT NULL),0) INTO shipped,received FROM shipment_items i LEFT JOIN shipment_receipts r ON r.shipment_id=i.shipment_id WHERE i.suborder_id=NEW.id;
 expected:=CASE WHEN received=total THEN 'COMPLETED' WHEN received>0 THEN 'PARTIALLY_COMPLETED' WHEN shipped=total THEN 'SHIPPED_WAITING_RECEIPT' WHEN shipped>0 THEN 'PARTIALLY_SHIPPED' ELSE 'PAID_WAITING_FULFILLMENT' END;
 IF NEW.fulfillment_status<>expected THEN RAISE EXCEPTION 'fulfillment state lacks quantity evidence'; END IF; RETURN NEW; END $$;
INSERT INTO permission(code,description) VALUES ('order.ship','Create shipment in all authorized item scopes');

-- Facts and their quantity-derived state must commit together, even for direct SQL.
CREATE FUNCTION verify_fulfillment_commit() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE sub uuid; total bigint; shipped bigint; received bigint; expected text; actual text; BEGIN
 IF TG_TABLE_NAME='shipment_receipts' THEN SELECT suborder_id INTO sub FROM shipments WHERE id=NEW.shipment_id; ELSE sub:=NEW.suborder_id; END IF;
 SELECT coalesce(sum(quantity-cancelled_qty),0) INTO total FROM order_items WHERE suborder_id=sub;
 SELECT coalesce(sum(i.quantity),0),coalesce(sum(i.quantity) FILTER(WHERE r.shipment_id IS NOT NULL),0) INTO shipped,received FROM shipment_items i LEFT JOIN shipment_receipts r ON r.shipment_id=i.shipment_id WHERE i.suborder_id=sub;
 expected:=CASE WHEN received=total THEN 'COMPLETED' WHEN received>0 THEN 'PARTIALLY_COMPLETED' WHEN shipped=total THEN 'SHIPPED_WAITING_RECEIPT' WHEN shipped>0 THEN 'PARTIALLY_SHIPPED' ELSE 'PAID_WAITING_FULFILLMENT' END;
 SELECT fulfillment_status INTO actual FROM suborders WHERE id=sub;
 IF actual<>expected OR EXISTS(SELECT 1 FROM shipments h WHERE h.suborder_id=sub AND NOT EXISTS(SELECT 1 FROM shipment_items i WHERE i.shipment_id=h.id)) THEN RAISE EXCEPTION 'fulfillment commit consistency'; END IF;RETURN NULL;END $$;
CREATE CONSTRAINT TRIGGER shipment_commit_consistency AFTER INSERT ON shipments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_fulfillment_commit();
CREATE CONSTRAINT TRIGGER shipment_item_commit_consistency AFTER INSERT ON shipment_items DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_fulfillment_commit();
CREATE CONSTRAINT TRIGGER receipt_commit_consistency AFTER INSERT ON shipment_receipts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verify_fulfillment_commit();
