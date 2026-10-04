CREATE TABLE brands (
 id uuid PRIMARY KEY, name varchar(160) NOT NULL UNIQUE, source_ref text NOT NULL,
 status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','RETIRED'))
);
CREATE TABLE spus (
 id uuid PRIMARY KEY, brand_id uuid NOT NULL REFERENCES brands(id), name varchar(160) NOT NULL,
 pet_category varchar(16) NOT NULL CHECK(pet_category IN ('CAT','DOG','AQUATIC','BIRD','SMALL_PET')),
 category varchar(80) NOT NULL, status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','RETIRED')),
 UNIQUE(brand_id,name)
);
CREATE TABLE skus (
 id uuid PRIMARY KEY, spu_id uuid NOT NULL REFERENCES spus(id), sku_code varchar(80) NOT NULL UNIQUE,
 barcode varchar(80) UNIQUE, weight_g bigint NOT NULL CHECK(weight_g>0 AND weight_g<=100000000),
 package_unit varchar(40) NOT NULL, status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','RETIRED')),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0)
);
CREATE TABLE sku_standard_versions (
 id uuid PRIMARY KEY, sku_id uuid NOT NULL REFERENCES skus(id), version_no bigint NOT NULL CHECK(version_no>0),
 status varchar(16) NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','PUBLISHED','RETIRED')),
 ingredients jsonb NOT NULL CHECK(jsonb_typeof(ingredients)='array'), nutrients jsonb NOT NULL CHECK(jsonb_typeof(nutrients)='array'),
 allergens_known boolean NOT NULL, life_stage_ids jsonb NOT NULL CHECK(jsonb_typeof(life_stage_ids)='array'),
 source_refs jsonb NOT NULL CHECK(jsonb_typeof(source_refs)='array' AND jsonb_array_length(source_refs)>0),
 source_updated_on date NOT NULL, created_by uuid NOT NULL REFERENCES identity_principal(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), published_at timestamptz,
 UNIQUE(sku_id,version_no)
);
CREATE UNIQUE INDEX sku_one_published ON sku_standard_versions(sku_id) WHERE status='PUBLISHED';
CREATE TABLE sku_allergens (
 standard_version_id uuid NOT NULL REFERENCES sku_standard_versions(id), allergen_id uuid NOT NULL REFERENCES allergens(id),
 PRIMARY KEY(standard_version_id,allergen_id)
);
CREATE FUNCTION catalog_immutable_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.status<>'DRAFT' THEN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'published standard is immutable'; END IF;
  IF (to_jsonb(NEW)-'status') IS DISTINCT FROM (to_jsonb(OLD)-'status') OR NOT(OLD.status='PUBLISHED' AND NEW.status='RETIRED') THEN
   RAISE EXCEPTION 'published standard is immutable';
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER catalog_version_guard BEFORE UPDATE OR DELETE ON sku_standard_versions FOR EACH ROW EXECUTE FUNCTION catalog_immutable_version();
CREATE FUNCTION catalog_immutable_allergen() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE state text;
BEGIN
 IF TG_OP<>'INSERT' THEN
  SELECT status INTO state FROM sku_standard_versions WHERE id=OLD.standard_version_id FOR UPDATE;
  IF state<>'DRAFT' THEN RAISE EXCEPTION 'published allergens are immutable'; END IF;
 END IF;
 IF TG_OP<>'DELETE' THEN
  SELECT status INTO state FROM sku_standard_versions WHERE id=NEW.standard_version_id FOR UPDATE;
  IF state<>'DRAFT' THEN RAISE EXCEPTION 'published allergens are immutable'; END IF;
  RETURN NEW;
 END IF;
 RETURN OLD;
END $$;
CREATE TRIGGER catalog_allergen_guard BEFORE INSERT OR UPDATE OR DELETE ON sku_allergens FOR EACH ROW EXECUTE FUNCTION catalog_immutable_allergen();
CREATE TABLE catalog_change_requests (
 id uuid PRIMARY KEY, merchant_id uuid NOT NULL REFERENCES merchant(id), submitted_by uuid NOT NULL REFERENCES identity_principal(id),
 sku_id uuid NOT NULL REFERENCES skus(id), base_sku_version bigint NOT NULL, proposal jsonb NOT NULL,
 reason text NOT NULL, status varchar(16) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','REJECTED')),
 version bigint NOT NULL DEFAULT 0, result_version_id uuid REFERENCES sku_standard_versions(id), created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE catalog_review_records (
 id uuid PRIMARY KEY, request_id uuid NOT NULL UNIQUE REFERENCES catalog_change_requests(id), reviewer_id uuid NOT NULL REFERENCES identity_principal(id),
 decision varchar(16) NOT NULL CHECK(decision IN ('APPROVED','REJECTED')), reason text NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE catalog_import_batches (
 id uuid PRIMARY KEY, created_by uuid NOT NULL REFERENCES identity_principal(id), format varchar(8) NOT NULL CHECK(format IN ('CSV','XLSX')),
 status varchar(16) NOT NULL CHECK(status IN ('PREVIEW','CONFIRMED','CANCELLED')), version bigint NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE catalog_import_rows (
 batch_id uuid NOT NULL REFERENCES catalog_import_batches(id), row_no integer NOT NULL, payload jsonb NOT NULL,
 error_codes jsonb NOT NULL, base_sku_version bigint, result_version_id uuid REFERENCES sku_standard_versions(id),
 PRIMARY KEY(batch_id,row_no)
);
INSERT INTO permission(code,description) VALUES
 ('catalog.standard.read','Read platform standards'),('catalog.standard.write','Maintain platform standards'),
 ('catalog.request.write','Submit merchant corrections') ON CONFLICT(code) DO NOTHING;
