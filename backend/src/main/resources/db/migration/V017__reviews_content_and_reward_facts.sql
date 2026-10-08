-- M5.2: verified order-item reviews, versioned article publishing and once-per-order review rewards.
ALTER TABLE media_asset DROP CONSTRAINT media_asset_mime_check;
ALTER TABLE media_asset ADD CONSTRAINT media_asset_mime_check CHECK(mime IN ('image/png','image/jpeg','video/mp4'));
ALTER TABLE media_asset ADD CONSTRAINT media_video_scope CHECK(mime<>'video/mp4' OR (scope='REVIEW' AND realm='CONSUMER'));

CREATE TABLE reviews (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app_user(id),
 order_id uuid NOT NULL REFERENCES orders(id), suborder_id uuid NOT NULL REFERENCES suborders(id),
 order_item_id uuid NOT NULL UNIQUE REFERENCES order_items(id), sku_id uuid NOT NULL REFERENCES skus(id),
 spu_id uuid NOT NULL REFERENCES spus(id), merchant_id uuid NOT NULL REFERENCES merchant(id), store_id uuid,
 current_revision_id uuid, published_revision_id uuid,
 visibility varchar(12) NOT NULL DEFAULT 'HIDDEN' CHECK(visibility IN ('PUBLIC','HIDDEN')),
 draft_status varchar(12) NOT NULL DEFAULT 'PENDING' CHECK(draft_status IN ('PENDING','APPROVED','REJECTED')),
 share_pet_label boolean NOT NULL DEFAULT false,
 version bigint NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE review_revisions (
 id uuid PRIMARY KEY, review_id uuid NOT NULL REFERENCES reviews(id), revision_no integer NOT NULL CHECK(revision_no>0),
 rating integer NOT NULL CHECK(rating BETWEEN 1 AND 5), service_rating integer CHECK(service_rating BETWEEN 1 AND 5),
 body text NOT NULL CHECK(length(body) BETWEEN 1 AND 2000),
 asset_ids jsonb NOT NULL CHECK(jsonb_typeof(asset_ids)='array' AND jsonb_array_length(asset_ids)<=6),
 pet_id uuid REFERENCES pets(id), pet_label jsonb,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(review_id,revision_no), UNIQUE(review_id,id)
);
ALTER TABLE reviews ADD CONSTRAINT review_current_revision FOREIGN KEY(id,current_revision_id) REFERENCES review_revisions(review_id,id);
ALTER TABLE reviews ADD CONSTRAINT review_published_revision FOREIGN KEY(id,published_revision_id) REFERENCES review_revisions(review_id,id);
CREATE TRIGGER immutable_review_revisions BEFORE UPDATE OR DELETE ON review_revisions FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE INDEX ix_reviews_public ON reviews(spu_id,id) WHERE visibility='PUBLIC';
CREATE INDEX ix_reviews_owner ON reviews(user_id,id);
CREATE INDEX ix_reviews_merchant ON reviews(merchant_id,store_id,id);
CREATE TABLE review_moderation (
 id uuid PRIMARY KEY, review_id uuid NOT NULL REFERENCES reviews(id), revision_id uuid NOT NULL REFERENCES review_revisions(id),
 decision varchar(12) NOT NULL CHECK(decision IN ('APPROVE','REJECT','HIDE')),
 reason varchar(1000) NOT NULL, actor_id uuid NOT NULL REFERENCES identity_principal(id),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_review_moderation BEFORE UPDATE OR DELETE ON review_moderation FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

CREATE TABLE review_reward_policies (
 id uuid PRIMARY KEY, policy_version integer NOT NULL UNIQUE CHECK(policy_version>0),
 base_points integer NOT NULL CHECK(base_points BETWEEN 0 AND 10000),
 media_bonus_points integer NOT NULL CHECK(media_bonus_points BETWEEN 0 AND 10000),
 refund_strategy varchar(24) NOT NULL CHECK(refund_strategy IN ('PROPORTIONAL_GOODS','NONE')),
 created_by uuid REFERENCES identity_principal(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_review_reward_policies BEFORE UPDATE OR DELETE ON review_reward_policies FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
INSERT INTO review_reward_policies(id,policy_version,base_points,media_bonus_points,refund_strategy)
VALUES ('5d2e2f3a-4b5c-6d7e-8f9a-000000000001',1,10,5,'PROPORTIONAL_GOODS');
CREATE TABLE review_reward_grants (
 order_id uuid PRIMARY KEY REFERENCES orders(id), user_id uuid NOT NULL REFERENCES app_user(id),
 policy_id uuid NOT NULL REFERENCES review_reward_policies(id), first_review_id uuid NOT NULL REFERENCES reviews(id),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_review_reward_grants BEFORE UPDATE OR DELETE ON review_reward_grants FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
ALTER TABLE points_ledger DROP CONSTRAINT points_ledger_entry_type_check;
ALTER TABLE points_ledger DROP CONSTRAINT points_ledger_check;
ALTER TABLE points_ledger ADD CONSTRAINT points_ledger_entry_type_check CHECK(entry_type IN ('PURCHASE_EARN','REVIEW_EARN','MEDIA_REVIEW_BONUS','CHECKIN_EARN','REDEMPTION_SPEND','REFUND_CLAWBACK','REVIEW_CLAWBACK','MANUAL_ADJUSTMENT'));
ALTER TABLE points_ledger ADD CONSTRAINT points_ledger_check CHECK((entry_type IN ('PURCHASE_EARN','REVIEW_EARN','MEDIA_REVIEW_BONUS','CHECKIN_EARN') AND points>0) OR (entry_type IN ('REDEMPTION_SPEND','REFUND_CLAWBACK','REVIEW_CLAWBACK') AND points<0) OR entry_type='MANUAL_ADJUSTMENT');

CREATE TABLE content_articles (
 id uuid PRIMARY KEY, current_revision_id uuid, published_revision_id uuid,
 visibility varchar(12) NOT NULL DEFAULT 'HIDDEN' CHECK(visibility IN ('PUBLIC','HIDDEN')),
 draft_status varchar(12) NOT NULL DEFAULT 'DRAFT' CHECK(draft_status IN ('DRAFT','SUBMITTED','APPROVED','REJECTED')),
 version bigint NOT NULL DEFAULT 0, created_by uuid NOT NULL REFERENCES identity_principal(id),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), published_at timestamptz
);
CREATE TABLE content_article_revisions (
 id uuid PRIMARY KEY, article_id uuid NOT NULL REFERENCES content_articles(id), revision_no integer NOT NULL CHECK(revision_no>0),
 title varchar(160) NOT NULL, category varchar(24) NOT NULL CHECK(category IN ('FOOD_KNOWLEDGE','BRAND_KNOWLEDGE','PET_CARE')),
 body text NOT NULL CHECK(length(body) BETWEEN 1 AND 20000), source_refs jsonb NOT NULL CHECK(jsonb_typeof(source_refs)='array' AND jsonb_array_length(source_refs) BETWEEN 1 AND 10),
 sponsored boolean NOT NULL DEFAULT false,
 asset_ids jsonb NOT NULL CHECK(jsonb_typeof(asset_ids)='array' AND jsonb_array_length(asset_ids)<=6),
 sku_ids jsonb NOT NULL CHECK(jsonb_typeof(sku_ids)='array' AND jsonb_array_length(sku_ids)<=8),
 created_by uuid NOT NULL REFERENCES identity_principal(id), created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(article_id,revision_no), UNIQUE(article_id,id)
);
ALTER TABLE content_articles ADD CONSTRAINT article_current_revision FOREIGN KEY(id,current_revision_id) REFERENCES content_article_revisions(article_id,id);
ALTER TABLE content_articles ADD CONSTRAINT article_published_revision FOREIGN KEY(id,published_revision_id) REFERENCES content_article_revisions(article_id,id);
CREATE TRIGGER immutable_article_revisions BEFORE UPDATE OR DELETE ON content_article_revisions FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE INDEX ix_content_public ON content_articles(id) WHERE visibility='PUBLIC';
CREATE TABLE content_moderation (
 id uuid PRIMARY KEY, article_id uuid NOT NULL REFERENCES content_articles(id), revision_id uuid NOT NULL REFERENCES content_article_revisions(id),
 decision varchar(12) NOT NULL CHECK(decision IN ('PUBLISH','REJECT','HIDE')),
 reason varchar(1000) NOT NULL, actor_id uuid NOT NULL REFERENCES identity_principal(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable_content_moderation BEFORE UPDATE OR DELETE ON content_moderation FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();

-- Referenced assets cannot be deleted while their immutable review/article evidence is retained.
CREATE TABLE media_asset_usage (
 asset_id uuid NOT NULL REFERENCES media_asset(id), kind varchar(12) NOT NULL CHECK(kind IN ('REVIEW','ARTICLE')),
 revision_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(asset_id,kind,revision_id)
);
CREATE TRIGGER immutable_media_asset_usage BEFORE UPDATE OR DELETE ON media_asset_usage FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
COMMENT ON TABLE review_reward_grants IS 'Freezes the first approved review reward policy once per parent order, not once per line or merchant';
COMMENT ON TABLE review_revisions IS 'Immutable review text/media/coarse consent label snapshots; never expose private pet fields';

INSERT INTO permission(code,description) VALUES
 ('review.read','Read reviews and moderation evidence'),('review.moderate','Moderate purchased-item reviews after reverify'),
 ('review.policy.manage','Publish immutable review reward policies after reverify'),
 ('review.merchant.read','Read public reviews within merchant/store scope'),
 ('content.read','Read content drafts and publishing evidence'),('content.write','Create, revise and submit article drafts'),
 ('content.moderate','Publish, reject or hide articles after reverify');
