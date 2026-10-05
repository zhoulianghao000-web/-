CREATE TABLE user_addresses (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app_user(id), recipient varchar(80) NOT NULL,
 phone varchar(32) NOT NULL, province_code varchar(12) NOT NULL, city_code varchar(12),
 district_code varchar(12), detail varchar(500) NOT NULL,
 status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','DELETED')),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0), created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(id,user_id)
);
CREATE TABLE carts (id uuid PRIMARY KEY, user_id uuid NOT NULL UNIQUE REFERENCES app_user(id),version bigint NOT NULL DEFAULT 0 CHECK(version>=0));
CREATE TABLE cart_items (
 id uuid PRIMARY KEY,cart_id uuid NOT NULL REFERENCES carts(id),offer_id uuid NOT NULL REFERENCES offers(id),pet_id uuid REFERENCES pets(id),
 quantity integer NOT NULL CHECK(quantity BETWEEN 1 AND 999),active boolean NOT NULL DEFAULT true,
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_cart_live_offer_pet ON cart_items(cart_id,offer_id,pet_id) NULLS NOT DISTINCT WHERE active;
CREATE TABLE pricing_rule_versions (
 id uuid PRIMARY KEY, code varchar(80) NOT NULL UNIQUE,algorithm_version varchar(80) NOT NULL,
 parameters jsonb NOT NULL,parameters_hash varchar(64) NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO pricing_rule_versions VALUES(gen_random_uuid(),'PRICING_V1_1','LARGEST_REMAINDER_V1','{"quote_ttl_seconds":900,"maximum_items":100}',encode(digest('{"quote_ttl_seconds":900,"maximum_items":100}','sha256'),'hex'),now());
CREATE TABLE shipping_rule_versions (
 id uuid PRIMARY KEY,merchant_id uuid NOT NULL REFERENCES merchant(id),version_no bigint NOT NULL CHECK(version_no>0),
 province_codes jsonb NOT NULL,base_fen bigint NOT NULL CHECK(base_fen BETWEEN 0 AND 1000000000),
 per_kg_fen bigint NOT NULL CHECK(per_kg_fen BETWEEN 0 AND 1000000000),free_threshold_fen bigint CHECK(free_threshold_fen>=0),
 created_by uuid NOT NULL REFERENCES identity_principal(id),created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(merchant_id,version_no)
);
CREATE TABLE membership_plan_versions (
 id uuid PRIMARY KEY,version_code varchar(80) NOT NULL UNIQUE,parameters jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE membership_subscriptions (
 user_id uuid PRIMARY KEY REFERENCES app_user(id),plan_version_id uuid NOT NULL REFERENCES membership_plan_versions(id),
 starts_at timestamptz NOT NULL,expires_at timestamptz NOT NULL,status varchar(16) NOT NULL CHECK(status IN ('ACTIVE','EXPIRED','CANCELLED')),
 version bigint NOT NULL DEFAULT 0,CHECK(expires_at>starts_at)
);
CREATE TABLE coupon_definitions (
 id uuid PRIMARY KEY,version bigint NOT NULL CHECK(version>0),status varchar(16) NOT NULL CHECK(status IN ('DRAFT','PUBLISHED','STOPPED','EXPIRED')),
 parameters jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE user_coupons (
 id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES app_user(id),definition_id uuid NOT NULL REFERENCES coupon_definitions(id),definition_version bigint NOT NULL,scope varchar(16) NOT NULL CHECK(scope IN ('MERCHANT','PLATFORM','SHIPPING')),
 merchant_id uuid REFERENCES merchant(id),amount_fen bigint NOT NULL CHECK(amount_fen>0),threshold_fen bigint NOT NULL CHECK(threshold_fen>=0),
 status varchar(16) NOT NULL CHECK(status IN ('AVAILABLE','RETURNED','RESERVED','USED','EXPIRED','VOID')),
 expires_at timestamptz NOT NULL,version bigint NOT NULL DEFAULT 0,rule_version varchar(80) NOT NULL,
 reserved_order_id uuid,reserved_from_status varchar(16),reservation_expires_at timestamptz,
 CHECK((status='RESERVED')=(reserved_order_id IS NOT NULL AND reserved_from_status IS NOT NULL AND reservation_expires_at IS NOT NULL)),
 CHECK((scope='MERCHANT')=(merchant_id IS NOT NULL))
);
CREATE TABLE pricing_quotes (
 id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES app_user(id),address_id uuid NOT NULL REFERENCES user_addresses(id),
 address_version bigint NOT NULL,address_snapshot jsonb NOT NULL,membership_snapshot jsonb NOT NULL,currency varchar(3) NOT NULL CHECK(currency='CNY'),
 goods_amount_fen bigint NOT NULL CHECK(goods_amount_fen>=0),shipping_amount_fen bigint NOT NULL CHECK(shipping_amount_fen>=0),
 discount_amount_fen bigint NOT NULL CHECK(discount_amount_fen>=0),payable_amount_fen bigint NOT NULL CHECK(payable_amount_fen>=1),
 pricing_rule_version varchar(80) NOT NULL REFERENCES pricing_rule_versions(code),algorithm_version varchar(80) NOT NULL,
 input_hash varchar(64) NOT NULL,snapshot_hash varchar(64) NOT NULL,facts_snapshot jsonb NOT NULL,result_snapshot jsonb NOT NULL,
 status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','CONSUMED','EXPIRED','INVALIDATED')),
 expires_at timestamptz NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),consumed_order_id uuid UNIQUE,consumed_at timestamptz,
 version bigint NOT NULL DEFAULT 0,CHECK(goods_amount_fen+shipping_amount_fen-discount_amount_fen=payable_amount_fen),
 CHECK((status='CONSUMED' AND consumed_order_id IS NOT NULL AND consumed_at IS NOT NULL) OR (status<>'CONSUMED' AND consumed_order_id IS NULL AND consumed_at IS NULL))
);
CREATE INDEX ix_quote_expiry ON pricing_quotes(expires_at) WHERE status='ACTIVE';
CREATE TABLE pricing_quote_items (
 id uuid PRIMARY KEY,quote_id uuid NOT NULL REFERENCES pricing_quotes(id),allocation_key varchar(12) NOT NULL,
 cart_item_id uuid NOT NULL REFERENCES cart_items(id),cart_item_version bigint NOT NULL,offer_id uuid NOT NULL REFERENCES offers(id),offer_version bigint NOT NULL,
 sku_id uuid NOT NULL REFERENCES skus(id),catalog_standard_version_id uuid NOT NULL REFERENCES sku_standard_versions(id),merchant_id uuid NOT NULL REFERENCES merchant(id),
 quantity integer NOT NULL CHECK(quantity>0),unit_price_fen bigint NOT NULL CHECK(unit_price_fen>=0),goods_amount_fen bigint NOT NULL CHECK(goods_amount_fen>=0),
 discount_amount_fen bigint NOT NULL CHECK(discount_amount_fen>=0),payable_amount_fen bigint NOT NULL CHECK(payable_amount_fen>=0),
 UNIQUE(quote_id,allocation_key),CHECK(goods_amount_fen=quantity*unit_price_fen),CHECK(goods_amount_fen-discount_amount_fen=payable_amount_fen)
);
CREATE TABLE pricing_quote_merchant_groups (
 quote_id uuid NOT NULL REFERENCES pricing_quotes(id),merchant_id uuid NOT NULL REFERENCES merchant(id),shipping_rule_id uuid NOT NULL REFERENCES shipping_rule_versions(id),
 shipping_amount_fen bigint NOT NULL CHECK(shipping_amount_fen>=0),shipping_discount_fen bigint NOT NULL CHECK(shipping_discount_fen>=0),
 shipping_payable_fen bigint NOT NULL CHECK(shipping_payable_fen>=0),PRIMARY KEY(quote_id,merchant_id),CHECK(shipping_amount_fen-shipping_discount_fen=shipping_payable_fen)
);
CREATE TABLE pricing_quote_discount_allocations (
 id uuid PRIMARY KEY,quote_id uuid NOT NULL REFERENCES pricing_quotes(id),source_id uuid NOT NULL REFERENCES user_coupons(id),
 scope varchar(16) NOT NULL CHECK(scope IN ('GOODS','SHIPPING')),allocation_key varchar(36) NOT NULL,sequence_no integer NOT NULL,
 eligible_base_fen bigint NOT NULL CHECK(eligible_base_fen>=0),discount_fen bigint NOT NULL CHECK(discount_fen BETWEEN 0 AND eligible_base_fen),
 rule_version varchar(80) NOT NULL,algorithm_version varchar(80) NOT NULL,UNIQUE(quote_id,source_id,allocation_key)
);
CREATE FUNCTION reject_pricing_snapshot_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'pricing evidence is immutable'; END $$;
CREATE TRIGGER immutable_pricing_rules BEFORE UPDATE OR DELETE ON pricing_rule_versions FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER immutable_shipping_rules BEFORE UPDATE OR DELETE ON shipping_rule_versions FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER immutable_quote_items BEFORE UPDATE OR DELETE ON pricing_quote_items FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER immutable_quote_groups BEFORE UPDATE OR DELETE ON pricing_quote_merchant_groups FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER immutable_quote_allocations BEFORE UPDATE OR DELETE ON pricing_quote_discount_allocations FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE FUNCTION protect_quote_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version','consumed_order_id','consumed_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','consumed_order_id','consumed_at']) THEN RAISE EXCEPTION 'quote snapshot is immutable'; END IF;
 IF OLD.status<>'ACTIVE' OR NEW.status NOT IN ('CONSUMED','EXPIRED','INVALIDATED') OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'invalid quote transition'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER quote_snapshot_guard BEFORE UPDATE ON pricing_quotes FOR EACH ROW EXECUTE FUNCTION protect_quote_snapshot();
CREATE TRIGGER quote_no_delete BEFORE DELETE ON pricing_quotes FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
INSERT INTO permission(code,description) VALUES('pricing.shipping.manage','Publish immutable shipping rules after reverify');
CREATE TRIGGER immutable_membership_plan_versions BEFORE UPDATE OR DELETE ON membership_plan_versions FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE FUNCTION protect_coupon_terms() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','version','reserved_order_id','reserved_from_status','reservation_expires_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','reserved_order_id','reserved_from_status','reservation_expires_at']) OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'issued coupon terms are immutable'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER coupon_terms_guard BEFORE UPDATE ON user_coupons FOR EACH ROW EXECUTE FUNCTION protect_coupon_terms();
CREATE FUNCTION protect_coupon_definition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.status<>'DRAFT' AND (to_jsonb(NEW)-'status') IS DISTINCT FROM (to_jsonb(OLD)-'status') THEN RAISE EXCEPTION 'published coupon terms are immutable'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER published_coupon_definition_guard BEFORE UPDATE ON coupon_definitions FOR EACH ROW EXECUTE FUNCTION protect_coupon_definition();
