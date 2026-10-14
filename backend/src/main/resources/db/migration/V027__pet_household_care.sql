CREATE TABLE pet_share_members (
 pet_id uuid NOT NULL REFERENCES pets(id), user_id uuid NOT NULL REFERENCES app_user(id),
 role varchar(16) NOT NULL CHECK(role IN ('VIEWER','CAREGIVER')),
 status varchar(16) NOT NULL CHECK(status IN ('ACTIVE','REVOKED','LEFT')),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0), joined_at timestamptz NOT NULL DEFAULT now(),
 ended_at timestamptz, PRIMARY KEY(pet_id,user_id),
 CHECK((status='ACTIVE')=(ended_at IS NULL))
);
CREATE INDEX ix_pet_share_user ON pet_share_members(user_id,pet_id) WHERE status='ACTIVE';
CREATE TABLE pet_share_invites (
 id uuid PRIMARY KEY, pet_id uuid NOT NULL REFERENCES pets(id), token_hash char(64) NOT NULL UNIQUE,
 role varchar(16) NOT NULL CHECK(role IN ('VIEWER','CAREGIVER')),
 status varchar(16) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','ACCEPTED','REVOKED')),
 created_by uuid NOT NULL REFERENCES app_user(id), accepted_by uuid REFERENCES app_user(id),
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), ended_at timestamptz,
 CHECK(expires_at>created_at), CHECK((status='ACCEPTED')=(accepted_by IS NOT NULL)),
 CHECK((status='PENDING')=(ended_at IS NULL))
);
CREATE INDEX ix_pet_share_invites_pet ON pet_share_invites(pet_id,created_at DESC);
CREATE TABLE pet_care_tasks (
 id uuid PRIMARY KEY, pet_id uuid NOT NULL REFERENCES pets(id), title varchar(160) NOT NULL,
 due_on date NOT NULL, status varchar(16) NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN','DONE','CANCELLED')),
 created_by uuid NOT NULL REFERENCES app_user(id), completed_by uuid REFERENCES app_user(id),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0), created_at timestamptz NOT NULL DEFAULT now(), ended_at timestamptz,
 CHECK((status='OPEN')=(ended_at IS NULL)), CHECK((status='DONE')=(completed_by IS NOT NULL))
);
CREATE INDEX ix_pet_care_tasks ON pet_care_tasks(pet_id,due_on,id);
CREATE TABLE pet_care_entries (
 id uuid PRIMARY KEY, pet_id uuid NOT NULL REFERENCES pets(id), actor_user_id uuid NOT NULL REFERENCES app_user(id),
 kind varchar(16) NOT NULL CHECK(kind IN ('FEEDING','WALK','GROOMING','NOTE')),
 note varchar(2000) NOT NULL, recorded_on date NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pet_care_entries ON pet_care_entries(pet_id,created_at DESC,id DESC);
CREATE TRIGGER immutable_pet_care_entry BEFORE UPDATE OR DELETE ON pet_care_entries
 FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TRIGGER no_truncate_pet_care_entry BEFORE TRUNCATE ON pet_care_entries
 FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE FUNCTION protect_pet_care_task() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' OR OLD.status<>'OPEN' OR NEW.id<>OLD.id OR NEW.pet_id<>OLD.pet_id
 OR NEW.title<>OLD.title OR NEW.due_on<>OLD.due_on OR NEW.created_by<>OLD.created_by
 OR NEW.created_at<>OLD.created_at OR NEW.version<>OLD.version+1 OR NEW.status='OPEN'
 THEN RAISE EXCEPTION 'pet care task terminal state cannot be overwritten'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_pet_care_task BEFORE UPDATE OR DELETE ON pet_care_tasks
 FOR EACH ROW EXECUTE FUNCTION protect_pet_care_task();
CREATE TRIGGER no_truncate_pet_care_task BEFORE TRUNCATE ON pet_care_tasks FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation();
