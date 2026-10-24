-- V3.2-B1: explicit synthetic connections and immutable stock provenance. No old-data receipts.
CREATE TABLE integration_connections (
 id uuid PRIMARY KEY,merchant_id uuid NOT NULL REFERENCES merchant(id),store_id uuid NOT NULL,
 label varchar(110) NOT NULL CHECK(label ~ '^TEST_ONLY_[A-Za-z0-9_.:-]{1,100}$'),
 mode varchar(20) NOT NULL DEFAULT 'SIMULATED_TEST' CHECK(mode='SIMULATED_TEST'),
 inventory_basis varchar(50) NOT NULL DEFAULT 'DEDICATED_REMAINING_AFTER_WATERMARK' CHECK(inventory_basis='DEDICATED_REMAINING_AFTER_WATERMARK'),
 state varchar(8) NOT NULL DEFAULT 'PAUSED' CHECK(state IN ('PAUSED','ACTIVE')),version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
 created_by uuid NOT NULL REFERENCES identity_principal(id),created_at timestamptz NOT NULL,
 FOREIGN KEY(store_id,merchant_id) REFERENCES merchant_store(id,merchant_id)
);
CREATE TABLE integration_mappings (
 id uuid PRIMARY KEY,connection_id uuid NOT NULL REFERENCES integration_connections(id),offer_id uuid NOT NULL REFERENCES offers(id),
 external_sku varchar(110) NOT NULL CHECK(external_sku ~ '^TEST_ONLY_[A-Za-z0-9_.:-]{1,100}$'),
 external_warehouse varchar(110) NOT NULL CHECK(external_warehouse ~ '^TEST_ONLY_[A-Za-z0-9_.:-]{1,100}$'),unit varchar(8) NOT NULL CHECK(unit='PIECE'),
 state varchar(8) NOT NULL DEFAULT 'ACTIVE' CHECK(state IN ('ACTIVE','RETIRED')),version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
 epoch_sequence bigint NOT NULL CHECK(epoch_sequence>=0),epoch_inventory_version bigint NOT NULL CHECK(epoch_inventory_version>=0),
 created_by uuid NOT NULL REFERENCES identity_principal(id),created_at timestamptz NOT NULL,
 UNIQUE(id,connection_id)
);
CREATE UNIQUE INDEX integration_active_external_key ON integration_mappings(connection_id,external_warehouse,external_sku) WHERE state='ACTIVE';
CREATE UNIQUE INDEX integration_one_stock_source ON integration_mappings(offer_id) WHERE state='ACTIVE';
CREATE TABLE integration_stock_movements (
 id uuid PRIMARY KEY,offer_id uuid NOT NULL REFERENCES offers(id),sequence bigint NOT NULL CHECK(sequence>0),
 source_kind varchar(12) NOT NULL CHECK(source_kind IN ('SALE','ADJUSTMENT','RESTOCK')),source_id uuid NOT NULL,
 delta_qty bigint NOT NULL CHECK(delta_qty BETWEEN -1000000000 AND 1000000000 AND delta_qty<>0),
 before_on_hand_qty bigint NOT NULL,resulting_on_hand_qty bigint NOT NULL CHECK(resulting_on_hand_qty BETWEEN 0 AND 1000000000),
 resulting_inventory_version bigint NOT NULL CHECK(resulting_inventory_version>0),occurred_at timestamptz NOT NULL,
 UNIQUE(offer_id,sequence),UNIQUE(source_kind,source_id),UNIQUE(offer_id,resulting_inventory_version),
 CHECK(resulting_on_hand_qty=before_on_hand_qty+delta_qty),CHECK(source_kind<>'SALE' OR delta_qty<0),CHECK(source_kind<>'RESTOCK' OR delta_qty>0)
);
CREATE FUNCTION integration_guard_movement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE source jsonb;BEGIN
 PERFORM 1 FROM inventory_balances WHERE offer_id=NEW.offer_id FOR UPDATE;
 IF NEW.source_kind='SALE' THEN SELECT to_jsonb(x) INTO source FROM inventory_sale_events x WHERE id=NEW.source_id;
 ELSIF NEW.source_kind='ADJUSTMENT' THEN SELECT to_jsonb(x) INTO source FROM inventory_adjustments x WHERE id=NEW.source_id;
 ELSE SELECT to_jsonb(x) INTO source FROM inventory_restock_events x WHERE id=NEW.source_id;END IF;
 IF source IS NULL OR (source->>'offer_id')::uuid<>NEW.offer_id OR (source->>'before_on_hand_qty')::bigint<>NEW.before_on_hand_qty
 OR (source->>'resulting_on_hand_qty')::bigint<>NEW.resulting_on_hand_qty OR coalesce(source->>'resulting_inventory_version',source->>'resulting_version')::bigint<>NEW.resulting_inventory_version
 OR NEW.sequence<>(SELECT coalesce(max(sequence),0)+1 FROM integration_stock_movements WHERE offer_id=NEW.offer_id) THEN RAISE EXCEPTION 'integration movement source';END IF;RETURN NEW;
