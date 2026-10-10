-- One transactional counter, not a sequence: rolled-back facts leave no gaps and
-- concurrent commits cannot publish a watermark ahead of an uncommitted fact.
CREATE TABLE privacy_journal_head (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 journal_id uuid NOT NULL DEFAULT gen_random_uuid(), installed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 last_sequence bigint NOT NULL DEFAULT 0 CHECK(last_sequence>=0)
);
INSERT INTO privacy_journal_head(singleton) VALUES(true);
CREATE TABLE privacy_journal (
 sequence bigint PRIMARY KEY CHECK(sequence>0),
 kind varchar(40) NOT NULL CHECK(kind IN ('AI_CONVERSATION_DELETE','AI_PERSONALIZATION_REVOKE','MEDIA_DELETE')),
 subject_id uuid NOT NULL, reason_code varchar(32) NOT NULL,
 effective_at timestamptz NOT NULL, retention_deadline timestamptz
);
CREATE TRIGGER privacy_journal_immutable BEFORE UPDATE OR DELETE ON privacy_journal FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER privacy_journal_no_truncate BEFORE TRUNCATE ON privacy_journal FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE FUNCTION append_privacy_fact(action text, subject uuid, reason text, deadline timestamptz DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE position bigint; BEGIN
 UPDATE privacy_journal_head SET last_sequence=last_sequence+1 WHERE singleton RETURNING last_sequence INTO position;
 INSERT INTO privacy_journal VALUES(position,action,subject,reason,clock_timestamp(),deadline);
END $$;
CREATE FUNCTION capture_privacy_fact() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_TABLE_NAME='ai_preferences' THEN
  IF OLD.personalization_enabled AND NOT NEW.personalization_enabled THEN
   PERFORM append_privacy_fact('AI_PERSONALIZATION_REVOKE',NEW.user_id,'CONSENT_REVOKED');
  END IF;
 ELSIF TG_TABLE_NAME='ai_conversations' THEN
  IF OLD.status='ACTIVE' AND NEW.status IN ('DELETED','EXPIRED') THEN
   PERFORM append_privacy_fact('AI_CONVERSATION_DELETE',NEW.id,CASE WHEN NEW.status='EXPIRED' THEN 'RETENTION_EXPIRED' ELSE 'USER_DELETED' END,NEW.expires_at);
  END IF;
 ELSE
  IF OLD.status NOT IN ('DELETE_PENDING','DELETED','FAILED','EXPIRED') AND NEW.status IN ('DELETE_PENDING','DELETED','FAILED','EXPIRED') THEN
   PERFORM append_privacy_fact('MEDIA_DELETE',NEW.id,CASE WHEN NEW.status IN ('FAILED','EXPIRED') THEN 'UPLOAD_DISCARDED' ELSE 'USER_DELETED' END);
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER ai_privacy_capture AFTER UPDATE ON ai_conversations FOR EACH ROW EXECUTE FUNCTION capture_privacy_fact();
CREATE TRIGGER ai_consent_capture AFTER UPDATE ON ai_preferences FOR EACH ROW EXECUTE FUNCTION capture_privacy_fact();
CREATE TRIGGER media_privacy_capture AFTER UPDATE ON media_asset FOR EACH ROW EXECUTE FUNCTION capture_privacy_fact();
-- Conservative migration-time baseline; unavailable pre-migration history is
-- not claimed as independently captured. Account deletion is not supported here.
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT id,status,expires_at FROM ai_conversations WHERE status<>'ACTIVE' ORDER BY id LOOP
  PERFORM append_privacy_fact('AI_CONVERSATION_DELETE',r.id,'MIGRATION_BASELINE',r.expires_at);
 END LOOP;
 FOR r IN SELECT user_id FROM ai_preferences WHERE NOT personalization_enabled ORDER BY user_id LOOP
  PERFORM append_privacy_fact('AI_PERSONALIZATION_REVOKE',r.user_id,'MIGRATION_BASELINE');
 END LOOP;
 FOR r IN SELECT id FROM media_asset WHERE status IN ('DELETE_PENDING','DELETED','FAILED','EXPIRED') ORDER BY id LOOP
  PERFORM append_privacy_fact('MEDIA_DELETE',r.id,'MIGRATION_BASELINE');
 END LOOP;
END $$;
CREATE TABLE privacy_export_state (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 exported_sequence bigint NOT NULL DEFAULT 0, covered_until timestamptz,
 checkpoint_sha256 varchar(64), claim_token uuid, lease_until timestamptz,
 attempts integer NOT NULL DEFAULT 0, next_attempt_at timestamptz NOT NULL DEFAULT now(),
 last_error_code varchar(40), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((claim_token IS NULL)=(lease_until IS NULL))
);
INSERT INTO privacy_export_state(singleton) VALUES(true);
COMMENT ON TABLE privacy_journal IS 'Append-only privacy tombstones; no text, OTP, object contents or financial mutations. Captured by the same PostgreSQL transaction as business state.';
