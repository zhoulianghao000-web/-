CREATE TABLE offers (
 id uuid PRIMARY KEY, merchant_id uuid NOT NULL REFERENCES merchant(id),
 store_id uuid, sku_id uuid NOT NULL REFERENCES skus(id),
 sale_price_fen bigint NOT NULL CHECK(sale_price_fen BETWEEN 1 AND 1000000000),
 member_price_fen bigint CHECK(member_price_fen BETWEEN 1 AND sale_price_fen),
 fulfillment_sla varchar(500) NOT NULL CHECK(length(trim(fulfillment_sla)) > 0),
 sale_status varchar(16) NOT NULL DEFAULT 'DRAFT'
   CHECK(sale_status IN ('DRAFT','ACTIVE','PAUSED','FROZEN','DELISTED')),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,merchant_id), FOREIGN KEY(store_id,merchant_id) REFERENCES merchant_store(id,merchant_id)
);
CREATE UNIQUE INDEX uq_offer_live_scope ON offers(merchant_id,sku_id,store_id) NULLS NOT DISTINCT
 WHERE sale_status IN ('DRAFT','ACTIVE','PAUSED','FROZEN');
CREATE TABLE inventory_balances (
 offer_id uuid PRIMARY KEY REFERENCES offers(id),
 on_hand_qty bigint NOT NULL DEFAULT 0 CHECK(on_hand_qty BETWEEN 0 AND 1000000000),
 reserved_qty bigint NOT NULL DEFAULT 0 CHECK(reserved_qty BETWEEN 0 AND on_hand_qty),
 available_qty bigint GENERATED ALWAYS AS (on_hand_qty-reserved_qty) STORED,
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE inventory_adjustments (
 id uuid PRIMARY KEY, merchant_id uuid NOT NULL,
 operation varchar(32) NOT NULL DEFAULT 'INVENTORY_ADJUSTMENT' CHECK(operation='INVENTORY_ADJUSTMENT'),
 offer_id uuid NOT NULL, delta_qty bigint NOT NULL CHECK(delta_qty BETWEEN -1000000000 AND 1000000000 AND delta_qty<>0),
 reason_code varchar(32) NOT NULL CHECK(reason_code IN ('RESTOCK','COUNT_CORRECTION','DAMAGE')),
 expected_version bigint NOT NULL CHECK(expected_version>=0),
 before_on_hand_qty bigint NOT NULL, resulting_on_hand_qty bigint NOT NULL,
 resulting_reserved_qty bigint NOT NULL, resulting_version bigint NOT NULL,
 actor_id uuid NOT NULL REFERENCES identity_principal(id),
 idempotency_key varchar(128) NOT NULL, payload_hash varchar(64) NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(merchant_id,operation,idempotency_key),
 FOREIGN KEY(offer_id,merchant_id) REFERENCES offers(id,merchant_id),
 CHECK(resulting_on_hand_qty=before_on_hand_qty+delta_qty),
 CHECK(resulting_on_hand_qty>=resulting_reserved_qty AND resulting_reserved_qty>=0),
 CHECK(resulting_version=expected_version+1)
);
CREATE INDEX ix_inventory_adjustment_offer ON inventory_adjustments(offer_id,id);
CREATE FUNCTION reject_inventory_adjustment_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'inventory_adjustments is append-only'; END $$;
CREATE TRIGGER inventory_adjustment_immutable BEFORE UPDATE OR DELETE ON inventory_adjustments
 FOR EACH ROW EXECUTE FUNCTION reject_inventory_adjustment_mutation();
CREATE TRIGGER inventory_adjustment_no_truncate BEFORE TRUNCATE ON inventory_adjustments
 FOR EACH STATEMENT EXECUTE FUNCTION reject_inventory_adjustment_mutation();
INSERT INTO permission(code,description) VALUES
 ('offer.read','Merchant scoped offer and inventory read'),
 ('offer.write','Merchant scoped offer price and sale commands'),
 ('inventory.adjust','Merchant scoped append-only stock adjustments'),
 ('offer.default-scope','Explicit access to merchant default fulfillment scope'),
 ('offer.admin.read','Platform offer and stock inspection'),
 ('offer.admin.manage','Platform freeze, unfreeze and delist after reverify');