END $$;
CREATE TRIGGER integration_movement_source BEFORE INSERT ON integration_stock_movements FOR EACH ROW EXECUTE FUNCTION integration_guard_movement();
CREATE FUNCTION integration_capture_movement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE j jsonb:=to_jsonb(NEW);kind text;BEGIN
 PERFORM 1 FROM inventory_balances WHERE offer_id=NEW.offer_id FOR UPDATE;
 kind:=CASE TG_TABLE_NAME WHEN 'inventory_sale_events' THEN 'SALE' WHEN 'inventory_adjustments' THEN 'ADJUSTMENT' ELSE 'RESTOCK' END;
 INSERT INTO integration_stock_movements VALUES(gen_random_uuid(),NEW.offer_id,
 (SELECT coalesce(max(sequence),0)+1 FROM integration_stock_movements WHERE offer_id=NEW.offer_id),kind,NEW.id,
 (j->>'resulting_on_hand_qty')::bigint-(j->>'before_on_hand_qty')::bigint,
 (j->>'before_on_hand_qty')::bigint,(j->>'resulting_on_hand_qty')::bigint,
 coalesce(j->>'resulting_inventory_version',j->>'resulting_version')::bigint,clock_timestamp());
 RETURN NEW;
END $$;
CREATE TRIGGER integration_capture_sale AFTER INSERT ON inventory_sale_events FOR EACH ROW EXECUTE FUNCTION integration_capture_movement();
CREATE TRIGGER integration_capture_adjustment AFTER INSERT ON inventory_adjustments FOR EACH ROW EXECUTE FUNCTION integration_capture_movement();
CREATE TRIGGER integration_capture_restock AFTER INSERT ON inventory_restock_events FOR EACH ROW EXECUTE FUNCTION integration_capture_movement();
CREATE FUNCTION integration_prefix_hash(mapping uuid,ack bigint) RETURNS text LANGUAGE sql STABLE AS $$
 SELECT encode(digest(jsonb_build_object('mapping_id',m.id,'connection_id',m.connection_id,'offer_id',m.offer_id,'epoch',m.epoch_sequence,'ack',ack,
 'movements',coalesce((SELECT jsonb_agg(jsonb_build_object('sequence',x.sequence-m.epoch_sequence,'source_kind',x.source_kind,'source_id',x.source_id,'delta_qty',x.delta_qty) ORDER BY x.sequence)
 FROM integration_stock_movements x WHERE x.offer_id=m.offer_id AND x.sequence>m.epoch_sequence AND x.sequence<=m.epoch_sequence+ack),'[]'::jsonb))::text,'sha256'),'hex')
 FROM integration_mappings m WHERE m.id=mapping
