-- A platform decision must load the persisted trade version; no client-entered version.
INSERT INTO permission(code,description) VALUES
 ('service.trade.admin.read','Read paid service trade detail for authorized platform handling') ON CONFLICT DO NOTHING;
-- Merchant cancellation is also valid before collection, with no fabricated refund.
DO $$ DECLARE c record;BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='service_trade_orders'::regclass AND contype='c'
 AND pg_get_constraintdef(oid) LIKE '%order_state%' AND pg_get_constraintdef(oid) LIKE '%cancel_reason%' LOOP
 EXECUTE format('ALTER TABLE service_trade_orders DROP CONSTRAINT %I',c.conname);END LOOP;
END $$;
ALTER TABLE service_trade_orders ADD CONSTRAINT service_trade_order_coherence_v34 CHECK
 ((order_state='AWAITING_PAYMENT' AND payment_state='PENDING' AND capacity_state='HELD' AND closed_at IS NULL AND receipt_id IS NULL AND confirmed_at IS NULL AND cancel_reason IS NULL)
 OR (order_state='CONFIRMED' AND payment_state='SUCCEEDED' AND capacity_state='CONFIRMED' AND closed_at IS NULL AND receipt_id IS NOT NULL AND confirmed_at IS NOT NULL AND cancel_reason IS NULL)
 OR (order_state='CANCELLED' AND payment_state='SUCCEEDED' AND capacity_state='RELEASED' AND closed_at IS NOT NULL AND receipt_id IS NOT NULL AND confirmed_at IS NOT NULL AND cancel_reason IN ('CONSUMER_CANCELLED','SERVICE_UNAVAILABLE'))
 OR (order_state='CANCELLED' AND payment_state='CLOSED' AND capacity_state='RELEASED' AND closed_at IS NOT NULL AND receipt_id IS NULL AND confirmed_at IS NULL AND cancel_reason IN ('CONSUMER_CANCELLED','SERVICE_UNAVAILABLE'))
 OR (order_state='EXPIRED' AND payment_state='CLOSED' AND capacity_state='RELEASED' AND closed_at IS NOT NULL AND receipt_id IS NULL AND confirmed_at IS NULL AND cancel_reason='PAYMENT_WINDOW_EXPIRED'));
