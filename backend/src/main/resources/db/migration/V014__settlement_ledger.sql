-- M4.6 merchant settlement ledger: commission snapshots, append-only ledger, settlement tracks and batches.
-- Money facts derive only from real events: payment success, refund success, receipt confirmation, admin execution.

-- Commission policies are versioned, prioritized and immutable once recorded; "editing" means posting a newer row.
CREATE TABLE commission_policies (
 id uuid PRIMARY KEY,name varchar(160) NOT NULL,
 merchant_id uuid REFERENCES merchant(id),category varchar(80),campaign_code varchar(80),
 rate_basis_points integer NOT NULL CHECK(rate_basis_points BETWEEN 0 AND 10000),
 priority integer NOT NULL DEFAULT 0,
 effective_from timestamptz NOT NULL,effective_to timestamptz,
 policy_version integer NOT NULL CHECK(policy_version>=1),
 created_by uuid REFERENCES identity_principal(id),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_commission_policies BEFORE UPDATE OR DELETE ON commission_policies FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE INDEX ix_commission_policies_scope ON commission_policies(merchant_id,category,effective_from);
-- Default platform commission: 5% unless a more specific policy wins at payment time.
INSERT INTO commission_policies(id,name,rate_basis_points,priority,effective_from,policy_version)
VALUES ('7b2f2b6a-7c1f-4d0d-9c1a-000000000001','平台默认佣金',500,0,'2020-01-01T00:00:00Z',1);

-- Settlement buffer policy (after-sale buffer days) is versioned backend configuration; default 7 days.
CREATE TABLE settlement_policies (
 id uuid PRIMARY KEY,buffer_days integer NOT NULL CHECK(buffer_days BETWEEN 0 AND 90),
 policy_version integer NOT NULL CHECK(policy_version>=1),
 created_by uuid REFERENCES identity_principal(id),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_settlement_policies BEFORE UPDATE OR DELETE ON settlement_policies FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
INSERT INTO settlement_policies(id,buffer_days,policy_version) VALUES ('7b2f2b6a-7c1f-4d0d-9c1a-000000000002',7,1);

-- Per-suborder settlement lifecycle track. WAITING_RECEIPT starts at payment success.
CREATE TABLE settlement_tracks (
 id uuid PRIMARY KEY,suborder_id uuid NOT NULL UNIQUE REFERENCES suborders(id),
 order_id uuid NOT NULL REFERENCES orders(id),merchant_id uuid NOT NULL REFERENCES merchant(id),
 status varchar(20) NOT NULL CHECK(status IN ('WAITING_RECEIPT','BUFFERING','FROZEN','ELIGIBLE','PROCESSING','SETTLED','ADJUSTED')),
 settlement_policy_id uuid REFERENCES settlement_policies(id),buffer_days integer,eligible_at timestamptz,
 settlement_id uuid,version bigint NOT NULL DEFAULT 0,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_settlement_tracks_status ON settlement_tracks(status,eligible_at,id);
CREATE FUNCTION protect_settlement_track() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version','settlement_policy_id','buffer_days','eligible_at','settlement_id']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','settlement_policy_id','buffer_days','eligible_at','settlement_id']) OR NEW.version<>OLD.version+1
 OR OLD.status IN ('SETTLED','ADJUSTED') AND NEW.status<>'ADJUSTED'
 OR OLD.status='ADJUSTED'
 OR NOT ((OLD.status='WAITING_RECEIPT' AND NEW.status IN ('BUFFERING','FROZEN','ADJUSTED')) OR (OLD.status='BUFFERING' AND NEW.status IN ('ELIGIBLE','FROZEN')) OR (OLD.status='FROZEN' AND NEW.status IN ('BUFFERING','ELIGIBLE')) OR (OLD.status='ELIGIBLE' AND NEW.status IN ('PROCESSING','FROZEN')) OR (OLD.status='PROCESSING' AND NEW.status IN ('SETTLED','ELIGIBLE')) OR (OLD.status='SETTLED' AND NEW.status='ADJUSTED')) THEN RAISE EXCEPTION 'invalid settlement track mutation'; END IF; RETURN NEW; END $$;
CREATE TRIGGER settlement_track_guard BEFORE UPDATE ON settlement_tracks FOR EACH ROW EXECUTE FUNCTION protect_settlement_track();
CREATE TRIGGER settlement_track_no_delete BEFORE DELETE ON settlement_tracks FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

-- Append-only merchant ledger. affects_balance=false rows are evidence copies kept next to the balance bridge entry.
CREATE TABLE merchant_ledger_entries (
 id uuid PRIMARY KEY,merchant_id uuid NOT NULL REFERENCES merchant(id),
 entry_type varchar(24) NOT NULL CHECK(entry_type IN ('SALE_CREDIT','COMMISSION_DEBIT','REFUND_DEBIT','COMMISSION_REVERSAL','SHIPPING_ADJUSTMENT','SETTLEMENT_DEBIT','SETTLEMENT_ADJUSTMENT','MANUAL_ADJUSTMENT')),
 direction varchar(6) NOT NULL CHECK(direction IN ('CREDIT','DEBIT')),
 amount_fen bigint NOT NULL CHECK(amount_fen>0),affects_balance boolean NOT NULL,
 order_id uuid,suborder_id uuid,order_item_id uuid,refund_id uuid,settlement_id uuid,
 source_event varchar(64) NOT NULL,reason varchar(500),
 created_by_type varchar(16) NOT NULL CHECK(created_by_type IN ('SYSTEM','PRINCIPAL')),created_by uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK((entry_type='SALE_CREDIT' AND direction='CREDIT') OR (entry_type='COMMISSION_DEBIT' AND direction='DEBIT') OR (entry_type='REFUND_DEBIT' AND direction='DEBIT') OR (entry_type='COMMISSION_REVERSAL' AND direction='CREDIT') OR (entry_type='SETTLEMENT_DEBIT' AND direction='DEBIT') OR entry_type IN ('SHIPPING_ADJUSTMENT','SETTLEMENT_ADJUSTMENT','MANUAL_ADJUSTMENT'))
);
CREATE TRIGGER immutable_ledger_entries BEFORE UPDATE OR DELETE ON merchant_ledger_entries FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE INDEX ix_ledger_merchant ON merchant_ledger_entries(merchant_id,created_at,id);
CREATE INDEX ix_ledger_suborder ON merchant_ledger_entries(suborder_id) WHERE suborder_id IS NOT NULL;
CREATE UNIQUE INDEX uq_ledger_sale ON merchant_ledger_entries(suborder_id) WHERE entry_type='SALE_CREDIT';
CREATE UNIQUE INDEX uq_ledger_commission ON merchant_ledger_entries(order_item_id) WHERE entry_type='COMMISSION_DEBIT';
CREATE UNIQUE INDEX uq_ledger_refund ON merchant_ledger_entries(refund_id) WHERE entry_type='REFUND_DEBIT';
CREATE UNIQUE INDEX uq_ledger_shipping ON merchant_ledger_entries(refund_id) WHERE entry_type='SHIPPING_ADJUSTMENT';
CREATE UNIQUE INDEX uq_ledger_reversal ON merchant_ledger_entries(refund_id,order_item_id) WHERE entry_type='COMMISSION_REVERSAL';
CREATE UNIQUE INDEX uq_ledger_settlement_debit ON merchant_ledger_entries(settlement_id) WHERE entry_type='SETTLEMENT_DEBIT';
CREATE UNIQUE INDEX uq_ledger_settlement_adjustment ON merchant_ledger_entries(refund_id) WHERE entry_type='SETTLEMENT_ADJUSTMENT';

-- Commission snapshot frozen per order item at payment success; partial refunds reverse proportionally from this snapshot.
CREATE TABLE commission_allocations (
 id uuid PRIMARY KEY,order_item_id uuid NOT NULL UNIQUE REFERENCES order_items(id),
 payment_id uuid NOT NULL REFERENCES payments(id),
 policy_id uuid REFERENCES commission_policies(id),policy_version integer,priority integer,
 rate_basis_points integer NOT NULL CHECK(rate_basis_points BETWEEN 0 AND 10000),
 base_amount_fen bigint NOT NULL CHECK(base_amount_fen>=0),commission_fen bigint NOT NULL CHECK(commission_fen>=0),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_commission_allocations BEFORE UPDATE OR DELETE ON commission_allocations FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

-- Merchant settlement batch: consumes eligible unconsumed balance entries exactly once.
CREATE TABLE settlements (
 id uuid PRIMARY KEY,settlement_no varchar(48) NOT NULL UNIQUE,
 merchant_id uuid NOT NULL REFERENCES merchant(id),
 status varchar(16) NOT NULL CHECK(status IN ('PROCESSING','SETTLED','FAILED_RETRYABLE')),
 amount_fen bigint NOT NULL CHECK(amount_fen>0),entry_count integer NOT NULL CHECK(entry_count>0),
 attempt_count integer NOT NULL DEFAULT 0,last_error_code varchar(80),channel_reference varchar(100),
 initiated_by uuid REFERENCES identity_principal(id),
 created_at timestamptz NOT NULL DEFAULT now(),settled_at timestamptz,next_retry_at timestamptz
);
CREATE FUNCTION protect_settlement() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','attempt_count','last_error_code','channel_reference','settled_at','next_retry_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','attempt_count','last_error_code','channel_reference','settled_at','next_retry_at'])
 OR OLD.status='SETTLED'
 OR NOT ((OLD.status='PROCESSING' AND NEW.status IN ('SETTLED','FAILED_RETRYABLE')) OR (OLD.status='FAILED_RETRYABLE' AND NEW.status IN ('PROCESSING','FAILED_RETRYABLE'))) THEN RAISE EXCEPTION 'invalid settlement mutation'; END IF; RETURN NEW; END $$;
CREATE TRIGGER settlement_guard BEFORE UPDATE ON settlements FOR EACH ROW EXECUTE FUNCTION protect_settlement();
CREATE TRIGGER settlement_no_delete BEFORE DELETE ON settlements FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
ALTER TABLE settlement_tracks ADD CONSTRAINT fk_track_settlement FOREIGN KEY(settlement_id) REFERENCES settlements(id);

CREATE TABLE settlement_items (
 settlement_id uuid NOT NULL REFERENCES settlements(id),
 ledger_entry_id uuid NOT NULL REFERENCES merchant_ledger_entries(id),
 signed_amount_fen bigint NOT NULL,
 PRIMARY KEY(settlement_id,ledger_entry_id)
);
CREATE UNIQUE INDEX uq_settlement_item_entry ON settlement_items(ledger_entry_id);
CREATE TRIGGER immutable_settlement_items BEFORE UPDATE OR DELETE ON settlement_items FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

-- Development disbursement channel: one payout per settlement, with test directives for failure drills.
CREATE TABLE simulated_settlement_disbursements (
 settlement_no varchar(48) PRIMARY KEY,merchant_id uuid NOT NULL,amount_fen bigint NOT NULL CHECK(amount_fen>0),
 channel_reference varchar(100) NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_simulated_disbursements BEFORE UPDATE OR DELETE ON simulated_settlement_disbursements FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE simulated_settlement_directives (
 settlement_no varchar(48) PRIMARY KEY,outcome varchar(20) NOT NULL CHECK(outcome IN ('SUCCEED','FAIL_TRANSIENT'))
);

INSERT INTO permission(code,description) VALUES
 ('settlement.read','Read settlement tracks, batches and finance summaries within authorized scopes'),
 ('settlement.execute','Initiate and retry merchant settlement batches after reverify'),
 ('settlement.policy.manage','Manage commission and settlement buffer policies after reverify'),
 ('ledger.read','Read merchant ledger entries within authorized scopes'),
 ('ledger.adjust','Post manual merchant ledger adjustments after reverify');
