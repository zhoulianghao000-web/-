-- M5.1 membership purchase and consumer points ledger.
-- Membership plans are versioned and immutable; points always move through an append-only ledger with unique business keys.

-- Sellable membership plans; "editing" means posting a newer plan_version for the same code.
CREATE TABLE membership_plans (
 id uuid PRIMARY KEY,code varchar(40) NOT NULL,name varchar(80) NOT NULL,
 term varchar(8) NOT NULL CHECK(term IN ('MONTH','YEAR')),
 price_fen bigint NOT NULL CHECK(price_fen BETWEEN 1 AND 100000000),
 ai_quota integer NOT NULL DEFAULT 0 CHECK(ai_quota>=0),
 benefits jsonb NOT NULL DEFAULT '[]'::jsonb,
 status varchar(12) NOT NULL CHECK(status IN ('ACTIVE','RETIRED')),
 plan_version integer NOT NULL CHECK(plan_version>=1),
 created_by uuid REFERENCES identity_principal(id),created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(code,plan_version)
);
CREATE TRIGGER immutable_membership_plans BEFORE UPDATE OR DELETE ON membership_plans FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
INSERT INTO membership_plans(id,code,name,term,price_fen,ai_quota,benefits,status,plan_version) VALUES
 ('3c9a1f2e-5b6d-4e7f-8a9b-000000000001','MEMBER_MONTH','月度会员','MONTH',1500,20,'["会员价","AI 问答额度 20 次/月"]','ACTIVE',1),
 ('3c9a1f2e-5b6d-4e7f-8a9b-000000000002','MEMBER_YEAR','年度会员','YEAR',12800,300,'["会员价","AI 问答额度 300 次/年"]','ACTIVE',1);

-- Membership purchase orders, separate from goods orders; paid through the shared payments pipeline.
CREATE TABLE membership_orders (
 id uuid PRIMARY KEY,order_no varchar(40) NOT NULL UNIQUE,
 user_id uuid NOT NULL REFERENCES app_user(id),
 plan_id uuid NOT NULL REFERENCES membership_plans(id),
 plan_snapshot jsonb NOT NULL,
 amount_fen bigint NOT NULL CHECK(amount_fen>=1),
 status varchar(20) NOT NULL DEFAULT 'PENDING_PAYMENT' CHECK(status IN ('PENDING_PAYMENT','PAID','EXPIRED','CANCELLED')),
 payment_id uuid,version bigint NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(),paid_at timestamptz
);
CREATE FUNCTION protect_membership_order() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version','payment_id','paid_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','payment_id','paid_at']) OR NEW.version<>OLD.version+1
 OR OLD.status IN ('PAID','EXPIRED','CANCELLED')
 OR NOT ((OLD.status='PENDING_PAYMENT' AND NEW.status='PENDING_PAYMENT' AND NEW.paid_at IS NULL) OR (OLD.status='PENDING_PAYMENT' AND NEW.status IN ('PAID','EXPIRED','CANCELLED'))) THEN RAISE EXCEPTION 'invalid membership order mutation'; END IF; RETURN NEW; END $$;
CREATE TRIGGER membership_order_guard BEFORE UPDATE ON membership_orders FOR EACH ROW EXECUTE FUNCTION protect_membership_order();
CREATE TRIGGER membership_order_no_delete BEFORE DELETE ON membership_orders FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE INDEX ix_membership_orders_user ON membership_orders(user_id,created_at,id);

-- Payments now reference exactly one of goods order or membership order.
ALTER TABLE payments ALTER COLUMN order_id DROP NOT NULL;
ALTER TABLE payments DROP CONSTRAINT payments_order_id_key;
ALTER TABLE payments ADD membership_order_id uuid REFERENCES membership_orders(id);
ALTER TABLE payments ADD CONSTRAINT payments_exactly_one_owner CHECK((order_id IS NOT NULL)<>(membership_order_id IS NOT NULL));
CREATE UNIQUE INDEX uq_payments_order ON payments(order_id) WHERE order_id IS NOT NULL;
CREATE UNIQUE INDEX uq_payments_membership_order ON payments(membership_order_id) WHERE membership_order_id IS NOT NULL;
ALTER TABLE membership_orders ADD CONSTRAINT fk_membership_order_payment FOREIGN KEY(payment_id) REFERENCES payments(id);

