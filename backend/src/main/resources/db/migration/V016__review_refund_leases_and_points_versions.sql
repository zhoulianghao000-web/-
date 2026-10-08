-- Review correction; leave the already released V013-V015 checksums unchanged.
ALTER TABLE refunds ADD COLUMN lease_token uuid;
ALTER TABLE refunds ADD COLUMN lease_until timestamptz;
ALTER TABLE refunds ADD CONSTRAINT refund_lease_pair CHECK((lease_token IS NULL)=(lease_until IS NULL));
CREATE OR REPLACE FUNCTION protect_refund() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['status','attempt_count','next_retry_at','last_error_code','channel_refund_no','decided_at','lease_token','lease_until']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['status','attempt_count','next_retry_at','last_error_code','channel_refund_no','decided_at','lease_token','lease_until'])
 OR OLD.status IN ('SUCCEEDED','CANCELLED')
 OR NOT ((OLD.status='CREATED' AND NEW.status='PROCESSING')
  OR (OLD.status='PROCESSING' AND NEW.status IN ('PROCESSING','SUCCEEDED','FAILED_RETRYABLE','FAILED_FINAL'))
  OR (OLD.status='FAILED_RETRYABLE' AND NEW.status IN ('PROCESSING','FAILED_RETRYABLE','FAILED_FINAL'))
  OR (OLD.status='FAILED_FINAL' AND NEW.status='FAILED_RETRYABLE' AND NEW.attempt_count=0 AND NEW.last_error_code='MANUAL_RETRY_REQUESTED' AND NEW.lease_token IS NULL))
 THEN RAISE EXCEPTION 'invalid refund mutation'; END IF; RETURN NEW; END $$;
-- Policy versions are an authority, not merely an ordering hint. Fail migration if legacy duplicates need review.
ALTER TABLE points_policies ADD CONSTRAINT uq_points_policy_version UNIQUE(policy_version);
