CREATE TABLE media_asset (
  id uuid PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES identity_principal(id),
  realm varchar(16) NOT NULL,
  owner_session_id uuid NOT NULL REFERENCES auth_session(id),
  scope varchar(24) NOT NULL CHECK(scope IN ('AVATAR','REVIEW','CHAT','PRODUCT','ARTICLE')),
  store_id uuid REFERENCES merchant_store(id),
  storage_provider varchar(32) NOT NULL,
  object_key varchar(240) NOT NULL,
  mime varchar(80) NOT NULL CHECK(mime IN ('image/png','image/jpeg')),
  size_bytes bigint NOT NULL CHECK(size_bytes>0 AND size_bytes<=5242880),
  sha256 varchar(64) NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
  status varchar(24) NOT NULL CHECK(status IN ('UPLOAD_PENDING','UPLOADING','READY','FAILED','DELETE_PENDING','DELETED','EXPIRED')),
  upload_token_hash varchar(64) UNIQUE,
  upload_expires_at timestamptz NOT NULL,
  claim_token uuid,
  lease_expires_at timestamptz,
  error_code varchar(80),
  next_cleanup_at timestamptz NOT NULL,
  cleanup_attempts integer NOT NULL DEFAULT 0,
  cleanup_claim_token uuid,
  cleanup_lease_expires_at timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  UNIQUE(storage_provider,object_key),
  FOREIGN KEY(owner_id,realm) REFERENCES identity_principal(id,realm),
  CHECK((scope='PRODUCT' AND realm='MERCHANT' AND store_id IS NOT NULL) OR (scope<>'PRODUCT' AND store_id IS NULL)),
  CHECK((realm='CONSUMER' AND scope IN ('AVATAR','REVIEW','CHAT')) OR (realm='MERCHANT' AND scope IN ('PRODUCT','CHAT')) OR (realm='ADMIN' AND scope IN ('ARTICLE','CHAT'))),
  CHECK((status='UPLOADING' AND claim_token IS NOT NULL AND lease_expires_at IS NOT NULL) OR (status<>'UPLOADING' AND claim_token IS NULL AND lease_expires_at IS NULL)),
  CHECK(status='UPLOAD_PENDING' OR upload_token_hash IS NULL)
);
CREATE INDEX ix_media_owner ON media_asset(owner_id,realm,created_at DESC);
CREATE INDEX ix_media_recovery ON media_asset(status,next_cleanup_at,lease_expires_at);
COMMENT ON TABLE media_asset IS 'Only provider-neutral resource references and upload control metadata; binary files live outside PostgreSQL';