-- Versioned points operation policy; purchase earn rate and check-in rules are backend configuration.
CREATE TABLE points_policies (
 id uuid PRIMARY KEY,
 earn_points_per_yuan integer NOT NULL CHECK(earn_points_per_yuan BETWEEN 0 AND 1000),
 checkin_points integer NOT NULL CHECK(checkin_points BETWEEN 1 AND 10000),
 checkin_cycle_days integer NOT NULL CHECK(checkin_cycle_days BETWEEN 1 AND 30),
 policy_version integer NOT NULL CHECK(policy_version>=1),
 created_by uuid REFERENCES identity_principal(id),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_points_policies BEFORE UPDATE OR DELETE ON points_policies FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
INSERT INTO points_policies(id,earn_points_per_yuan,checkin_points,checkin_cycle_days,policy_version)
VALUES ('5d1e2f3a-4b5c-6d7e-8f9a-000000000001',1,5,30,1);

-- Lock row per consumer; balance itself is derived from the ledger, never stored as the source of truth.
CREATE TABLE points_accounts (
 user_id uuid PRIMARY KEY REFERENCES app_user(id),
 version bigint NOT NULL DEFAULT 0,created_at timestamptz NOT NULL DEFAULT now()
);

-- Append-only points ledger. Sign is bound to entry type; negative balances are allowed so refund clawbacks
-- can overtake spent points, while new redemptions require balance>=0 and balance>=cost.
CREATE TABLE points_ledger (
 id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES app_user(id),
 entry_type varchar(24) NOT NULL CHECK(entry_type IN ('PURCHASE_EARN','REVIEW_EARN','MEDIA_REVIEW_BONUS','CHECKIN_EARN','REDEMPTION_SPEND','REFUND_CLAWBACK','MANUAL_ADJUSTMENT')),
 points bigint NOT NULL CHECK(points<>0),
 business_key varchar(120) NOT NULL UNIQUE,
 order_id uuid,refund_id uuid,redemption_id uuid,policy_version integer,
 reason varchar(500),
 created_by_type varchar(16) NOT NULL CHECK(created_by_type IN ('SYSTEM','PRINCIPAL')),created_by uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK((entry_type IN ('PURCHASE_EARN','REVIEW_EARN','MEDIA_REVIEW_BONUS','CHECKIN_EARN') AND points>0)
    OR (entry_type IN ('REDEMPTION_SPEND','REFUND_CLAWBACK') AND points<0)
    OR entry_type='MANUAL_ADJUSTMENT')
);
CREATE TRIGGER immutable_points_ledger BEFORE UPDATE OR DELETE ON points_ledger FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE INDEX ix_points_ledger_user ON points_ledger(user_id,created_at,id);

-- Daily check-in facts; one row per user per day, consecutive streak capped by policy cycle length.
CREATE TABLE points_checkins (
 id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES app_user(id),
 checkin_date date NOT NULL,cycle_day integer NOT NULL CHECK(cycle_day BETWEEN 1 AND 30),
 points integer NOT NULL CHECK(points>0),
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(user_id,checkin_date)
);
CREATE TRIGGER immutable_points_checkins BEFORE UPDATE OR DELETE ON points_checkins FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

-- Redeemable rewards are versioned like plans; redemption spends are atomic under the account row lock.
CREATE TABLE points_rewards (
 id uuid PRIMARY KEY,code varchar(60) NOT NULL,name varchar(120) NOT NULL,
 cost_points bigint NOT NULL CHECK(cost_points BETWEEN 1 AND 100000000),
 status varchar(12) NOT NULL CHECK(status IN ('ACTIVE','RETIRED')),
 reward_version integer NOT NULL CHECK(reward_version>=1),
 created_by uuid REFERENCES identity_principal(id),created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(code,reward_version)
);
CREATE TRIGGER immutable_points_rewards BEFORE UPDATE OR DELETE ON points_rewards FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

CREATE TABLE points_redemptions (
 id uuid PRIMARY KEY,redemption_no varchar(40) NOT NULL UNIQUE,
 user_id uuid NOT NULL REFERENCES app_user(id),
 reward_id uuid NOT NULL REFERENCES points_rewards(id),
 reward_snapshot jsonb NOT NULL,cost_points bigint NOT NULL CHECK(cost_points>0),
 status varchar(16) NOT NULL CHECK(status IN ('SUCCEEDED')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_points_redemptions BEFORE UPDATE OR DELETE ON points_redemptions FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE INDEX ix_points_redemptions_user ON points_redemptions(user_id,created_at,id);

-- The goods-order consistency gate from V011 only applies to goods payments; membership payments
-- verify attempt/receipt integrity and membership order activation instead.
CREATE OR REPLACE FUNCTION verify_payment_success_commit() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE a payment_attempts%ROWTYPE;r payment_receipts%ROWTYPE; BEGIN
 IF NEW.status<>'SUCCEEDED' THEN RETURN NULL; END IF;
 SELECT * INTO a FROM payment_attempts WHERE id=NEW.successful_attempt_id;SELECT * INTO r FROM payment_receipts WHERE id=NEW.successful_receipt_id;
 IF a.status<>'CHANNEL_SUCCEEDED' OR r.amount_fen<>NEW.amount_fen OR r.currency<>NEW.currency THEN RAISE EXCEPTION 'payment success consistency'; END IF;
 IF NEW.membership_order_id IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM membership_orders mo WHERE mo.id=NEW.membership_order_id AND mo.payment_id=NEW.id AND mo.status='PAID' AND mo.amount_fen=NEW.amount_fen) THEN RAISE EXCEPTION 'payment success consistency'; END IF; RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM orders WHERE id=NEW.order_id AND status='FULFILLING')
 OR EXISTS(SELECT 1 FROM suborders WHERE order_id=NEW.order_id AND fulfillment_status<>'PAID_WAITING_FULFILLMENT')
 OR EXISTS(SELECT 1 FROM inventory_reservations v WHERE v.order_id=NEW.order_id AND (v.status<>'CONSUMED' OR NOT EXISTS(SELECT 1 FROM inventory_sale_events e WHERE e.reservation_id=v.id AND e.payment_id=NEW.id AND e.offer_id=v.offer_id AND e.quantity=v.quantity)))
 OR EXISTS(SELECT 1 FROM order_coupon_snapshots c WHERE c.order_id=NEW.order_id AND NOT EXISTS(SELECT 1 FROM coupon_redemption_events e JOIN user_coupons u ON u.id=e.coupon_id WHERE e.order_id=c.order_id AND e.coupon_id=c.coupon_id AND e.payment_id=NEW.id AND u.status='USED'))
 THEN RAISE EXCEPTION 'payment success consistency'; END IF; RETURN NULL; END $$;

INSERT INTO permission(code,description) VALUES
 ('membership.plan.manage','Publish or retire membership plan versions after reverify'),
 ('points.policy.manage','Manage points earn and check-in policies after reverify'),
 ('points.reward.manage','Manage points reward catalogue versions after reverify'),
 ('points.adjust','Post manual consumer points adjustments after reverify'),
 ('points.read','Read consumer points balance and ledger within authorized scopes');
