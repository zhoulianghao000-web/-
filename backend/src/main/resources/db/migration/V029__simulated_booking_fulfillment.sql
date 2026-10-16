-- Append-only simulation facts. V028 reservation/cancellation facts remain unchanged.
CREATE TABLE booking_fulfillment_events (
 id uuid PRIMARY KEY, booking_id uuid NOT NULL REFERENCES service_bookings(id),
 version bigint NOT NULL CHECK(version BETWEEN 1 AND 2),
 status varchar(16) NOT NULL CHECK(status IN ('CHECKED_IN','COMPLETED','NO_SHOW','EXCEPTION')),
 reason_code varchar(32) NOT NULL CHECK(reason_code IN ('','SERVICE_UNAVAILABLE','SAFETY_STOP','CUSTOMER_DISPUTE')),
 actor_id uuid NOT NULL REFERENCES identity_principal(id), occurred_at timestamptz NOT NULL,
 UNIQUE(booking_id,version),
 CHECK((status='EXCEPTION')=(reason_code<>''))
);
CREATE FUNCTION protect_booking_fulfillment_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b service_bookings; s booking_slots; previous booking_fulfillment_events;
BEGIN
 SELECT * INTO STRICT b FROM service_bookings WHERE id=NEW.booking_id FOR UPDATE;
 SELECT * INTO STRICT s FROM booking_slots WHERE id=b.slot_id;
 SELECT * INTO previous FROM booking_fulfillment_events WHERE booking_id=b.id ORDER BY version DESC LIMIT 1;
 IF b.status<>'BOOKED' OR NEW.version<>coalesce(previous.version,0)+1
 OR (previous.id IS NULL AND NEW.status NOT IN ('CHECKED_IN','NO_SHOW','EXCEPTION'))
 OR (previous.id IS NOT NULL AND (previous.status<>'CHECKED_IN' OR NEW.status NOT IN ('COMPLETED','EXCEPTION') OR NEW.occurred_at<previous.occurred_at))
 OR (NEW.status='CHECKED_IN' AND (NEW.occurred_at<s.starts_at-interval '30 minutes' OR NEW.occurred_at>=s.ends_at))
 OR (NEW.status='COMPLETED' AND NEW.occurred_at<s.starts_at)
 OR (NEW.status='NO_SHOW' AND NEW.occurred_at<s.ends_at)
 OR (NEW.status='EXCEPTION' AND NEW.occurred_at<s.starts_at-interval '30 minutes')
 THEN RAISE EXCEPTION 'invalid simulated fulfillment transition'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER valid_booking_fulfillment BEFORE INSERT ON booking_fulfillment_events FOR EACH ROW EXECUTE FUNCTION protect_booking_fulfillment_insert();
CREATE TRIGGER immutable_booking_fulfillment BEFORE UPDATE OR DELETE ON booking_fulfillment_events FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER no_truncate_booking_fulfillment BEFORE TRUNCATE ON booking_fulfillment_events FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
-- An arrival and a cancellation cannot both become durable, including direct SQL.
CREATE OR REPLACE FUNCTION protect_service_booking() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' OR OLD.status<>'BOOKED' OR NEW.status<>'CANCELLED'
 OR NEW.version<>OLD.version+1
 OR EXISTS(SELECT 1 FROM booking_fulfillment_events WHERE booking_id=OLD.id)
 OR (to_jsonb(NEW)-ARRAY['status','version','cancelled_at','cancelled_by']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['status','version','cancelled_at','cancelled_by'])
 THEN RAISE EXCEPTION 'booking facts are immutable except cancellation before fulfillment'; END IF;
 RETURN NEW;
END $$;
