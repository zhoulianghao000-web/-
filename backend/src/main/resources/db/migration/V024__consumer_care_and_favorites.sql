-- V1 closeout: owner-managed estimates, immutable calibration history and favorites.
CREATE TABLE pet_food_plans (
 id uuid PRIMARY KEY, pet_id uuid NOT NULL UNIQUE REFERENCES pets(id), sku_id uuid REFERENCES skus(id),
 food_name varchar(160) NOT NULL CHECK(length(trim(food_name))>0),
 package_weight_g bigint NOT NULL CHECK(package_weight_g BETWEEN 1 AND 100000000),
 daily_amount_g integer NOT NULL CHECK(daily_amount_g BETWEEN 1 AND 1000000),
 started_on date NOT NULL, baseline_on date NOT NULL, baseline_remaining_g bigint NOT NULL CHECK(baseline_remaining_g BETWEEN 0 AND package_weight_g),
 reminder_enabled boolean NOT NULL, remind_before_days integer NOT NULL CHECK(remind_before_days BETWEEN 0 AND 30),
 active boolean NOT NULL DEFAULT true, version bigint NOT NULL DEFAULT 0,
 emitted_event_id uuid REFERENCES outbox_event(id), created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(baseline_on>=started_on)
);
CREATE TABLE pet_food_changes (
 id uuid PRIMARY KEY, plan_id uuid NOT NULL REFERENCES pet_food_plans(id), version bigint NOT NULL,
 action varchar(16) NOT NULL CHECK(action IN ('START','CALIBRATE','STOP')),
 snapshot jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(plan_id,version)
);
CREATE TRIGGER immutable_pet_food_changes BEFORE UPDATE OR DELETE ON pet_food_changes FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE INDEX pet_food_due ON pet_food_plans(id) WHERE active AND reminder_enabled AND emitted_event_id IS NULL;
CREATE TABLE consumer_favorites (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app_user(id),
 spu_id uuid REFERENCES spus(id), store_id uuid REFERENCES merchant_store(id), active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((spu_id IS NULL)<>(store_id IS NULL))
);
CREATE UNIQUE INDEX favorite_product_owner ON consumer_favorites(user_id,spu_id) WHERE spu_id IS NOT NULL;
CREATE UNIQUE INDEX favorite_store_owner ON consumer_favorites(user_id,store_id) WHERE store_id IS NOT NULL;
ALTER TABLE notification_messages DROP CONSTRAINT notification_messages_target_type_check;
ALTER TABLE notification_messages ADD CONSTRAINT notification_messages_target_type_check CHECK(target_type IN ('ORDER','AFTERSALE','CONVERSATION','PET_FOOD'));
COMMENT ON TABLE pet_food_plans IS 'Owner-entered consumption estimates; never a dietary recommendation or automatic purchase authorization';

CREATE TABLE invoice_applications (
 id uuid PRIMARY KEY, suborder_id uuid NOT NULL UNIQUE REFERENCES suborders(id),
 title_type varchar(16) NOT NULL CHECK(title_type IN ('PERSONAL','BUSINESS')),
 private_cipher text NOT NULL, status varchar(16) NOT NULL DEFAULT 'REQUESTED' CHECK(status IN ('REQUESTED','ACCEPTED','REJECTED')),
 reason varchar(500), version bigint NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE invoice_application_changes (
 id uuid PRIMARY KEY, application_id uuid NOT NULL REFERENCES invoice_applications(id), version bigint NOT NULL,
 status varchar(16) NOT NULL CHECK(status IN ('REQUESTED','ACCEPTED','REJECTED')),
 actor_principal_id uuid NOT NULL REFERENCES identity_principal(id), reason varchar(500), created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(application_id,version)
);
CREATE TRIGGER immutable_invoice_application_changes BEFORE UPDATE OR DELETE ON invoice_application_changes FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
INSERT INTO permission(code,description) VALUES
 ('invoice.read','Invoice application read'),('invoice.handle','Invoice application handle') ON CONFLICT(code) DO NOTHING;
