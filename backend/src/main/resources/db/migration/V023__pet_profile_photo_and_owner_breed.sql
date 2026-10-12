ALTER TABLE pets ADD COLUMN custom_breed_name varchar(80), ADD COLUMN photo_asset_id uuid REFERENCES media_asset(id);
ALTER TABLE pets ADD CONSTRAINT ck_pet_custom_breed CHECK(custom_breed_name IS NULL OR (breed_id IS NULL AND length(trim(custom_breed_name))>0));
CREATE INDEX ix_pet_photo_usage ON pets(photo_asset_id) WHERE status='ACTIVE' AND photo_asset_id IS NOT NULL;
COMMENT ON COLUMN pets.custom_breed_name IS 'Owner supplied label only; never a verified taxonomy breed or medical rule';
COMMENT ON COLUMN pets.photo_asset_id IS 'Owner controlled READY AVATAR resource reference; binaries stay in object storage';
