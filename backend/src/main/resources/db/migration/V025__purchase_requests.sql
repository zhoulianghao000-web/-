-- Consumer demands are internal workflow facts, never procurement or inventory commitments.
CREATE TABLE purchase_requests (
 id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES app_user(id),request_cipher text NOT NULL,
 content_hash char(64) NOT NULL,status varchar(16) NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN','REVIEWING','RESOLVED','REJECTED','CANCELLED')),
 response_cipher text,version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_purchase_request_open ON purchase_requests(user_id,content_hash) WHERE status IN ('OPEN','REVIEWING');
CREATE INDEX ix_purchase_requests_owner ON purchase_requests(user_id,id);
CREATE INDEX ix_purchase_requests_status ON purchase_requests(status,id);
CREATE TABLE purchase_request_changes (
 id uuid PRIMARY KEY,request_id uuid NOT NULL REFERENCES purchase_requests(id),actor_id uuid NOT NULL REFERENCES identity_principal(id),
 status varchar(16) NOT NULL CHECK(status IN ('OPEN','REVIEWING','RESOLVED','REJECTED','CANCELLED')),
 version bigint NOT NULL,request_cipher text NOT NULL,response_cipher text,
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(request_id,version)
);
CREATE TRIGGER immutable_purchase_request_changes BEFORE UPDATE OR DELETE ON purchase_request_changes FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation();
INSERT INTO permission(code,description) VALUES ('purchase-request.read','Read consumer purchase requests'),('purchase-request.manage','Review consumer purchase requests') ON CONFLICT(code) DO NOTHING;
