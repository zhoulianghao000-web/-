-- Search is a projection. These foundation rows are owned by PostgreSQL and will
-- be replaced/extended by the catalog domain in M3, never by OpenSearch reads.
CREATE TABLE catalog_search_source (
 sku_id uuid PRIMARY KEY, spu_id uuid NOT NULL, revision bigint NOT NULL CHECK(revision>0),
 document jsonb NOT NULL, deleted boolean NOT NULL DEFAULT false,
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE search_index_version (
 index_name varchar(160) PRIMARY KEY, schema_version integer NOT NULL,
 status varchar(24) NOT NULL CHECK(status IN ('BUILDING','ACTIVE','RETIRED')),
 created_at timestamptz NOT NULL DEFAULT now(), activated_at timestamptz
);
CREATE UNIQUE INDEX ux_search_one_active ON search_index_version(status) WHERE status='ACTIVE';
CREATE TABLE search_sync_task (
 source_id uuid NOT NULL REFERENCES catalog_search_source(sku_id), target_index varchar(160) NOT NULL REFERENCES search_index_version(index_name),
 event_id uuid, desired_revision bigint NOT NULL CHECK(desired_revision>0), completed_revision bigint NOT NULL DEFAULT 0,
 status varchar(24) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','SYNCING','APPLIED','FAILED_RETRYABLE','DEAD')),
 attempt_count integer NOT NULL DEFAULT 0, available_at timestamptz NOT NULL DEFAULT now(),
 claim_token uuid, lease_expires_at timestamptz, last_error_code varchar(160),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(source_id,target_index),
 CHECK((status='SYNCING' AND claim_token IS NOT NULL AND lease_expires_at IS NOT NULL)
   OR(status<>'SYNCING' AND claim_token IS NULL AND lease_expires_at IS NULL))
);
CREATE INDEX ix_search_sync_claim ON search_sync_task(available_at,source_id) WHERE status IN ('PENDING','FAILED_RETRYABLE');
CREATE TABLE search_rebuild_job (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_id uuid UNIQUE, target_index varchar(160) NOT NULL UNIQUE,
 status varchar(24) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','BUILDING','FAILED_RETRYABLE','COMPLETED','DEAD')),
 attempt_count integer NOT NULL DEFAULT 0, available_at timestamptz NOT NULL DEFAULT now(),
 claim_token uuid, lease_expires_at timestamptz, last_error_code varchar(160),
 validated_count bigint, source_digest varchar(64), completed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((status='BUILDING' AND claim_token IS NOT NULL AND lease_expires_at IS NOT NULL)
   OR(status<>'BUILDING' AND claim_token IS NULL AND lease_expires_at IS NULL))
);
CREATE UNIQUE INDEX ux_search_one_rebuild ON search_rebuild_job((true)) WHERE status IN ('PENDING','BUILDING','FAILED_RETRYABLE');
CREATE TABLE search_admin_command (
 principal_id uuid NOT NULL REFERENCES identity_principal(id), idempotency_key varchar(128) NOT NULL,
 action varchar(80) NOT NULL, payload_hash varchar(64) NOT NULL, result_json jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(principal_id,idempotency_key)
);
INSERT INTO permission(code,description) VALUES
 ('search.read','Inspect redacted search health, versions and synchronization jobs'),
 ('search.manage','Rebuild, reconcile and retry derived search data after action-bound reverify and audit');
