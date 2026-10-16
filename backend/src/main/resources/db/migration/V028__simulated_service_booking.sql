-- V3.1.1: isolated no-charge rehearsal, never a sale or a payment instruction.
CREATE TABLE booking_services (
 id uuid PRIMARY KEY, store_id uuid NOT NULL REFERENCES merchant_store(id),
 title varchar(120) NOT NULL CHECK(length(trim(title))>0),
 kind varchar(16) NOT NULL CHECK(kind IN ('GROOMING','BOARDING')),
 status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','PAUSED')),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0), created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,store_id)
);
CREATE INDEX booking_services_store ON booking_services(store_id,id);
CREATE TABLE booking_slots (
 id uuid PRIMARY KEY, service_id uuid NOT NULL REFERENCES booking_services(id),
 starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL,
 capacity integer NOT NULL CHECK(capacity BETWEEN 1 AND 100),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(id,service_id),
 CHECK(ends_at>starts_at AND ends_at<=starts_at+interval '168 hours'),
 UNIQUE(service_id,starts_at)
);
CREATE INDEX booking_slots_service_time ON booking_slots(service_id,starts_at,id);
CREATE TABLE service_bookings (
 id uuid PRIMARY KEY, slot_id uuid NOT NULL, service_id uuid NOT NULL, store_id uuid NOT NULL,
 user_id uuid NOT NULL REFERENCES app_user(id), service_title varchar(120) NOT NULL,
 policy varchar(40) NOT NULL DEFAULT 'SIMULATION_NO_CHARGE_V1' CHECK(policy='SIMULATION_NO_CHARGE_V1'),
 amount_fen integer NOT NULL DEFAULT 0 CHECK(amount_fen=0),
 status varchar(16) NOT NULL DEFAULT 'BOOKED' CHECK(status IN ('BOOKED','CANCELLED')),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0), created_at timestamptz NOT NULL DEFAULT now(),
 cancelled_at timestamptz, cancelled_by uuid REFERENCES identity_principal(id),
 FOREIGN KEY(slot_id,service_id) REFERENCES booking_slots(id,service_id),
 FOREIGN KEY(service_id,store_id) REFERENCES booking_services(id,store_id),
 CHECK((status='CANCELLED')=(cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL)),
 CHECK(status<>'BOOKED' OR (cancelled_at IS NULL AND cancelled_by IS NULL))
);
CREATE UNIQUE INDEX booking_one_active_per_user_slot ON service_bookings(user_id,slot_id) WHERE status='BOOKED';
CREATE INDEX booking_capacity ON service_bookings(slot_id) WHERE status='BOOKED';
CREATE INDEX booking_user ON service_bookings(user_id,id);
CREATE INDEX booking_store ON service_bookings(store_id,id);
CREATE TRIGGER immutable_booking_slot BEFORE UPDATE OR DELETE ON booking_slots FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER no_truncate_booking_slot BEFORE TRUNCATE ON booking_slots FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE FUNCTION protect_service_booking() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' OR OLD.status<>'BOOKED' OR NEW.status<>'CANCELLED'
 OR NEW.version<>OLD.version+1
 OR (to_jsonb(NEW)-ARRAY['status','version','cancelled_at','cancelled_by']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['status','version','cancelled_at','cancelled_by'])
 THEN RAISE EXCEPTION 'booking facts are immutable except one cancellation'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_service_booking BEFORE UPDATE OR DELETE ON service_bookings FOR EACH ROW EXECUTE FUNCTION protect_service_booking();
CREATE TRIGGER no_truncate_service_booking BEFORE TRUNCATE ON service_bookings FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
