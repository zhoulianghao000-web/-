-- B1 follow-up: preserve V035 and reject takeover while original obligations remain.
-- No historical balances, mappings, claims or policies are rewritten.
CREATE FUNCTION integration_bootstrap_has_open_responsibility(offer uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS (
  SELECT 1 FROM order_items i JOIN suborders s ON s.id=i.suborder_id WHERE i.offer_id=offer AND (
   s.fulfillment_status NOT IN ('CANCELLED','COMPLETED')
   OR EXISTS (SELECT 1 FROM aftersale_items ai JOIN aftersales a ON a.id=ai.aftersale_id
              WHERE ai.order_item_id=i.id AND a.status NOT IN ('COMPLETED','CANCELLED')
              AND (a.status<>'REJECTED' OR NOT EXISTS (SELECT 1 FROM aftersale_decisions d WHERE d.aftersale_id=a.id AND d.decision='REJECTED')))
   OR EXISTS (SELECT 1 FROM order_cancellation_items ci JOIN order_cancellations c ON c.id=ci.cancellation_id
              WHERE ci.order_item_id=i.id AND c.status NOT IN ('COMPLETED','REJECTED'))
   OR EXISTS (SELECT 1 FROM refunds r WHERE r.status NOT IN ('SUCCEEDED','CANCELLED') AND (
        EXISTS (SELECT 1 FROM order_cancellation_items ci WHERE ci.cancellation_id=r.cancellation_id AND ci.order_item_id=i.id)
        OR EXISTS (SELECT 1 FROM aftersale_items ai WHERE ai.aftersale_id=r.aftersale_id AND ai.order_item_id=i.id)))
   OR EXISTS (SELECT 1 FROM payments p JOIN payment_cases c ON c.payment_id=p.id
              WHERE p.order_id=s.order_id AND c.status<>'REFUNDED')
   OR EXISTS (SELECT 1 FROM payments p JOIN payment_attempts a ON a.payment_id=p.id
              WHERE p.order_id=s.order_id AND a.status IN ('CREATED','CHANNEL_PENDING','UNKNOWN'))
  )
 )
$$;
CREATE FUNCTION integration_guard_bootstrap_responsibility() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 -- Same connection -> offer -> balance order as the scoped bootstrap command.
 PERFORM 1 FROM integration_connections WHERE id=NEW.connection_id FOR UPDATE;
 PERFORM 1 FROM offers WHERE id=NEW.offer_id FOR UPDATE;
 PERFORM 1 FROM inventory_balances WHERE offer_id=NEW.offer_id FOR UPDATE;
 IF integration_bootstrap_has_open_responsibility(NEW.offer_id) THEN RAISE EXCEPTION 'integration bootstrap has open original responsibility';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER integration_mapping_bootstrap_responsibility BEFORE INSERT ON integration_mappings
 FOR EACH ROW EXECUTE FUNCTION integration_guard_bootstrap_responsibility();
