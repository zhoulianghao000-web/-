-- M5.3: private human support, durable ordered messages and notification inbox.
CREATE TABLE conversations (
 id uuid PRIMARY KEY, consumer_id uuid NOT NULL REFERENCES identity_principal(id),
 kind varchar(12) NOT NULL CHECK(kind IN ('PLATFORM','MERCHANT')),
 merchant_id uuid REFERENCES merchant(id), store_id uuid REFERENCES merchant_store(id),
 assigned_principal_id uuid REFERENCES identity_principal(id),
 status varchar(12) NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN','CLOSED')),
 last_sequence bigint NOT NULL DEFAULT 0 CHECK(last_sequence>=0),
 delivered_sequence bigint NOT NULL DEFAULT 0 CHECK(delivered_sequence BETWEEN 0 AND last_sequence),
 version bigint NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(store_id,merchant_id) REFERENCES merchant_store(id,merchant_id),
 CHECK((kind='PLATFORM' AND merchant_id IS NULL AND store_id IS NULL) OR (kind='MERCHANT' AND merchant_id IS NOT NULL AND store_id IS NOT NULL))
);
CREATE UNIQUE INDEX conversation_one_platform ON conversations(consumer_id) WHERE kind='PLATFORM';
CREATE UNIQUE INDEX conversation_one_store ON conversations(consumer_id,store_id) WHERE kind='MERCHANT';
CREATE INDEX conversation_queue ON conversations(kind,merchant_id,store_id,id);
CREATE TABLE conversation_participants (
 conversation_id uuid NOT NULL REFERENCES conversations(id), principal_id uuid NOT NULL REFERENCES identity_principal(id),
 active boolean NOT NULL DEFAULT true, read_sequence bigint NOT NULL DEFAULT 0 CHECK(read_sequence>=0),
 joined_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(conversation_id,principal_id)
);
CREATE TABLE conversation_messages (
 id uuid PRIMARY KEY, conversation_id uuid NOT NULL REFERENCES conversations(id), sequence bigint NOT NULL CHECK(sequence>0),
 sender_id uuid NOT NULL REFERENCES identity_principal(id), sender_realm varchar(12) NOT NULL CHECK(sender_realm IN ('CONSUMER','MERCHANT','ADMIN')),
 type varchar(12) NOT NULL CHECK(type IN ('TEXT','IMAGE','PRODUCT','ORDER')),
 body varchar(2000), asset_ids jsonb NOT NULL DEFAULT '[]' CHECK(jsonb_typeof(asset_ids)='array' AND jsonb_array_length(asset_ids)<=4),
 target_id uuid, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(conversation_id,sequence), UNIQUE(conversation_id,id),
 CHECK((type='TEXT' AND body IS NOT NULL AND length(body) BETWEEN 1 AND 2000 AND asset_ids='[]' AND target_id IS NULL)
 OR (type='IMAGE' AND body IS NULL AND jsonb_array_length(asset_ids) BETWEEN 1 AND 4 AND target_id IS NULL)
 OR (type IN ('PRODUCT','ORDER') AND body IS NULL AND asset_ids='[]' AND target_id IS NOT NULL))
);
CREATE TRIGGER immutable_conversation_messages BEFORE UPDATE OR DELETE ON conversation_messages FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
CREATE TABLE conversation_message_delivery (
 message_id uuid PRIMARY KEY REFERENCES conversation_messages(id), event_id uuid NOT NULL UNIQUE,
 delivered_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE media_asset_usage DROP CONSTRAINT media_asset_usage_kind_check;
ALTER TABLE media_asset_usage ADD CONSTRAINT media_asset_usage_kind_check CHECK(kind IN ('REVIEW','ARTICLE','CHAT'));
CREATE TABLE notification_preferences (
 principal_id uuid NOT NULL REFERENCES identity_principal(id), category varchar(24) NOT NULL CHECK(category IN ('ORDER','AFTERSALE','PRICE_DROP','RESTOCK','FOOD_REMINDER','ACTIVITY','SUPPORT')),
 enabled boolean NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(principal_id,category)
);
CREATE TABLE notification_messages (
 id uuid PRIMARY KEY, principal_id uuid NOT NULL REFERENCES identity_principal(id), event_id uuid NOT NULL,
 category varchar(24) NOT NULL CHECK(category IN ('ORDER','AFTERSALE','PRICE_DROP','RESTOCK','FOOD_REMINDER','ACTIVITY','SUPPORT')),
 event_type varchar(80) NOT NULL, target_type varchar(16) NOT NULL CHECK(target_type IN ('ORDER','AFTERSALE','CONVERSATION')),
 target_id uuid NOT NULL, notify_enabled boolean NOT NULL, read_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(principal_id,event_id)
);
CREATE INDEX notification_owner ON notification_messages(principal_id,id);
INSERT INTO permission(code,description) VALUES
 ('support.read','Read scoped human support queue and assigned conversations'),
 ('support.reply','Reply only to current assigned conversations'),
 ('support.assign','Assign or transfer scoped human support after reverify');
COMMENT ON TABLE notification_preferences IS 'Business reminder preferences; never represents operating-system push authorization. Inbox history remains available.';
COMMENT ON TABLE conversation_messages IS 'Immutable private messages, serialized sequence per conversation; RabbitMQ is delivery infrastructure, not the fact source';
