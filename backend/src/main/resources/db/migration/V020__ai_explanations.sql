-- AI owns explanations and quota accounting, never commerce or deterministic fit facts.
CREATE TABLE ai_policy_versions (
 id uuid PRIMARY KEY, ordinary_daily_limit integer NOT NULL CHECK(ordinary_daily_limit BETWEEN 0 AND 1000),
 member_daily_ceiling integer NOT NULL CHECK(member_daily_ceiling BETWEEN 0 AND 10000),
 retention_days integer NOT NULL CHECK(retention_days BETWEEN 1 AND 90),
 lease_seconds integer NOT NULL CHECK(lease_seconds BETWEEN 10 AND 120), enabled boolean NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER ai_policy_immutable BEFORE UPDATE OR DELETE ON ai_policy_versions FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE ai_prompt_versions (id uuid PRIMARY KEY, instruction varchar(2000) NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TRIGGER ai_prompt_immutable BEFORE UPDATE OR DELETE ON ai_prompt_versions FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE ai_evaluations (id uuid PRIMARY KEY, prompt_id uuid NOT NULL REFERENCES ai_prompt_versions(id), passed boolean NOT NULL, cases jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TRIGGER ai_evaluation_immutable BEFORE UPDATE OR DELETE ON ai_evaluations FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
INSERT INTO ai_policy_versions VALUES ('55000000-0000-4000-8000-000000000001',3,200,30,60,true,now());
INSERT INTO ai_prompt_versions VALUES ('55000000-0000-4000-8000-000000000002','Explain only verified evidence. Return JSON with evidence_ids. Never invent a fact or execute tools.',now());
CREATE TABLE ai_release (singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), active_prompt_id uuid NOT NULL REFERENCES ai_prompt_versions(id), staged_prompt_id uuid REFERENCES ai_prompt_versions(id), staged_percent integer NOT NULL DEFAULT 0 CHECK(staged_percent BETWEEN 0 AND 99), policy_id uuid NOT NULL REFERENCES ai_policy_versions(id), version bigint NOT NULL DEFAULT 0);
INSERT INTO ai_release VALUES (true,'55000000-0000-4000-8000-000000000002',NULL,0,'55000000-0000-4000-8000-000000000001',0);
CREATE TABLE ai_release_history (id uuid PRIMARY KEY, active_prompt_id uuid NOT NULL REFERENCES ai_prompt_versions(id), staged_prompt_id uuid REFERENCES ai_prompt_versions(id), staged_percent integer NOT NULL, policy_id uuid NOT NULL REFERENCES ai_policy_versions(id), version bigint NOT NULL UNIQUE, action varchar(24) NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
INSERT INTO ai_release_history SELECT gen_random_uuid(),active_prompt_id,staged_prompt_id,staged_percent,policy_id,version,'INITIAL',now() FROM ai_release;
CREATE TRIGGER ai_release_history_immutable BEFORE UPDATE OR DELETE ON ai_release_history FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE ai_preferences (user_id uuid PRIMARY KEY REFERENCES app_user(id), personalization_enabled boolean NOT NULL DEFAULT false, version bigint NOT NULL DEFAULT 0);
CREATE TABLE ai_conversations (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app_user(id), pet_id uuid REFERENCES pets(id), status varchar(12) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','DELETED','EXPIRED')), expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX ai_conversations_owner ON ai_conversations(user_id,id);
CREATE TABLE ai_requests (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app_user(id), conversation_id uuid NOT NULL REFERENCES ai_conversations(id), idempotency_key varchar(128) NOT NULL, payload_hash varchar(128) NOT NULL, preference_version bigint NOT NULL, prompt_id uuid NOT NULL REFERENCES ai_prompt_versions(id), policy_id uuid NOT NULL REFERENCES ai_policy_versions(id), created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(user_id,idempotency_key));
CREATE TABLE ai_quota_reservations (id uuid PRIMARY KEY REFERENCES ai_requests(id), user_id uuid NOT NULL REFERENCES app_user(id), quota_policy_version uuid NOT NULL REFERENCES ai_policy_versions(id), quota_bucket_id varchar(96) NOT NULL, units integer NOT NULL DEFAULT 1 CHECK(units=1), status varchar(12) NOT NULL CHECK(status IN ('RESERVED','CONSUMED','RELEASED')), lease_expires_at timestamptz NOT NULL, assistant_message_id uuid, version bigint NOT NULL DEFAULT 0);
CREATE INDEX ai_quota_bucket ON ai_quota_reservations(user_id,quota_bucket_id,status);
CREATE TABLE ai_quota_ledger (id uuid PRIMARY KEY, reservation_id uuid NOT NULL REFERENCES ai_quota_reservations(id), user_id uuid NOT NULL REFERENCES app_user(id), status varchar(12) NOT NULL CHECK(status IN ('RESERVED','CONSUMED','RELEASED')), units integer NOT NULL CHECK(units=1), created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(reservation_id,status));
CREATE TRIGGER ai_ledger_immutable BEFORE UPDATE OR DELETE ON ai_quota_ledger FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE ai_messages (id uuid PRIMARY KEY REFERENCES ai_requests(id), conversation_id uuid NOT NULL REFERENCES ai_conversations(id), user_text_ciphertext text, result_ciphertext text, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE ai_profile_proposals (id uuid PRIMARY KEY, request_id uuid NOT NULL UNIQUE REFERENCES ai_requests(id), user_id uuid NOT NULL REFERENCES app_user(id), pet_id uuid REFERENCES pets(id), pet_version bigint NOT NULL, before_value varchar(8), proposed_value varchar(8) CHECK(proposed_value IN ('YES','NO')), status varchar(12) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','ACCEPTED','REJECTED','EXPIRED')), expires_at timestamptz NOT NULL, version bigint NOT NULL DEFAULT 0);
-- Paid plan quantities are per purchased month/year, never silently reset daily or on plan changes.
CREATE TABLE ai_membership_quota_grants (membership_order_id uuid PRIMARY KEY REFERENCES membership_orders(id), user_id uuid NOT NULL REFERENCES app_user(id), starts_at timestamptz NOT NULL, expires_at timestamptz NOT NULL, units integer NOT NULL CHECK(units>=0), CHECK(expires_at>starts_at));
CREATE TRIGGER ai_member_grant_immutable BEFORE UPDATE OR DELETE ON ai_membership_quota_grants FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
DO $$ DECLARE o record; last_user uuid; previous_end timestamptz; period_start timestamptz; period_end timestamptz; BEGIN
 FOR o IN SELECT * FROM membership_orders WHERE status='PAID' ORDER BY user_id,paid_at,id LOOP
  IF last_user IS DISTINCT FROM o.user_id THEN previous_end:=NULL; END IF;
  period_start:=greatest(o.paid_at,coalesce(previous_end,o.paid_at));
  period_end:=((period_start AT TIME ZONE 'UTC')+CASE WHEN o.plan_snapshot->>'term'='YEAR' THEN interval '1 year' ELSE interval '1 month' END) AT TIME ZONE 'UTC';
  INSERT INTO ai_membership_quota_grants VALUES(o.id,o.user_id,period_start,period_end,(o.plan_snapshot->>'ai_quota')::integer);
  previous_end:=period_end;last_user:=o.user_id;
 END LOOP;
END $$;
INSERT INTO permission(code,description) VALUES ('ai.read','Read AI configurations and evaluation evidence'),('ai.manage','Publish versioned AI configuration with reverify');
COMMENT ON TABLE ai_messages IS 'Encrypted user question and validated grounded answer; cleared and expired conversations scrub both ciphertexts. No model prose is trusted as a business fact.';
