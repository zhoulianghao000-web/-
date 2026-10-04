CREATE TABLE pet_species (
 id uuid PRIMARY KEY, parent_id uuid REFERENCES pet_species(id),
 category varchar(16) NOT NULL CHECK(category IN ('CAT','DOG','AQUATIC','BIRD','SMALL_PET')),
 name varchar(160) NOT NULL CHECK(length(trim(name))>0),
 status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','RETIRED')),
 UNIQUE(id,category), CHECK(parent_id IS NULL OR parent_id<>id),
 FOREIGN KEY(parent_id,category) REFERENCES pet_species(id,category)
);
CREATE UNIQUE INDEX uq_pet_category_root ON pet_species(category) WHERE parent_id IS NULL;
CREATE TABLE pet_breeds (
 id uuid PRIMARY KEY, species_id uuid NOT NULL REFERENCES pet_species(id), name varchar(160) NOT NULL,
 status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','RETIRED')),
 UNIQUE(id,species_id), UNIQUE(species_id,name)
);
CREATE TABLE allergens (id uuid PRIMARY KEY, name varchar(160) NOT NULL UNIQUE, status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','RETIRED')));
CREATE TABLE pet_life_stage_rule_versions (
 id uuid PRIMARY KEY, species_id uuid NOT NULL REFERENCES pet_species(id), version_no bigint NOT NULL CHECK(version_no>0),
 status varchar(16) NOT NULL CHECK(status IN ('DRAFT','PUBLISHED','RETIRED')),
 source_refs jsonb NOT NULL CHECK(jsonb_typeof(source_refs)='array'), published_at timestamptz,
 UNIQUE(species_id,version_no)
);
CREATE UNIQUE INDEX uq_pet_current_rule ON pet_life_stage_rule_versions(species_id) WHERE status='PUBLISHED';
CREATE TABLE pet_life_stage_definitions (
 id uuid PRIMARY KEY, rule_version_id uuid NOT NULL REFERENCES pet_life_stage_rule_versions(id),
 stage_code varchar(80) NOT NULL, display_name varchar(160) NOT NULL,
 min_age_value integer, max_age_value integer, age_unit varchar(8) NOT NULL CHECK(age_unit IN ('DAY','MONTH','YEAR')),
 is_unknown boolean NOT NULL, UNIQUE(rule_version_id,stage_code),
 CHECK((is_unknown AND min_age_value IS NULL AND max_age_value IS NULL) OR
  (NOT is_unknown AND min_age_value IS NOT NULL AND min_age_value>=0 AND (max_age_value IS NULL OR max_age_value>min_age_value)))
);
CREATE FUNCTION protect_pet_rule() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_TABLE_NAME='pet_life_stage_definitions' THEN
  IF TG_OP='UPDATE' AND NEW.rule_version_id<>OLD.rule_version_id THEN RAISE EXCEPTION 'cannot move pet stage between versions'; END IF;
  PERFORM 1 FROM pet_life_stage_rule_versions WHERE id=COALESCE(NEW.rule_version_id,OLD.rule_version_id) AND status='DRAFT' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'published pet rule is immutable'; END IF;
  IF TG_OP<>'DELETE' AND NOT NEW.is_unknown AND EXISTS(SELECT 1 FROM pet_life_stage_definitions d
    WHERE d.rule_version_id=NEW.rule_version_id AND d.id<>NEW.id AND NOT d.is_unknown
    AND (d.age_unit<>NEW.age_unit OR int8range(d.min_age_value,d.max_age_value,'[)') && int8range(NEW.min_age_value,NEW.max_age_value,'[)'))) THEN
    RAISE EXCEPTION 'overlapping or mixed-unit pet stages';
  END IF;
 ELSE
  IF OLD.status<>'DRAFT' AND (TG_OP='DELETE' OR NEW.species_id<>OLD.species_id OR NEW.version_no<>OLD.version_no
   OR NEW.source_refs<>OLD.source_refs OR NEW.published_at IS DISTINCT FROM OLD.published_at
   OR NOT(OLD.status='PUBLISHED' AND NEW.status='RETIRED')) THEN RAISE EXCEPTION 'published pet rule is immutable'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER immutable_pet_stage BEFORE INSERT OR UPDATE OR DELETE ON pet_life_stage_definitions FOR EACH ROW EXECUTE FUNCTION protect_pet_rule();
CREATE TRIGGER immutable_pet_rule BEFORE UPDATE OR DELETE ON pet_life_stage_rule_versions FOR EACH ROW EXECUTE FUNCTION protect_pet_rule();
CREATE TABLE pets (
 id uuid PRIMARY KEY, owner_user_id uuid NOT NULL REFERENCES app_user(id), name varchar(160) NOT NULL,
 species_id uuid NOT NULL REFERENCES pet_species(id), breed_id uuid,
 birth_date date, age_estimate_months integer CHECK(age_estimate_months BETWEEN 0 AND 2400),
 sex varchar(8) NOT NULL CHECK(sex IN ('MALE','FEMALE','UNKNOWN')),
 neutered_status varchar(8) NOT NULL CHECK(neutered_status IN ('YES','NO','UNKNOWN')),
 avoidance_notes jsonb NOT NULL DEFAULT '[]' CHECK(jsonb_typeof(avoidance_notes)='array'),
 current_weight_g bigint CHECK(current_weight_g BETWEEN 1 AND 100000000),
 status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','DELETED')),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0), created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(breed_id,species_id) REFERENCES pet_breeds(id,species_id),
 CHECK(birth_date IS NULL OR age_estimate_months IS NULL)
);
CREATE INDEX ix_pets_owner ON pets(owner_user_id,id) WHERE status='ACTIVE';
CREATE TABLE pet_allergens (
 pet_id uuid NOT NULL REFERENCES pets(id), allergen_id uuid NOT NULL REFERENCES allergens(id),
 status varchar(8) NOT NULL CHECK(status IN ('YES','NO','UNKNOWN')),
 source varchar(24) NOT NULL CHECK(source IN ('OWNER_OBSERVATION','VET_DIAGNOSIS')), note varchar(2000), PRIMARY KEY(pet_id,allergen_id)
);
CREATE TABLE pet_weight_records (
 id uuid PRIMARY KEY, pet_id uuid NOT NULL REFERENCES pets(id), weight_g bigint NOT NULL CHECK(weight_g BETWEEN 1 AND 100000000),
 recorded_on date NOT NULL, source varchar(24) NOT NULL CHECK(source IN ('OWNER_OBSERVATION','VET_DIAGNOSIS')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pet_weight_history ON pet_weight_records(pet_id,recorded_on DESC,created_at DESC,id);
INSERT INTO permission(code,description) VALUES ('pet.taxonomy.read','Read species and sourced lifecycle rules'),('pet.taxonomy.write','Manage pet taxonomy with fresh reverify');
-- Only five structural roots; no invented veterinary thresholds, breeds or allergens.
INSERT INTO pet_species(id,category,name) VALUES
 ('10000000-0000-4000-8000-000000000001','CAT','猫'),
 ('10000000-0000-4000-8000-000000000002','DOG','狗'),
 ('10000000-0000-4000-8000-000000000003','AQUATIC','水族 / 水宠'),
 ('10000000-0000-4000-8000-000000000004','BIRD','鸟'),
 ('10000000-0000-4000-8000-000000000005','SMALL_PET','小宠');
INSERT INTO pet_life_stage_rule_versions(id,species_id,version_no,status,source_refs)
 SELECT md5(id::text||':unknown-rule')::uuid,id,1,'DRAFT','[]' FROM pet_species;
INSERT INTO pet_life_stage_definitions(id,rule_version_id,stage_code,display_name,age_unit,is_unknown)
 SELECT md5(id::text||':unknown-stage')::uuid,md5(id::text||':unknown-rule')::uuid,'UNKNOWN','信息不足','MONTH',true FROM pet_species;
UPDATE pet_life_stage_rule_versions SET status='PUBLISHED',published_at=now();
