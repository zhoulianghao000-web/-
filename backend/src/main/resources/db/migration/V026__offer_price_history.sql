-- Only observed quotations are recorded; an existing quote is observed at migration time.
CREATE TABLE offer_price_snapshots (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 offer_id uuid NOT NULL REFERENCES offers(id),
 merchant_id uuid NOT NULL REFERENCES merchant(id),
 store_id uuid REFERENCES merchant_store(id),
 sku_id uuid NOT NULL REFERENCES skus(id),
 offer_version bigint NOT NULL CHECK(offer_version>=0),
 sale_price_fen bigint NOT NULL CHECK(sale_price_fen BETWEEN 1 AND 1000000000),
 member_price_fen bigint CHECK(member_price_fen BETWEEN 1 AND sale_price_fen),
 sale_status varchar(16) NOT NULL CHECK(sale_status IN ('DRAFT','ACTIVE','PAUSED','FROZEN','DELISTED')),
 kind varchar(16) NOT NULL CHECK(kind IN ('BASELINE','CREATED','PRICE_CHANGE','STATE_CHANGE')),
 publicly_recorded boolean NOT NULL CHECK(NOT publicly_recorded OR sale_status='ACTIVE'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_offer_price_history ON offer_price_snapshots(offer_id,recorded_at DESC,id DESC);
CREATE FUNCTION offer_quote_public_at_recording(owner_id uuid,spec_id uuid,state text) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT state='ACTIVE' AND EXISTS(
  SELECT 1 FROM merchant m,skus k JOIN spus p ON p.id=k.spu_id JOIN brands b ON b.id=p.brand_id
  WHERE m.id=owner_id AND m.status='ACTIVE' AND k.id=spec_id AND k.status='ACTIVE' AND p.status='ACTIVE' AND b.status='ACTIVE'
  AND EXISTS(SELECT 1 FROM sku_standard_versions v WHERE v.sku_id=k.id AND v.status='PUBLISHED')
 )
$$;
INSERT INTO offer_price_snapshots(offer_id,merchant_id,store_id,sku_id,offer_version,sale_price_fen,member_price_fen,sale_status,kind,publicly_recorded)
 SELECT id,merchant_id,store_id,sku_id,version,sale_price_fen,member_price_fen,sale_status,'BASELINE',offer_quote_public_at_recording(merchant_id,sku_id,sale_status) FROM offers;
CREATE FUNCTION record_offer_price_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE change_kind varchar(16);
BEGIN
 IF TG_OP='INSERT' THEN change_kind:='CREATED';
 ELSIF OLD.sale_price_fen IS DISTINCT FROM NEW.sale_price_fen OR OLD.member_price_fen IS DISTINCT FROM NEW.member_price_fen THEN change_kind:='PRICE_CHANGE';
 ELSIF OLD.sale_status IS DISTINCT FROM NEW.sale_status THEN change_kind:='STATE_CHANGE';
 ELSE RETURN NEW;
 END IF;
 INSERT INTO offer_price_snapshots(offer_id,merchant_id,store_id,sku_id,offer_version,sale_price_fen,member_price_fen,sale_status,kind,publicly_recorded)
 VALUES(NEW.id,NEW.merchant_id,NEW.store_id,NEW.sku_id,NEW.version,NEW.sale_price_fen,NEW.member_price_fen,NEW.sale_status,change_kind,offer_quote_public_at_recording(NEW.merchant_id,NEW.sku_id,NEW.sale_status));
 RETURN NEW;
END $$;
CREATE TRIGGER capture_offer_price_history AFTER INSERT OR UPDATE ON offers FOR EACH ROW EXECUTE FUNCTION record_offer_price_snapshot();
CREATE TRIGGER immutable_offer_price_history BEFORE UPDATE OR DELETE ON offer_price_snapshots FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER no_truncate_offer_price_history BEFORE TRUNCATE ON offer_price_snapshots FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
