-- Nearby is a public projection of existing owned stores, never a new merchant identity.
CREATE TABLE nearby_store_profile (
 store_id uuid PRIMARY KEY REFERENCES merchant_store(id), city varchar(80) NOT NULL,
 category varchar(16) NOT NULL CHECK(category IN ('PET_STORE','VET','GROOMING','BOARDING')),
 address varchar(500) NOT NULL, phone varchar(32) NOT NULL, business_hours varchar(240) NOT NULL,
 longitude numeric(10,6) NOT NULL CHECK(longitude BETWEEN -180 AND 180),
 latitude numeric(9,6) NOT NULL CHECK(latitude BETWEEN -90 AND 90),
 coordinate_system varchar(8) NOT NULL DEFAULT 'WGS84' CHECK(coordinate_system='WGS84'),
 services jsonb NOT NULL CHECK(jsonb_typeof(services)='array'),
 source varchar(24) NOT NULL DEFAULT 'MERCHANT_SUBMITTED' CHECK(source='MERCHANT_SUBMITTED'),
 publication_status varchar(16) NOT NULL DEFAULT 'DRAFT' CHECK(publication_status IN ('DRAFT','PUBLISHED','HIDDEN')),
 claim_status varchar(16) NOT NULL DEFAULT 'UNREVIEWED' CHECK(claim_status IN ('UNREVIEWED','VERIFIED','REJECTED')),
 pawday_certified boolean NOT NULL DEFAULT false, version bigint NOT NULL DEFAULT 0,
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(NOT pawday_certified OR claim_status='VERIFIED'),
 CHECK(publication_status<>'PUBLISHED' OR claim_status='VERIFIED')
);
CREATE INDEX nearby_city_category ON nearby_store_profile(city,category) WHERE publication_status='PUBLISHED';
CREATE TABLE nearby_moderation_history (
 id uuid PRIMARY KEY, store_id uuid NOT NULL REFERENCES merchant_store(id),
 principal_id uuid NOT NULL REFERENCES identity_principal(id), version bigint NOT NULL,
 publication_status varchar(16) NOT NULL, claim_status varchar(16) NOT NULL,
 pawday_certified boolean NOT NULL, reason varchar(500) NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(store_id,version)
);
CREATE TRIGGER nearby_history_immutable BEFORE UPDATE OR DELETE ON nearby_moderation_history FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
INSERT INTO permission(code,description) VALUES
 ('store.nearby.write','Edit current authorized store nearby profile; changes require publication review'),
 ('nearby.read','Read submitted store profiles for platform review'),
 ('nearby.moderate','Review claim evidence, certify and publish or hide nearby store after reverify');
COMMENT ON TABLE nearby_store_profile IS 'GPS WGS84 only; public source is merchant submitted and reviewed, not AMap POI ingestion. User locations are never persisted.';
