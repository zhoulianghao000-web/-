CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE app_user (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status varchar(32) NOT NULL,
  phone_e164 varchar(32),
  display_name varchar(120),
  version bigint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE UNIQUE INDEX ux_app_user_phone_active
  ON app_user(phone_e164)
  WHERE deleted_at IS NULL AND phone_e164 IS NOT NULL;

CREATE TABLE role (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope_type varchar(32) NOT NULL,
  code varchar(120) NOT NULL,
  name varchar(160) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(scope_type, code)
);

CREATE TABLE permission (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code varchar(160) NOT NULL UNIQUE,
  description varchar(500)
);

CREATE TABLE role_permission (
  role_id uuid NOT NULL REFERENCES role(id),
  permission_id uuid NOT NULL REFERENCES permission(id),
  PRIMARY KEY(role_id, permission_id)
);

CREATE TABLE audit_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_type varchar(32) NOT NULL,
  actor_id varchar(120),
  actor_role_snapshot jsonb,
  action varchar(160) NOT NULL,
  object_type varchar(120) NOT NULL,
  object_id varchar(120),
  before_json jsonb,
  after_json jsonb,
  request_id varchar(120),
  correlation_id varchar(120),
  source_ip inet,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE outbox_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aggregate_type varchar(120) NOT NULL,
  aggregate_id varchar(120) NOT NULL,
  event_type varchar(160) NOT NULL,
  event_version integer NOT NULL DEFAULT 1,
  payload jsonb NOT NULL,
  correlation_id varchar(120),
  status varchar(32) NOT NULL DEFAULT 'PENDING',
  attempt_count integer NOT NULL DEFAULT 0,
  available_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_outbox_pending
  ON outbox_event(status, available_at, created_at);

CREATE TABLE operation_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  config_key varchar(160) NOT NULL,
  version bigint NOT NULL,
  value_json jsonb NOT NULL,
  status varchar(32) NOT NULL,
  effective_at timestamptz,
  created_by varchar(120),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(config_key, version)
);