$$;
CREATE TABLE integration_stock_acknowledgements (
 id uuid PRIMARY KEY,connection_id uuid NOT NULL,mapping_id uuid NOT NULL,acknowledged_local_sequence bigint NOT NULL CHECK(acknowledged_local_sequence>0),
 prefix_sha256 varchar(64) NOT NULL CHECK(prefix_sha256 ~ '^[0-9a-f]{64}$'),provider varchar(20) NOT NULL CHECK(provider='SIMULATED_TEST'),
 provider_reference varchar(110) NOT NULL CHECK(provider_reference ~ '^TEST_ONLY_'),received_at timestamptz NOT NULL,
 FOREIGN KEY(mapping_id,connection_id) REFERENCES integration_mappings(id,connection_id),UNIQUE(mapping_id,acknowledged_local_sequence),UNIQUE(connection_id,provider_reference)
);
CREATE TABLE integration_inventory_events (
 id uuid PRIMARY KEY,connection_id uuid NOT NULL,mapping_id uuid NOT NULL,mapping_version bigint NOT NULL CHECK(mapping_version>=0),
 external_event_id varchar(110) NOT NULL CHECK(external_event_id ~ '^TEST_ONLY_[A-Za-z0-9_.:-]{1,100}$'),
 external_version bigint NOT NULL CHECK(external_version BETWEEN 1 AND 1000000000),external_remaining_qty bigint NOT NULL CHECK(external_remaining_qty BETWEEN 0 AND 1000000000),
 acknowledged_local_sequence bigint NOT NULL CHECK(acknowledged_local_sequence>=0),acknowledgement_id uuid REFERENCES integration_stock_acknowledgements(id),
 payload_sha256 varchar(64) NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),observed_at timestamptz NOT NULL,
 FOREIGN KEY(mapping_id,connection_id) REFERENCES integration_mappings(id,connection_id),UNIQUE(connection_id,external_event_id),UNIQUE(mapping_id,external_version),
 CHECK((acknowledged_local_sequence=0)=(acknowledgement_id IS NULL))
);
CREATE FUNCTION integration_event_hash(mapping uuid,mapping_version bigint,event_key text,external_version bigint,qty bigint,ack bigint,ack_id uuid) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT encode(digest(jsonb_build_object('mapping_id',mapping,'mapping_version',mapping_version,'external_event_id',event_key,'external_version',external_version,'external_remaining_qty',qty,'acknowledged_local_sequence',ack,'acknowledgement_id',ack_id)::text,'sha256'),'hex')
$$;
CREATE TABLE integration_stock_previews (
 id uuid PRIMARY KEY,event_id uuid NOT NULL REFERENCES integration_inventory_events(id),snapshot jsonb NOT NULL,
 snapshot_sha256 varchar(64) NOT NULL CHECK(snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL REFERENCES identity_principal(id),created_at timestamptz NOT NULL,expires_at timestamptz NOT NULL,
 CHECK(expires_at=created_at+interval '5 minutes')
);
CREATE TABLE integration_stock_applications (
 id uuid PRIMARY KEY,preview_id uuid NOT NULL UNIQUE REFERENCES integration_stock_previews(id),event_id uuid NOT NULL UNIQUE REFERENCES integration_inventory_events(id),
 offer_id uuid NOT NULL REFERENCES offers(id),before_on_hand_qty bigint NOT NULL,resulting_on_hand_qty bigint NOT NULL CHECK(resulting_on_hand_qty BETWEEN 0 AND 1000000000),
 reserved_qty bigint NOT NULL CHECK(reserved_qty>=0 AND reserved_qty<=resulting_on_hand_qty),resulting_inventory_version bigint NOT NULL CHECK(resulting_inventory_version>0),
 created_by uuid NOT NULL REFERENCES identity_principal(id),applied_at timestamptz NOT NULL,UNIQUE(offer_id,resulting_inventory_version)
);
CREATE FUNCTION integration_inventory_context(event uuid) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE e integration_inventory_events;m integration_mappings;c integration_connections;b inventory_balances;a integration_stock_acknowledgements;
 latest bigint;applied bigint;previous_ack bigint;tail bigint;target bigint;delta bigint;reconciled bigint;reasons jsonb:='[]';trusted boolean:=true;BEGIN
 SELECT * INTO STRICT e FROM integration_inventory_events WHERE id=event;
 SELECT * INTO STRICT m FROM integration_mappings WHERE id=e.mapping_id;SELECT * INTO STRICT c FROM integration_connections WHERE id=m.connection_id;
 SELECT * INTO STRICT b FROM inventory_balances WHERE offer_id=m.offer_id;
 SELECT coalesce(max(sequence),m.epoch_sequence)-m.epoch_sequence INTO latest FROM integration_stock_movements WHERE offer_id=m.offer_id;
 SELECT coalesce(max(ev.external_version),0),coalesce(max(ev.acknowledged_local_sequence),0) INTO applied,previous_ack FROM integration_stock_applications x JOIN integration_inventory_events ev ON ev.id=x.event_id WHERE ev.mapping_id=m.id;
 IF c.state<>'ACTIVE' OR m.state<>'ACTIVE' THEN reasons:=reasons||'"INTEGRATION_INACTIVE"'::jsonb;END IF;
 IF e.mapping_version<>m.version THEN reasons:=reasons||'"MAPPING_STALE"'::jsonb;trusted:=false;END IF;
 IF e.external_version<=applied OR EXISTS(SELECT 1 FROM integration_inventory_events WHERE mapping_id=m.id AND external_version>e.external_version) THEN reasons:=reasons||'"EXTERNAL_VERSION_STALE"'::jsonb;END IF;
 IF e.acknowledged_local_sequence>latest OR e.acknowledged_local_sequence<previous_ack THEN reasons:=reasons||'"WATERMARK_INVALID"'::jsonb;trusted:=false;END IF;
 IF e.acknowledgement_id IS NOT NULL THEN
 SELECT * INTO STRICT a FROM integration_stock_acknowledgements WHERE id=e.acknowledgement_id;
 IF a.mapping_id<>m.id OR a.connection_id<>c.id OR a.acknowledged_local_sequence<>e.acknowledged_local_sequence OR a.prefix_sha256<>integration_prefix_hash(m.id,e.acknowledged_local_sequence) THEN reasons:=reasons||'"WATERMARK_UNPROVEN"'::jsonb;trusted:=false;END IF;
 END IF;
 SELECT coalesce(sum(delta_qty),0) INTO reconciled FROM integration_stock_movements WHERE offer_id=m.offer_id AND sequence>m.epoch_sequence;
 SELECT reconciled+coalesce(sum(x.resulting_on_hand_qty-x.before_on_hand_qty),0) INTO reconciled FROM integration_stock_applications x JOIN integration_inventory_events ev ON ev.id=x.event_id WHERE ev.mapping_id=m.id;
 IF reconciled<>b.on_hand_qty THEN reasons:=reasons||'"LOCAL_STOCK_UNRECONCILED"'::jsonb;trusted:=false;END IF;
 IF trusted THEN
 SELECT coalesce(sum(delta_qty),0) INTO tail FROM integration_stock_movements WHERE offer_id=m.offer_id AND sequence>m.epoch_sequence+e.acknowledged_local_sequence;
 target:=e.external_remaining_qty+tail;
 IF target<0 OR target>1000000000 THEN reasons:=reasons||'"PROJECTED_STOCK_OUT_OF_RANGE"'::jsonb;target:=NULL;
 ELSIF target<b.reserved_qty THEN reasons:=reasons||'"RESERVED_STOCK_CONFLICT"'::jsonb;END IF;
 delta:=target-b.on_hand_qty;
 END IF;
 RETURN jsonb_build_object('event_id',e.id,'mapping_id',m.id,'connection_id',c.id,'offer_id',m.offer_id,'connection_version',c.version,'mapping_version',m.version,
 'inventory_version',b.version,'local_sequence',latest,'on_hand_qty',b.on_hand_qty,'reserved_qty',b.reserved_qty,'target_on_hand_qty',target,'delta_qty',delta,
 'external_version',e.external_version,'applied_external_version',applied,'acknowledged_local_sequence',e.acknowledged_local_sequence,'prefix_sha256',integration_prefix_hash(m.id,e.acknowledged_local_sequence),
 'eligible',jsonb_array_length(reasons)=0,'blocked_reasons',reasons);
END $$;
CREATE FUNCTION integration_guard_fact() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE m integration_mappings;c integration_connections;b inventory_balances;p integration_stock_previews;ctx jsonb;BEGIN
 IF TG_TABLE_NAME='integration_stock_acknowledgements' THEN
 SELECT * INTO STRICT m FROM integration_mappings WHERE id=NEW.mapping_id;
 IF NEW.prefix_sha256<>integration_prefix_hash(m.id,NEW.acknowledged_local_sequence) OR NEW.acknowledged_local_sequence>(SELECT coalesce(max(sequence),m.epoch_sequence)-m.epoch_sequence FROM integration_stock_movements WHERE offer_id=m.offer_id) THEN RAISE EXCEPTION 'unproven integration acknowledgement';END IF;
 ELSIF TG_TABLE_NAME='integration_inventory_events' THEN
 IF NEW.payload_sha256<>integration_event_hash(NEW.mapping_id,NEW.mapping_version,NEW.external_event_id,NEW.external_version,NEW.external_remaining_qty,NEW.acknowledged_local_sequence,NEW.acknowledgement_id) THEN RAISE EXCEPTION 'integration event payload hash';END IF;
 ELSIF TG_TABLE_NAME='integration_stock_previews' THEN
 ctx:=integration_inventory_context(NEW.event_id);
 IF NEW.snapshot<>ctx OR NEW.snapshot_sha256<>encode(digest(ctx::text,'sha256'),'hex') THEN RAISE EXCEPTION 'integration preview source';END IF;
 ELSE
 SELECT * INTO STRICT p FROM integration_stock_previews WHERE id=NEW.preview_id;
 SELECT * INTO STRICT m FROM integration_mappings WHERE id=(SELECT mapping_id FROM integration_inventory_events WHERE id=p.event_id);
 SELECT * INTO STRICT c FROM integration_connections WHERE id=m.connection_id FOR UPDATE;
 PERFORM 1 FROM integration_mappings WHERE id=m.id FOR UPDATE;PERFORM 1 FROM offers WHERE id=m.offer_id FOR UPDATE;
 SELECT * INTO STRICT b FROM inventory_balances WHERE offer_id=m.offer_id FOR UPDATE;
 ctx:=integration_inventory_context(p.event_id);
 IF NEW.event_id<>p.event_id OR NEW.offer_id<>m.offer_id OR NEW.created_by<>p.created_by OR NEW.applied_at<p.created_at OR NEW.applied_at>=p.expires_at
 OR ctx<>p.snapshot OR NOT (ctx->>'eligible')::boolean OR NEW.before_on_hand_qty<>b.on_hand_qty OR NEW.reserved_qty<>b.reserved_qty
 OR NEW.resulting_on_hand_qty<>(ctx->>'target_on_hand_qty')::bigint OR NEW.resulting_inventory_version<>b.version+1 THEN RAISE EXCEPTION 'integration application source';END IF;
 END IF;RETURN NEW;
END $$;
CREATE TRIGGER integration_ack_guard BEFORE INSERT ON integration_stock_acknowledgements FOR EACH ROW EXECUTE FUNCTION integration_guard_fact();
CREATE TRIGGER integration_event_guard BEFORE INSERT ON integration_inventory_events FOR EACH ROW EXECUTE FUNCTION integration_guard_fact();
CREATE TRIGGER integration_preview_guard BEFORE INSERT ON integration_stock_previews FOR EACH ROW EXECUTE FUNCTION integration_guard_fact();
CREATE TRIGGER integration_application_guard BEFORE INSERT ON integration_stock_applications FOR EACH ROW EXECUTE FUNCTION integration_guard_fact();
CREATE FUNCTION integration_apply_inventory() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 UPDATE inventory_balances SET on_hand_qty=NEW.resulting_on_hand_qty,version=NEW.resulting_inventory_version,updated_at=NEW.applied_at WHERE offer_id=NEW.offer_id;
 RETURN NEW;END $$;
CREATE TRIGGER integration_application_balance AFTER INSERT ON integration_stock_applications FOR EACH ROW EXECUTE FUNCTION integration_apply_inventory();
CREATE FUNCTION integration_guard_scope() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c integration_connections;o offers;b inventory_balances;BEGIN
 IF TG_TABLE_NAME='integration_connections' THEN
 IF TG_OP='INSERT' THEN
 IF NEW.state<>'PAUSED' OR NEW.version<>0 THEN RAISE EXCEPTION 'integration connection starts paused';END IF;
 ELSIF (to_jsonb(NEW)-ARRAY['state','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['state','version']) OR NEW.state=OLD.state OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'integration connection lifecycle';END IF;
 ELSE
 SELECT * INTO STRICT c FROM integration_connections WHERE id=NEW.connection_id;
 SELECT * INTO STRICT o FROM offers WHERE id=NEW.offer_id FOR UPDATE;SELECT * INTO STRICT b FROM inventory_balances WHERE offer_id=o.id FOR UPDATE;
 IF o.merchant_id<>c.merchant_id OR o.store_id IS DISTINCT FROM c.store_id THEN RAISE EXCEPTION 'integration mapping owner';END IF;
 IF TG_OP='INSERT' THEN
 IF c.state<>'PAUSED' OR NEW.state<>'ACTIVE' OR NEW.version<>0 OR b.on_hand_qty<>0 OR b.reserved_qty<>0 OR NEW.epoch_inventory_version<>b.version
 OR NEW.epoch_sequence<>(SELECT coalesce(max(sequence),0) FROM integration_stock_movements WHERE offer_id=o.id)
 OR EXISTS(SELECT 1 FROM order_items i JOIN suborders s ON s.id=i.suborder_id WHERE i.offer_id=o.id AND s.fulfillment_status NOT IN ('CANCELLED','COMPLETED')) THEN RAISE EXCEPTION 'integration mapping bootstrap';END IF;
 ELSIF (to_jsonb(NEW)-ARRAY['state','version']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['state','version']) OR OLD.state<>'ACTIVE' OR NEW.state<>'RETIRED' OR NEW.version<>OLD.version+1
 OR EXISTS(SELECT 1 FROM integration_inventory_events e WHERE e.mapping_id=NEW.id AND e.external_version>coalesce((SELECT max(ev.external_version) FROM integration_stock_applications x JOIN integration_inventory_events ev ON ev.id=x.event_id WHERE ev.mapping_id=NEW.id),0)) THEN RAISE EXCEPTION 'integration mapping unresolved responsibility';END IF;
 END IF;RETURN NEW;
END $$;
CREATE TRIGGER integration_connection_scope BEFORE INSERT OR UPDATE ON integration_connections FOR EACH ROW EXECUTE FUNCTION integration_guard_scope();
CREATE TRIGGER integration_mapping_scope BEFORE INSERT OR UPDATE ON integration_mappings FOR EACH ROW EXECUTE FUNCTION integration_guard_scope();
CREATE FUNCTION integration_verify_mapped_balance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE offer uuid;mapping integration_mappings;balance bigint;expected bigint;BEGIN
 offer:=NEW.offer_id;
 SELECT * INTO mapping FROM integration_mappings WHERE offer_id=offer AND state='ACTIVE';IF NOT FOUND THEN RETURN NULL;END IF;
 SELECT on_hand_qty INTO STRICT balance FROM inventory_balances WHERE offer_id=offer;
 SELECT coalesce(sum(delta_qty),0) INTO expected FROM integration_stock_movements WHERE offer_id=offer AND sequence>mapping.epoch_sequence;
 SELECT expected+coalesce(sum(x.resulting_on_hand_qty-x.before_on_hand_qty),0) INTO expected FROM integration_stock_applications x JOIN integration_inventory_events e ON e.id=x.event_id WHERE e.mapping_id=mapping.id;
 IF balance<>expected THEN RAISE EXCEPTION 'integration mapped inventory conservation';END IF;RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER integration_balance_conservation AFTER UPDATE ON inventory_balances DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION integration_verify_mapped_balance();
CREATE CONSTRAINT TRIGGER integration_movement_conservation AFTER INSERT ON integration_stock_movements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION integration_verify_mapped_balance();
DO $$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['integration_connections','integration_mappings','integration_stock_movements','integration_stock_acknowledgements','integration_inventory_events','integration_stock_previews','integration_stock_applications'] LOOP
 EXECUTE format('CREATE TRIGGER integration_no_truncate BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 IF t IN ('integration_connections','integration_mappings') THEN EXECUTE format('CREATE TRIGGER integration_no_delete BEFORE DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);
 ELSE EXECUTE format('CREATE TRIGGER integration_immutable BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION reject_pricing_snapshot_mutation()',t);END IF;
 END LOOP;
END $$;
INSERT INTO permission(code,description) VALUES
 ('integration.read','Read scoped synthetic integration inventory'),('integration.manage','Manage scoped synthetic integration connection'),
 ('integration.mapping.write','Bind and retire scoped synthetic inventory mapping'),('integration.stock.assess','Create stock comparison snapshot'),('integration.stock.apply','Apply verified synthetic stock snapshot');
