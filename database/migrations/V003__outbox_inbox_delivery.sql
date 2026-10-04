ALTER TABLE outbox_event
  ADD COLUMN root_event_id uuid,
  ADD COLUMN transport_kind varchar(24) NOT NULL DEFAULT 'EVENT',
  ADD COLUMN delivery_attempt integer NOT NULL DEFAULT 1,
  ADD COLUMN generation integer NOT NULL DEFAULT 0,
  ADD COLUMN claim_token uuid,
  ADD COLUMN claimed_by varchar(160),
  ADD COLUMN lease_expires_at timestamptz,
  ADD COLUMN last_error_code varchar(160),
  ADD COLUMN last_error_at timestamptz,
  ADD COLUMN dead_at timestamptz,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
UPDATE outbox_event SET root_event_id=id;
ALTER TABLE outbox_event ALTER COLUMN root_event_id SET NOT NULL;
ALTER TABLE outbox_event ADD CONSTRAINT ck_outbox_status
  CHECK(status IN ('PENDING','PUBLISHING','PUBLISHED','FAILED_RETRYABLE','DEAD'));
ALTER TABLE outbox_event ADD CONSTRAINT ck_outbox_kind CHECK(transport_kind IN ('EVENT','RETRY','DEAD_LETTER'));
ALTER TABLE outbox_event ADD CONSTRAINT ck_outbox_attempts CHECK(attempt_count>=0 AND delivery_attempt>0 AND generation>=0);
ALTER TABLE outbox_event ADD CONSTRAINT ck_outbox_claim CHECK(
  (status='PUBLISHING' AND claim_token IS NOT NULL AND claimed_by IS NOT NULL AND lease_expires_at IS NOT NULL)
  OR (status<>'PUBLISHING' AND claim_token IS NULL AND claimed_by IS NULL AND lease_expires_at IS NULL));
CREATE INDEX ix_outbox_claim ON outbox_event(available_at,created_at,id)
  WHERE status IN ('PENDING','FAILED_RETRYABLE');
CREATE INDEX ix_outbox_lease ON outbox_event(lease_expires_at) WHERE status='PUBLISHING';
CREATE INDEX ix_outbox_root ON outbox_event(root_event_id);

CREATE TABLE processed_event (
  consumer varchar(120) NOT NULL, event_id uuid NOT NULL,
  status varchar(24) NOT NULL CHECK(status IN ('PROCESSED','FAILED_RETRYABLE','DEAD')),
  attempt_count integer NOT NULL DEFAULT 0, generation integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz, last_error_code varchar(160), completed_at timestamptz,
  payload_hash varchar(64) NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(consumer,event_id), CHECK(attempt_count>=0 AND generation>=0)
);
ALTER TABLE otp_challenge ADD COLUMN delivery_secret_ciphertext text;
CREATE TABLE sms_delivery (
  id uuid PRIMARY KEY, event_id uuid NOT NULL UNIQUE, challenge_id uuid NOT NULL UNIQUE REFERENCES otp_challenge(id),
  status varchar(24) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','SENDING','DELIVERED','FAILED_RETRYABLE','DEAD','SKIPPED')),
  attempt_count integer NOT NULL DEFAULT 0, available_at timestamptz NOT NULL DEFAULT now(),
  claim_token uuid, claimed_by varchar(160), lease_expires_at timestamptz,
  last_error_code varchar(160), delivered_at timestamptz, dead_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK((status='SENDING' AND claim_token IS NOT NULL AND claimed_by IS NOT NULL AND lease_expires_at IS NOT NULL)
    OR(status<>'SENDING' AND claim_token IS NULL AND claimed_by IS NULL AND lease_expires_at IS NULL))
);
CREATE INDEX ix_sms_delivery_claim ON sms_delivery(available_at,id) WHERE status IN ('PENDING','FAILED_RETRYABLE');
CREATE TABLE outbox_replay_command (
  principal_id uuid NOT NULL REFERENCES identity_principal(id), idempotency_key varchar(128) NOT NULL,
  event_id uuid NOT NULL REFERENCES outbox_event(id), payload_hash varchar(64) NOT NULL,
  generation integer NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(principal_id,idempotency_key)
);
INSERT INTO permission(code,description) VALUES
 ('outbox.read','Read delivery backlog, redacted failures and metrics'),
 ('outbox.replay','Replay dead delivery after reverify and audit');
