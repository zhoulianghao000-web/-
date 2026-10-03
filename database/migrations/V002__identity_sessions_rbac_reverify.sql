CREATE TABLE merchant (
  id uuid PRIMARY KEY, name varchar(160) NOT NULL,
  status varchar(32) NOT NULL CHECK(status IN ('ACTIVE','SUSPENDED'))
);
CREATE TABLE merchant_store (
  id uuid PRIMARY KEY, merchant_id uuid NOT NULL REFERENCES merchant(id),
  name varchar(160) NOT NULL, UNIQUE(id, merchant_id)
);
CREATE TABLE identity_principal (
  id uuid PRIMARY KEY, realm varchar(16) NOT NULL CHECK(realm IN ('CONSUMER','MERCHANT','ADMIN')),
  user_id uuid REFERENCES app_user(id), merchant_id uuid REFERENCES merchant(id),
  login_name varchar(160), password_hash varchar(200),
  mfa_secret_ciphertext text, last_totp_step bigint NOT NULL DEFAULT -1,
  status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','DISABLED')),
  UNIQUE(realm,login_name), UNIQUE(user_id), UNIQUE(id,realm), UNIQUE(id,merchant_id),
  CHECK((realm='CONSUMER' AND user_id IS NOT NULL AND merchant_id IS NULL AND password_hash IS NULL)
    OR (realm='MERCHANT' AND user_id IS NULL AND merchant_id IS NOT NULL AND password_hash IS NOT NULL)
    OR (realm='ADMIN' AND user_id IS NULL AND merchant_id IS NULL AND password_hash IS NOT NULL AND mfa_secret_ciphertext IS NOT NULL))
);
ALTER TABLE role ADD CONSTRAINT uq_role_scope UNIQUE(id,scope_type);
ALTER TABLE role ADD CONSTRAINT ck_role_scope CHECK(scope_type IN ('CONSUMER','MERCHANT','ADMIN'));
CREATE TABLE principal_role (
  principal_id uuid NOT NULL, role_id uuid NOT NULL, realm varchar(16) NOT NULL,
  PRIMARY KEY(principal_id,role_id),
  FOREIGN KEY(principal_id,realm) REFERENCES identity_principal(id,realm),
  FOREIGN KEY(role_id,realm) REFERENCES role(id,scope_type)
);
CREATE TABLE principal_store_scope (
  principal_id uuid NOT NULL, merchant_id uuid NOT NULL, store_id uuid NOT NULL,
  PRIMARY KEY(principal_id,store_id),
  FOREIGN KEY(principal_id,merchant_id) REFERENCES identity_principal(id,merchant_id),
  FOREIGN KEY(store_id,merchant_id) REFERENCES merchant_store(id,merchant_id)
);
CREATE TABLE auth_session (
  id uuid PRIMARY KEY, principal_id uuid NOT NULL REFERENCES identity_principal(id),
  access_token_hash varchar(64) NOT NULL UNIQUE, device_id varchar(128) NOT NULL,
  expires_at timestamptz NOT NULL, refresh_expires_at timestamptz NOT NULL,
  revoked_at timestamptz, version bigint NOT NULL DEFAULT 0, created_at timestamptz NOT NULL,
  CHECK(refresh_expires_at>=expires_at)
);
CREATE INDEX ix_auth_session_principal ON auth_session(principal_id);
CREATE TABLE auth_refresh_token (
  token_hash varchar(64) PRIMARY KEY, session_id uuid NOT NULL REFERENCES auth_session(id),
  status varchar(16) NOT NULL CHECK(status IN ('ACTIVE','CONSUMED','REVOKED')),
  created_at timestamptz NOT NULL, consumed_at timestamptz
);
CREATE UNIQUE INDEX uq_active_refresh ON auth_refresh_token(session_id) WHERE status='ACTIVE';
CREATE TABLE otp_challenge (
  id uuid PRIMARY KEY, phone_e164 varchar(32) NOT NULL,
  purpose varchar(16) NOT NULL CHECK(purpose IN ('LOGIN','REVERIFY')),
  session_id uuid REFERENCES auth_session(id), code_hash varchar(64) NOT NULL,
  attempts integer NOT NULL DEFAULT 0, expires_at timestamptz NOT NULL,
  consumed_at timestamptz, created_at timestamptz NOT NULL,
  CHECK((purpose='LOGIN' AND session_id IS NULL) OR (purpose='REVERIFY' AND session_id IS NOT NULL))
);
CREATE INDEX ix_otp_latest ON otp_challenge(phone_e164,purpose,created_at DESC);
CREATE TABLE auth_rate_bucket (
  subject_hash varchar(64) PRIMARY KEY, window_start timestamptz NOT NULL,
  attempt_count integer NOT NULL CHECK(attempt_count>0)
);
CREATE TABLE reverify_grant (
  token_hash varchar(64) PRIMARY KEY, session_id uuid NOT NULL REFERENCES auth_session(id),
  action varchar(160) NOT NULL, expires_at timestamptz NOT NULL, used_at timestamptz,
  created_at timestamptz NOT NULL
);
CREATE TABLE identity_command (
  principal_id uuid NOT NULL REFERENCES identity_principal(id), action varchar(160) NOT NULL,
  idempotency_key varchar(128) NOT NULL, payload_hash varchar(64) NOT NULL,
  result_json jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(principal_id,action,idempotency_key)
);
ALTER TABLE audit_event ADD COLUMN session_id uuid REFERENCES auth_session(id);
ALTER TABLE role ADD COLUMN version bigint NOT NULL DEFAULT 0;
CREATE FUNCTION reject_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'audit_event is append-only'; END $$;
CREATE TRIGGER audit_event_immutable BEFORE UPDATE OR DELETE ON audit_event
  FOR EACH ROW EXECUTE FUNCTION reject_audit_mutation();
CREATE TRIGGER audit_event_no_truncate BEFORE TRUNCATE ON audit_event
  FOR EACH STATEMENT EXECUTE FUNCTION reject_audit_mutation();

INSERT INTO permission(code,description) VALUES
 ('store.read','Read stores within staff store scope'),
 ('access.role.read','Read platform role definitions'),
 ('access.role.write','Create or edit platform roles after reverify'),
 ('audit.read','Read redacted audit records');
