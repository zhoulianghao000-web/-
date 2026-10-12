ALTER TABLE identity_principal
  DROP COLUMN mfa_secret_ciphertext,
  DROP COLUMN last_totp_step;
ALTER TABLE identity_principal ADD CONSTRAINT ck_identity_principal_shape CHECK(
  (realm='CONSUMER' AND user_id IS NOT NULL AND merchant_id IS NULL AND password_hash IS NULL)
  OR (realm='MERCHANT' AND user_id IS NULL AND merchant_id IS NOT NULL AND password_hash IS NOT NULL)
  OR (realm='ADMIN' AND user_id IS NULL AND merchant_id IS NULL AND password_hash IS NOT NULL)
);
