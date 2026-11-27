SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: jj_lg_directory_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_lg_directory_sync() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
  target text;
  payload jsonb;
  is_active boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    target := jj_lg_directory_table(OLD.module_slug);
    IF target IS NOT NULL THEN
      EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id;
    END IF;
    RETURN NULL;
  END IF;

  -- An edit can move a row between slugs; clear the old home first.
  IF TG_OP = 'UPDATE' AND (OLD.module_slug IS DISTINCT FROM NEW.module_slug OR OLD.id IS DISTINCT FROM NEW.id) THEN
    target := jj_lg_directory_table(OLD.module_slug);
    IF target IS NOT NULL THEN
      EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id;
    END IF;
  END IF;

  target := jj_lg_directory_table(NEW.module_slug);
  IF target IS NULL THEN
    RETURN NULL;
  END IF;

  payload := CASE WHEN jsonb_typeof(NEW.data::jsonb) = 'object'
                  THEN NEW.data::jsonb ELSE '{}'::jsonb END;

  -- Mirrors active_module_record?: any delete flag set, or a status that
  -- is present and not "Active", means inactive. Blank status is active.
  is_active := NOT ( COALESCE(LOWER(BTRIM(payload ->> 'deleted')), '') IN ('1', 'true', 'yes', 'deleted') OR COALESCE(LOWER(BTRIM(payload ->> 'is_deleted')), '') IN ('1', 'true', 'yes', 'deleted') OR COALESCE(LOWER(BTRIM(payload ->> 'discarded')), '') IN ('1', 'true', 'yes', 'deleted') OR (COALESCE(BTRIM(payload ->> 'status'), '') <> '' AND LOWER(BTRIM(payload ->> 'status')) <> 'active') );

  EXECUTE format(
    'INSERT INTO %I (id, source_slug, active, status, state_name, state_code, district_name, district_code, sub_district_name, sub_district_code, block_name, block_code, gram_panchayat_name, gp_code, village_name, village_code, data, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
     ON CONFLICT (id) DO UPDATE SET
       source_slug = EXCLUDED.source_slug, active = EXCLUDED.active, status = EXCLUDED.status,
       state_name = EXCLUDED.state_name, state_code = EXCLUDED.state_code, district_name = EXCLUDED.district_name, district_code = EXCLUDED.district_code, sub_district_name = EXCLUDED.sub_district_name, sub_district_code = EXCLUDED.sub_district_code, block_name = EXCLUDED.block_name, block_code = EXCLUDED.block_code, gram_panchayat_name = EXCLUDED.gram_panchayat_name, gp_code = EXCLUDED.gp_code, village_name = EXCLUDED.village_name, village_code = EXCLUDED.village_code,
       data = EXCLUDED.data, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at',
    target
  ) USING
    NEW.id, NEW.module_slug, is_active, payload ->> 'status',
    COALESCE(NULLIF(payload ->> 'state_name', ''), NULLIF(payload ->> 'state', '')),
          COALESCE(NULLIF(payload ->> 'state_code', '')),
          COALESCE(NULLIF(payload ->> 'district_name', ''), NULLIF(payload ->> 'district', '')),
          COALESCE(NULLIF(payload ->> 'district_code', '')),
          COALESCE(NULLIF(payload ->> 'sub_district_name', ''), NULLIF(payload ->> 'sub_district', '')),
          COALESCE(NULLIF(payload ->> 'sub_district_code', '')),
          COALESCE(NULLIF(payload ->> 'block_name', ''), NULLIF(payload ->> 'cd_block_name', ''), NULLIF(payload ->> 'block', '')),
          COALESCE(NULLIF(payload ->> 'block_code', ''), NULLIF(payload ->> 'cd_block_code', '')),
          COALESCE(NULLIF(payload ->> 'gram_panchayat_name', ''), NULLIF(payload ->> 'gram_panchayat', '')),
          COALESCE(NULLIF(payload ->> 'gp_code', '')),
          COALESCE(NULLIF(payload ->> 'village_name', ''), NULLIF(payload ->> 'village', '')),
          COALESCE(NULLIF(payload ->> 'village_code', '')),
    payload, NEW.created_at, NEW.updated_at;

  RETURN NULL;
END;
$_$;


--
-- Name: jj_lg_directory_table(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_lg_directory_table(slug text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  RETURN CASE slug
    WHEN 'state-master' THEN 'lg_states'
          WHEN 'district-master' THEN 'lg_districts'
          WHEN 'block-master' THEN 'lg_blocks'
          WHEN 'gram-panchayat-master' THEN 'lg_gram_panchayats'
          WHEN 'village-master' THEN 'lg_villages'
          WHEN 'lg-directory-list' THEN 'lg_villages'
    ELSE NULL
  END;
END;
$$;


--
-- Name: jj_module_entries_legacy_bridge(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entries_legacy_bridge() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE target text;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    IF TG_OP = 'DELETE' OR OLD.module_slug IS DISTINCT FROM NEW.module_slug OR OLD.id IS DISTINCT FROM NEW.id THEN
      SELECT table_name INTO target FROM module_entry_sources WHERE slug = OLD.module_slug;
      IF target IS NOT NULL THEN EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id; END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN NULL; END IF;
  END IF;
  SELECT table_name INTO target FROM module_entry_sources WHERE slug = NEW.module_slug;
  -- Unknown slugs written by obsolete code must not silently disappear.
  IF target IS NULL THEN RAISE EXCEPTION 'Module source not configured: %', NEW.module_slug; END IF;
  EXECUTE format('INSERT INTO %I(id, source_slug, data, payload_text, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6)
    ON CONFLICT(id) DO UPDATE SET source_slug = EXCLUDED.source_slug, data = EXCLUDED.data, payload_text = EXCLUDED.payload_text,
      created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at', target)
  USING NEW.id, NEW.module_slug, CASE WHEN jsonb_typeof(NEW.data::jsonb) = 'object' THEN NEW.data::jsonb ELSE '{}'::jsonb END,
    NEW.data, NEW.created_at, NEW.updated_at;
  RETURN NULL;
END;
$_$;


--
-- Name: jj_module_entries_versions_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entries_versions_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM jj_module_entry_ensure_epoch();
  INSERT INTO module_record_read_versions(source_key, revision)
  SELECT 'module:' || source_slug, nextval('module_record_read_version_seq')
  FROM (SELECT DISTINCT source_slug FROM (SELECT source_slug FROM old_rows) affected WHERE source_slug IS NOT NULL) keys
  ON CONFLICT(source_key) DO UPDATE SET revision = EXCLUDED.revision;
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_entries_versions_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entries_versions_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM jj_module_entry_ensure_epoch();
  INSERT INTO module_record_read_versions(source_key, revision)
  SELECT 'module:' || source_slug, nextval('module_record_read_version_seq')
  FROM (SELECT DISTINCT source_slug FROM (SELECT source_slug FROM new_rows) affected WHERE source_slug IS NOT NULL) keys
  ON CONFLICT(source_key) DO UPDATE SET revision = EXCLUDED.revision;
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_entries_versions_truncate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entries_versions_truncate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM jj_module_entry_ensure_epoch();
  INSERT INTO module_record_read_versions(source_key, revision)
  SELECT 'module:' || slug, nextval('module_record_read_version_seq') FROM module_entry_sources WHERE table_name = TG_TABLE_NAME
  ON CONFLICT(source_key) DO UPDATE SET revision = EXCLUDED.revision;
  DELETE FROM module_entry_identities WHERE module_slug IN (SELECT slug FROM module_entry_sources WHERE table_name = TG_TABLE_NAME);
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_entries_versions_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entries_versions_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM jj_module_entry_ensure_epoch();
  INSERT INTO module_record_read_versions(source_key, revision)
  SELECT 'module:' || source_slug, nextval('module_record_read_version_seq')
  FROM (SELECT DISTINCT source_slug FROM (SELECT source_slug FROM new_rows UNION SELECT source_slug FROM old_rows) affected WHERE source_slug IS NOT NULL) keys
  ON CONFLICT(source_key) DO UPDATE SET revision = EXCLUDED.revision;
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_entries_write(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entries_write() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE target text; previous_target text; payload jsonb;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    SELECT table_name INTO previous_target FROM module_entry_sources WHERE slug = OLD.module_slug;
    IF TG_OP = 'DELETE' OR OLD.module_slug IS DISTINCT FROM NEW.module_slug OR OLD.id IS DISTINCT FROM NEW.id THEN
      EXECUTE format('DELETE FROM %I WHERE id = $1', previous_target) USING OLD.id;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  END IF;
  SELECT table_name INTO target FROM module_entry_sources WHERE slug = NEW.module_slug;
  IF target IS NULL THEN RAISE EXCEPTION 'Module source not configured: %', NEW.module_slug; END IF;
  payload := NEW.data::jsonb;
  IF TG_OP = 'INSERT' THEN
    EXECUTE format('INSERT INTO %I(id, source_slug, data, payload_text, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6)', target)
    USING NEW.id, NEW.module_slug, CASE WHEN jsonb_typeof(payload) = 'object' THEN payload ELSE '{}'::jsonb END, NEW.data, NEW.created_at, NEW.updated_at;
  ELSE
    EXECUTE format('INSERT INTO %I(id, source_slug, data, payload_text, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6)
      ON CONFLICT (id) DO UPDATE SET source_slug = EXCLUDED.source_slug, data = EXCLUDED.data,
        payload_text = EXCLUDED.payload_text, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at', target)
    USING NEW.id, NEW.module_slug, CASE WHEN jsonb_typeof(payload) = 'object' THEN payload ELSE '{}'::jsonb END, NEW.data, NEW.created_at, NEW.updated_at;
  END IF;
  RETURN NEW;
END;
$_$;


--
-- Name: jj_module_entry_dependency_changed(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entry_dependency_changed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM jj_module_entry_ensure_epoch();
  INSERT INTO module_record_read_versions(source_key, revision) VALUES ('table:' || TG_TABLE_NAME, nextval('module_record_read_version_seq'))
  ON CONFLICT(source_key) DO UPDATE SET revision = EXCLUDED.revision;
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_entry_ensure_epoch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entry_ensure_epoch() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO module_record_read_versions(source_key, revision)
  VALUES ('epoch', ('x' || substr(md5(random()::text || clock_timestamp()::text), 1, 15))::bit(60)::bigint)
  ON CONFLICT(source_key) DO NOTHING;
END;
$$;


--
-- Name: jj_module_entry_identity_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entry_identity_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM module_entry_identities WHERE id = OLD.id AND module_slug = OLD.source_slug;
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_entry_prepare(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_entry_prepare() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE payload jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM module_entry_sources WHERE slug = NEW.source_slug AND table_name = TG_TABLE_NAME) THEN
    RAISE EXCEPTION 'Invalid dedicated module source % for %', NEW.source_slug, TG_TABLE_NAME USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.source_slug IS DISTINCT FROM OLD.source_slug THEN
      DELETE FROM module_entry_identities WHERE id = OLD.id AND module_slug = OLD.source_slug;
    END IF;
    IF NEW.payload_text IS DISTINCT FROM OLD.payload_text THEN
      payload := NEW.payload_text::jsonb;
      NEW.data := CASE WHEN jsonb_typeof(payload) = 'object' THEN payload ELSE '{}'::jsonb END;
    ELSIF NEW.data IS DISTINCT FROM OLD.data THEN
      NEW.payload_text := NEW.data::text;
    END IF;
  ELSIF NEW.payload_text IS NULL THEN
    NEW.payload_text := NEW.data::text;
  ELSE
    payload := NEW.payload_text::jsonb;
    NEW.data := CASE WHEN jsonb_typeof(payload) = 'object' THEN payload ELSE '{}'::jsonb END;
  END IF;
  INSERT INTO module_entry_identities(id, module_slug) VALUES (NEW.id, NEW.source_slug)
  ON CONFLICT (id) DO UPDATE SET module_slug = EXCLUDED.module_slug
    WHERE module_entry_identities.module_slug = EXCLUDED.module_slug;
  IF NOT FOUND THEN RAISE EXCEPTION 'Duplicate module ID %', NEW.id USING ERRCODE = '23505'; END IF;
  IF TG_TABLE_NAME LIKE 'lg_%' THEN
    payload := NEW.data;
    NEW.status := payload ->> 'status';
    NEW.active := NOT (COALESCE(LOWER(BTRIM(payload ->> 'deleted')), '') IN ('1','true','yes','deleted') OR COALESCE(LOWER(BTRIM(payload ->> 'is_deleted')), '') IN ('1','true','yes','deleted') OR COALESCE(LOWER(BTRIM(payload ->> 'discarded')), '') IN ('1','true','yes','deleted') OR (COALESCE(BTRIM(payload ->> 'status'), '') <> '' AND LOWER(BTRIM(payload ->> 'status')) <> 'active'));
    NEW.state_name := COALESCE(NULLIF(payload ->> 'state_name', ''), NULLIF(payload ->> 'state', ''));
          NEW.state_code := COALESCE(NULLIF(payload ->> 'state_code', ''));
          NEW.district_name := COALESCE(NULLIF(payload ->> 'district_name', ''), NULLIF(payload ->> 'district', ''));
          NEW.district_code := COALESCE(NULLIF(payload ->> 'district_code', ''));
          NEW.sub_district_name := COALESCE(NULLIF(payload ->> 'sub_district_name', ''), NULLIF(payload ->> 'sub_district', ''));
          NEW.sub_district_code := COALESCE(NULLIF(payload ->> 'sub_district_code', ''));
          NEW.block_name := COALESCE(NULLIF(payload ->> 'block_name', ''), NULLIF(payload ->> 'cd_block_name', ''), NULLIF(payload ->> 'block', ''));
          NEW.block_code := COALESCE(NULLIF(payload ->> 'block_code', ''), NULLIF(payload ->> 'cd_block_code', ''));
          NEW.gram_panchayat_name := COALESCE(NULLIF(payload ->> 'gram_panchayat_name', ''), NULLIF(payload ->> 'gram_panchayat', ''));
          NEW.gp_code := COALESCE(NULLIF(payload ->> 'gp_code', ''));
          NEW.village_name := COALESCE(NULLIF(payload ->> 'village_name', ''), NULLIF(payload ->> 'village', ''));
          NEW.village_code := COALESCE(NULLIF(payload ->> 'village_code', ''));
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: jj_module_master_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_master_sync() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
  target text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    target := jj_module_master_table(OLD.module_slug);
    IF target IS NOT NULL THEN
      EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id;
    END IF;
    RETURN NULL;
  END IF;

  -- An edit can move a row to a different master; clear the old one.
  IF TG_OP = 'UPDATE' AND (OLD.module_slug IS DISTINCT FROM NEW.module_slug OR OLD.id IS DISTINCT FROM NEW.id) THEN
    target := jj_module_master_table(OLD.module_slug);
    IF target IS NOT NULL THEN
      EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id;
    END IF;
  END IF;

  target := jj_module_master_table(NEW.module_slug);
  IF target IS NULL THEN
    RETURN NULL;
  END IF;

  EXECUTE format(
    'INSERT INTO %I (id, data, created_at, updated_at) VALUES ($1, $2, $3, $4)
     ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at',
    target
  ) USING
    NEW.id,
    CASE WHEN jsonb_typeof(NEW.data::jsonb) = 'object' THEN NEW.data::jsonb ELSE '{}'::jsonb END,
    NEW.created_at, NEW.updated_at;

  RETURN NULL;
END;
$_$;


--
-- Name: jj_module_master_table(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_master_table(slug text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  RETURN CASE slug
    WHEN 'month-master' THEN 'module_months'
          WHEN 'stakeholder-master' THEN 'module_stakeholders'
          WHEN 'stakeholder-role' THEN 'module_stakeholder_roles'
          WHEN 'role-name' THEN 'module_roles'
          WHEN 'parent-office-add' THEN 'module_parent_offices'
          WHEN 'office-category-add' THEN 'module_office_categories'
          WHEN 'office-mapping-add' THEN 'module_sub_offices'
          WHEN 'project-master' THEN 'module_projects'
          WHEN 'add-activity-group' THEN 'module_main_activities'
          WHEN 'add-vrp-activity' THEN 'module_sub_activities'
          WHEN 'jeevika-jankar-transfer' THEN 'module_jj_transfers'
          WHEN 'user-hierarchy-mapping' THEN 'module_user_hierarchies'
          WHEN 'access-control' THEN 'module_access_controls'
          WHEN 'add-vrp-type' THEN 'module_vrp_types'
          WHEN 'approval-master' THEN 'module_approvals'
          WHEN 'training-form' THEN 'module_trainings'
          WHEN 'other-target' THEN 'module_other_targets'
          WHEN 'other-target-with-farmer' THEN 'module_other_farmer_targets'
          WHEN 'jeevika-jankar-bill-process' THEN 'module_bills'
          WHEN 'jeevika-jankar-payment-detail' THEN 'module_payment_details'
    ELSE NULL
  END;
END;
$$;


--
-- Name: jj_module_mirrors_truncate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_mirrors_truncate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  TRUNCATE TABLE lg_states, lg_districts, lg_blocks, lg_gram_panchayats, lg_villages, module_months, module_stakeholders, module_stakeholder_roles, module_roles, module_parent_offices, module_office_categories, module_sub_offices, module_projects, module_main_activities, module_sub_activities, module_jj_transfers, module_user_hierarchies, module_access_controls, module_vrp_types, module_approvals, module_trainings, module_other_targets, module_other_farmer_targets, module_bills, module_payment_details;
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_record_versions_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_record_versions_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO module_record_read_versions (source_key, revision)
  SELECT source_key, nextval('module_record_read_version_seq') FROM (
    SELECT DISTINCT 'module:' || module_slug AS source_key
    FROM (SELECT module_slug FROM old_rows) AS affected WHERE module_slug IS NOT NULL
  ) AS keys ORDER BY source_key
  ON CONFLICT (source_key) DO UPDATE SET revision = EXCLUDED.revision;
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_record_versions_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_record_versions_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO module_record_read_versions (source_key, revision)
  SELECT source_key, nextval('module_record_read_version_seq') FROM (
    SELECT DISTINCT 'module:' || module_slug AS source_key
    FROM (SELECT module_slug FROM new_rows) AS affected WHERE module_slug IS NOT NULL
  ) AS keys ORDER BY source_key
  ON CONFLICT (source_key) DO UPDATE SET revision = EXCLUDED.revision;
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_record_versions_truncate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_record_versions_truncate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE module_record_read_versions SET revision = nextval('module_record_read_version_seq')
  WHERE source_key <> 'epoch';
  RETURN NULL;
END;
$$;


--
-- Name: jj_module_record_versions_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jj_module_record_versions_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO module_record_read_versions (source_key, revision)
  SELECT source_key, nextval('module_record_read_version_seq') FROM (
    SELECT DISTINCT 'module:' || module_slug AS source_key
    FROM (SELECT module_slug FROM new_rows UNION SELECT module_slug FROM old_rows) AS affected WHERE module_slug IS NOT NULL
  ) AS keys ORDER BY source_key
  ON CONFLICT (source_key) DO UPDATE SET revision = EXCLUDED.revision;
  RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    blob_id integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    record_id integer NOT NULL,
    record_type character varying NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    content_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    filename character varying NOT NULL,
    key character varying NOT NULL,
    metadata text,
    service_name character varying NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id integer NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: afls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.afls (
    id bigint NOT NULL,
    fco_id character varying,
    fco character varying,
    fpo_id character varying,
    ics_id character varying,
    village_id character varying,
    ginning_id character varying,
    broker_id character varying,
    farmer_name character varying,
    father_name character varying,
    tracenet_no character varying,
    total_farm_area numeric(18,4),
    purchase_quantity_amount numeric(18,4),
    estimate_quantity numeric(18,4),
    purchase_quantity numeric(18,4),
    purchase_date date,
    dispoce character varying,
    ip character varying,
    date date,
    estimate_quantity_admin numeric(18,4),
    slip_no character varying,
    mobile_no character varying,
    purchase_product character varying,
    purchase_product_type character varying,
    khasara_no character varying,
    longitude numeric(20,8),
    lattitude numeric(20,8),
    aadhar character varying,
    reg_type character varying,
    fy character varying,
    qr_aadhar character varying,
    qr_mobile character varying,
    qrcode text,
    qrcode_date timestamp(6) without time zone,
    status character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    fpo_name character varying,
    ics_name character varying,
    village_name character varying,
    import_key character varying,
    farm_id character varying
);


--
-- Name: afls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.afls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: afls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.afls_id_seq OWNED BY public.afls.id;


--
-- Name: app_user_logins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_user_logins (
    id bigint NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    name character varying,
    username character varying,
    mobile_no character varying,
    role character varying,
    office_name character varying,
    fcoc character varying,
    login_method character varying DEFAULT 'password'::character varying NOT NULL,
    ip character varying,
    device character varying,
    app_version character varying,
    logged_in_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: app_user_logins_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.app_user_logins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: app_user_logins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.app_user_logins_id_seq OWNED BY public.app_user_logins.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: asa360_master; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asa360_master (
    id bigint NOT NULL,
    o_type character varying(50),
    o_name character varying(200),
    o_id integer
);


--
-- Name: asa360_master_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.asa360_master_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: asa360_master_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.asa360_master_id_seq OWNED BY public.asa360_master.id;


--
-- Name: farmer_app_login_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.farmer_app_login_events (
    id bigint NOT NULL,
    farmer_app_login_id bigint NOT NULL,
    logged_in_at timestamp(6) without time zone NOT NULL,
    identifier_type character varying,
    ip character varying,
    device character varying,
    app_version character varying,
    latitude numeric(10,7),
    longitude numeric(10,7),
    place character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: farmer_app_login_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.farmer_app_login_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: farmer_app_login_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.farmer_app_login_events_id_seq OWNED BY public.farmer_app_login_events.id;


--
-- Name: farmer_app_logins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.farmer_app_logins (
    id bigint NOT NULL,
    farmer_external_id character varying,
    full_name character varying,
    mobile_no character varying,
    aadhaar_last4 character varying(4),
    aadhaar_digest character varying,
    last_identifier_type character varying,
    father_husband_name character varying,
    village_name character varying,
    block_name character varying,
    district_name character varying,
    state_name character varying,
    fco_name character varying,
    ics_name character varying,
    tracenet_id character varying,
    login_count integer DEFAULT 0 NOT NULL,
    first_logged_in_at timestamp(6) without time zone,
    last_logged_in_at timestamp(6) without time zone,
    last_login_ip character varying,
    last_device character varying,
    last_app_version character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    last_login_latitude numeric(10,7),
    last_login_longitude numeric(10,7),
    last_login_place character varying,
    state_id character varying
);


--
-- Name: farmer_app_logins_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.farmer_app_logins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: farmer_app_logins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.farmer_app_logins_id_seq OWNED BY public.farmer_app_logins.id;


--
-- Name: farmer_devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.farmer_devices (
    id bigint NOT NULL,
    farmer_app_login_id bigint NOT NULL,
    token character varying NOT NULL,
    platform character varying,
    app_version character varying,
    last_seen_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: farmer_devices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.farmer_devices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: farmer_devices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.farmer_devices_id_seq OWNED BY public.farmer_devices.id;


--
-- Name: farmer_login_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.farmer_login_locks (
    id bigint NOT NULL,
    mobile_no character varying NOT NULL,
    failed_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp(6) without time zone,
    last_failed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: farmer_login_locks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.farmer_login_locks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: farmer_login_locks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.farmer_login_locks_id_seq OWNED BY public.farmer_login_locks.id;


--
-- Name: farmer_login_otps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.farmer_login_otps (
    id bigint NOT NULL,
    jti character varying NOT NULL,
    mobile_no character varying NOT NULL,
    identifier_type character varying,
    aadhaar_digest character varying,
    otp_digest character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    consumed_at timestamp(6) without time zone,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: farmer_login_otps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.farmer_login_otps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: farmer_login_otps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.farmer_login_otps_id_seq OWNED BY public.farmer_login_otps.id;


--
-- Name: farmer_news; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.farmer_news (
    id bigint NOT NULL,
    title character varying NOT NULL,
    body text,
    link_url character varying,
    image_path character varying,
    state_id character varying,
    state_name character varying,
    status character varying DEFAULT 'Active'::character varying NOT NULL,
    published_at timestamp(6) without time zone NOT NULL,
    created_by character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: farmer_news_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.farmer_news_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: farmer_news_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.farmer_news_id_seq OWNED BY public.farmer_news.id;


--
-- Name: farmer_push_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.farmer_push_messages (
    id bigint NOT NULL,
    notifiable_type character varying NOT NULL,
    notifiable_id bigint NOT NULL,
    title character varying,
    body text,
    state_id character varying,
    device_count integer DEFAULT 0 NOT NULL,
    sent_count integer DEFAULT 0 NOT NULL,
    failed_count integer DEFAULT 0 NOT NULL,
    status character varying DEFAULT 'Pending'::character varying NOT NULL,
    error text,
    sent_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: farmer_push_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.farmer_push_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: farmer_push_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.farmer_push_messages_id_seq OWNED BY public.farmer_push_messages.id;


--
-- Name: farmer_videos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.farmer_videos (
    id bigint NOT NULL,
    title character varying NOT NULL,
    description text,
    video_url character varying,
    video_path character varying,
    thumbnail_path character varying,
    duration_label character varying,
    state_id character varying,
    state_name character varying,
    status character varying DEFAULT 'Active'::character varying NOT NULL,
    published_at timestamp(6) without time zone NOT NULL,
    created_by character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: farmer_videos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.farmer_videos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: farmer_videos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.farmer_videos_id_seq OWNED BY public.farmer_videos.id;


--
-- Name: jj_quiz_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jj_quiz_answers (
    id bigint NOT NULL,
    jj_quiz_attempt_id bigint NOT NULL,
    jj_quiz_question_id bigint NOT NULL,
    selected_option character varying,
    correct_option character varying NOT NULL,
    correct boolean DEFAULT false NOT NULL,
    marks_awarded numeric(8,2) DEFAULT 0.0 NOT NULL,
    question_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: jj_quiz_answers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jj_quiz_answers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jj_quiz_answers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jj_quiz_answers_id_seq OWNED BY public.jj_quiz_answers.id;


--
-- Name: jj_quiz_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jj_quiz_attempts (
    id bigint NOT NULL,
    jj_quiz_id bigint NOT NULL,
    vrp_id bigint NOT NULL,
    access_token character varying NOT NULL,
    status character varying DEFAULT 'qr_issued'::character varying NOT NULL,
    started_at timestamp(6) without time zone,
    expires_at timestamp(6) without time zone,
    submitted_at timestamp(6) without time zone,
    score numeric(10,2) DEFAULT 0.0 NOT NULL,
    total_marks numeric(10,2) DEFAULT 0.0 NOT NULL,
    percentage numeric(7,2) DEFAULT 0.0 NOT NULL,
    passed boolean DEFAULT false NOT NULL,
    login_ip character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: jj_quiz_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jj_quiz_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jj_quiz_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jj_quiz_attempts_id_seq OWNED BY public.jj_quiz_attempts.id;


--
-- Name: jj_quiz_questions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jj_quiz_questions (
    id bigint NOT NULL,
    jj_quiz_id bigint NOT NULL,
    question_text text NOT NULL,
    option_a character varying NOT NULL,
    option_b character varying NOT NULL,
    option_c character varying,
    option_d character varying,
    correct_option character varying NOT NULL,
    marks numeric(8,2) DEFAULT 1.0 NOT NULL,
    "position" integer DEFAULT 1 NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: jj_quiz_questions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jj_quiz_questions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jj_quiz_questions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jj_quiz_questions_id_seq OWNED BY public.jj_quiz_questions.id;


--
-- Name: jj_quizzes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jj_quizzes (
    id bigint NOT NULL,
    title character varying NOT NULL,
    description text,
    duration_minutes integer DEFAULT 30 NOT NULL,
    passing_marks numeric(8,2),
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    starts_at timestamp(6) without time zone,
    ends_at timestamp(6) without time zone,
    allow_retake boolean DEFAULT false NOT NULL,
    created_by_type character varying,
    created_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: jj_quizzes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jj_quizzes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jj_quizzes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jj_quizzes_id_seq OWNED BY public.jj_quizzes.id;


--
-- Name: module_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.module_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lg_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lg_blocks (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    status character varying,
    state_name character varying,
    state_code character varying,
    district_name character varying,
    district_code character varying,
    sub_district_name character varying,
    sub_district_code character varying,
    block_name character varying,
    block_code character varying,
    gram_panchayat_name character varying,
    gp_code character varying,
    village_name character varying,
    village_code character varying,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: lg_districts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lg_districts (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    status character varying,
    state_name character varying,
    state_code character varying,
    district_name character varying,
    district_code character varying,
    sub_district_name character varying,
    sub_district_code character varying,
    block_name character varying,
    block_code character varying,
    gram_panchayat_name character varying,
    gp_code character varying,
    village_name character varying,
    village_code character varying,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: lg_gram_panchayats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lg_gram_panchayats (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    status character varying,
    state_name character varying,
    state_code character varying,
    district_name character varying,
    district_code character varying,
    sub_district_name character varying,
    sub_district_code character varying,
    block_name character varying,
    block_code character varying,
    gram_panchayat_name character varying,
    gp_code character varying,
    village_name character varying,
    village_code character varying,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: lg_states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lg_states (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    status character varying,
    state_name character varying,
    state_code character varying,
    district_name character varying,
    district_code character varying,
    sub_district_name character varying,
    sub_district_code character varying,
    block_name character varying,
    block_code character varying,
    gram_panchayat_name character varying,
    gp_code character varying,
    village_name character varying,
    village_code character varying,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: lg_villages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lg_villages (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    status character varying,
    state_name character varying,
    state_code character varying,
    district_name character varying,
    district_code character varying,
    sub_district_name character varying,
    sub_district_code character varying,
    block_name character varying,
    block_code character varying,
    gram_panchayat_name character varying,
    gp_code character varying,
    village_name character varying,
    village_code character varying,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_access_control_list_b9d538d4; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_access_control_list_b9d538d4 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'access-control-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_access_controls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_access_controls (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stakeholder text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder'::text)), ''::text)) STORED,
    stakeholder_role text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_role'::text)), ''::text)) STORED,
    role_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'role_name'::text)), ''::text)) STORED,
    can_view text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'can_view'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'access-control'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_activity_group_list_34a52e96; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_activity_group_list_34a52e96 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'activity-group-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_activity_master_2e19bce0; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_activity_master_2e19bce0 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'activity-master'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_all_user_b8d83be4; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_all_user_b8d83be4 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'all-user'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_approval_list_27d1da1f; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_approval_list_27d1da1f (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'approval-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_approval_status_summary_1483b5d5; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_approval_status_summary_1483b5d5 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'approval-status-summary'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_approvals (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    module_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'module_name'::text)), ''::text)) STORED,
    approval_level text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'approval_level'::text)), ''::text)) STORED,
    stakeholder_role text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_role'::text)), ''::text)) STORED,
    role_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'role_name'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'approval-master'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_bank_master_9e57e6ab; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_bank_master_9e57e6ab (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'bank-master'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_bill_approval_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_bill_approval_histories (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'jeevika-jankar-bill-approval-history'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_bills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_bills (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    bill_month text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'bill_month'::text)), ''::text)) STORED,
    select_vrp text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'select_vrp'::text)), ''::text)) STORED,
    bill_status text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'status'::text)), ''::text)) STORED,
    grand_total text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'grand_total'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text]))))) STORED,
    source_slug character varying DEFAULT 'jeevika-jankar-bill-process'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_entry_order_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.module_entry_order_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: module_entry_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_entry_identities (
    id bigint NOT NULL,
    module_slug character varying NOT NULL,
    storage_order bigint DEFAULT nextval('public.module_entry_order_seq'::regclass) NOT NULL
);


--
-- Name: module_farmer_forms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_farmer_forms (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'add-farmer-form'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_ics_master_483e7ffc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_ics_master_483e7ffc (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'ics-master'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_jeevika_jankar_bill_list_083c76c4; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_jeevika_jankar_bill_list_083c76c4 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'jeevika-jankar-bill-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_jeevika_jankar_completed_payment_l_bad7b61b; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_jeevika_jankar_completed_payment_l_bad7b61b (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'jeevika-jankar-completed-payment-list'::character varying CONSTRAINT module_jeevika_jankar_completed_payment_l__source_slug_not_null NOT NULL,
    data jsonb DEFAULT '{}'::jsonb CONSTRAINT module_jeevika_jankar_completed_payment_l_bad7b61_data_not_null NOT NULL,
    created_at timestamp(6) without time zone CONSTRAINT module_jeevika_jankar_completed_payment_l_b_created_at_not_null NOT NULL,
    updated_at timestamp(6) without time zone CONSTRAINT module_jeevika_jankar_completed_payment_l_b_updated_at_not_null NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_jeevika_jankar_observation_list_9bfb7dc5; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_jeevika_jankar_observation_list_9bfb7dc5 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'jeevika-jankar-observation-list'::character varying CONSTRAINT module_jeevika_jankar_observation_list_9bf_source_slug_not_null NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone CONSTRAINT module_jeevika_jankar_observation_list_9bfb_created_at_not_null NOT NULL,
    updated_at timestamp(6) without time zone CONSTRAINT module_jeevika_jankar_observation_list_9bfb_updated_at_not_null NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_jeevika_jankar_payment_list_2e70d942; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_jeevika_jankar_payment_list_2e70d942 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'jeevika-jankar-payment-list'::character varying CONSTRAINT module_jeevika_jankar_payment_list_2e70d94_source_slug_not_null NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_jeevika_jankar_payment_list_detail_d8114659; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_jeevika_jankar_payment_list_detail_d8114659 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'jeevika-jankar-payment-list-detail'::character varying CONSTRAINT module_jeevika_jankar_payment_list_detail__source_slug_not_null NOT NULL,
    data jsonb DEFAULT '{}'::jsonb CONSTRAINT module_jeevika_jankar_payment_list_detail_d811465_data_not_null NOT NULL,
    created_at timestamp(6) without time zone CONSTRAINT module_jeevika_jankar_payment_list_detail_d_created_at_not_null NOT NULL,
    updated_at timestamp(6) without time zone CONSTRAINT module_jeevika_jankar_payment_list_detail_d_updated_at_not_null NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_jeevika_jankar_transfer_list_73f1674d; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_jeevika_jankar_transfer_list_73f1674d (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'jeevika-jankar-transfer-list'::character varying CONSTRAINT module_jeevika_jankar_transfer_list_73f167_source_slug_not_null NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone CONSTRAINT module_jeevika_jankar_transfer_list_73f1674_created_at_not_null NOT NULL,
    updated_at timestamp(6) without time zone CONSTRAINT module_jeevika_jankar_transfer_list_73f1674_updated_at_not_null NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_jj_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_jj_transfers (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stakeholder_category text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)) STORED,
    user_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'user_name'::text)), ''::text)) STORED,
    fcoc text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'fcoc'::text)), ''::text)) STORED,
    sidebar_menu text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'sidebar_menu'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'jeevika-jankar-transfer'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_lg_directory_import_status_0543ee43; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_lg_directory_import_status_0543ee43 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'lg-directory-import-status'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_main_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_main_activities (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    main_activity_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'main_activity_name'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'add-activity-group'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_monthly_bill_summary_816eb1f0; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_monthly_bill_summary_816eb1f0 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'monthly-bill-summary'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_months; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_months (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    month_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'month_name'::text)), ''::text)) STORED,
    financial_year text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'financial_year'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'month-master'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_new_user_6724757d; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_new_user_6724757d (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'new-user'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_office_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_office_categories (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stakeholder_category text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)) STORED,
    parent_category text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'parent_category'::text)), ''::text)) STORED,
    office_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'office_name'::text)), ''::text)) STORED,
    office_level text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'office_level'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'office-category-add'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_office_list_286e3232; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_office_list_286e3232 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'office-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_other_farmer_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_other_farmer_targets (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    month text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'month'::text)), ''::text)) STORED,
    jeevika_jankar_id text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'jeevika_jankar_id'::text)), ''::text)) STORED,
    fcoc_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'fcoc_name'::text)), ''::text)) STORED,
    target_mapping_id text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'target_mapping_id'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'other-target-with-farmer'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_other_target_list_410d4f4c; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_other_target_list_410d4f4c (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'other-target-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_other_target_with_farmer_list_0d98bf9f; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_other_target_with_farmer_list_0d98bf9f (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'other-target-with-farmer-list'::character varying CONSTRAINT module_other_target_with_farmer_list_0d98b_source_slug_not_null NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone CONSTRAINT module_other_target_with_farmer_list_0d98bf_created_at_not_null NOT NULL,
    updated_at timestamp(6) without time zone CONSTRAINT module_other_target_with_farmer_list_0d98bf_updated_at_not_null NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_other_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_other_targets (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    month text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'month'::text)), ''::text)) STORED,
    jeevika_jankar_id text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'jeevika_jankar_id'::text)), ''::text)) STORED,
    fcoc_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'fcoc_name'::text)), ''::text)) STORED,
    ics_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'ics_name'::text)), ''::text)) STORED,
    target_mapping_id text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'target_mapping_id'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'other-target'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_papl360_target_e2ff67fc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_papl360_target_e2ff67fc (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'papl360-target'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_papl360_target_list_08d81bec; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_papl360_target_list_08d81bec (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'papl360-target-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_parent_offices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_parent_offices (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stakeholder_category text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)) STORED,
    parent_office_type text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'parent_office_type'::text)), ''::text)) STORED,
    parent_office_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'parent_office_name'::text)), ''::text)) STORED,
    parent_office text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'parent_office'::text)), ''::text)) STORED,
    office_level text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'office_level'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'parent-office-add'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_payment_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_payment_details (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    bill_month text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'bill_month'::text)), ''::text)) STORED,
    select_vrp text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'select_vrp'::text)), ''::text)) STORED,
    bill_status text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'status'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text]))))) STORED,
    source_slug character varying DEFAULT 'jeevika-jankar-payment-detail'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_payment_status_report_17d409eb; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_payment_status_report_17d409eb (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'payment-status-report'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_person_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_person_types (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'person-type'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_position_type_486dc9a9; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_position_type_486dc9a9 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'position-type'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_projects (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    project_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'project_name'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'project-master'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_role_managements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_role_managements (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'role-management'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_roles (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stakeholder_category text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)) STORED,
    stakeholder_role text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_role'::text)), ''::text)) STORED,
    role_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'role_name'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'role-name'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_seed_distribution_target_list_5453661e; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_seed_distribution_target_list_5453661e (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'seed-distribution-target-list'::character varying CONSTRAINT module_seed_distribution_target_list_54536_source_slug_not_null NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone CONSTRAINT module_seed_distribution_target_list_545366_created_at_not_null NOT NULL,
    updated_at timestamp(6) without time zone CONSTRAINT module_seed_distribution_target_list_545366_updated_at_not_null NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_seed_distribution_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_seed_distribution_targets (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'seed-distribution-target'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_stakeholder_profile_603e5d20; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_stakeholder_profile_603e5d20 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'stakeholder-profile'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_stakeholder_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_stakeholder_roles (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stakeholder_category text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)) STORED,
    stakeholder_role text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_role'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'stakeholder-role'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_stakeholders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_stakeholders (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stakeholder_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_name_in_english'::text)), ''::text)) STORED,
    stakeholder_name_hindi text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_name_in_hindi'::text)), ''::text)) STORED,
    logo_upload text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'logo_upload'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'stakeholder-master'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_sub_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_sub_activities (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    main_activity text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'main_activity'::text)), ''::text)) STORED,
    sub_activity_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'sub_activity_name'::text)), ''::text)) STORED,
    unit text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'unit'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'add-vrp-activity'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_sub_offices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_sub_offices (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stakeholder_category text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)) STORED,
    parent_category text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'parent_category'::text)), ''::text)) STORED,
    office_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'office_name'::text)), ''::text)) STORED,
    sub_office_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'sub_office_name'::text)), ''::text)) STORED,
    office_level text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'office_level'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'office-mapping-add'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_task_completion_indicator_2dc4f3fb; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_task_completion_indicator_2dc4f3fb (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'task-completion-indicator'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_task_completion_indicator_list_fc8d2b85; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_task_completion_indicator_list_fc8d2b85 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'task-completion-indicator-list'::character varying CONSTRAINT module_task_completion_indicator_list_fc8d_source_slug_not_null NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone CONSTRAINT module_task_completion_indicator_list_fc8d2_created_at_not_null NOT NULL,
    updated_at timestamp(6) without time zone CONSTRAINT module_task_completion_indicator_list_fc8d2_updated_at_not_null NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_task_indicator_master_c07b884a; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_task_indicator_master_c07b884a (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'task-indicator-master'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_training_edit_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_training_edit_requests (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'training-form-edit-request'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_training_form_list_88933913; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_training_form_list_88933913 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'training-form-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_training_topic_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_training_topic_mappings (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'training-topic-mapping'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_trainings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_trainings (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    month text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'month'::text)), ''::text)) STORED,
    main_activity text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'main_activity'::text)), ''::text)) STORED,
    sub_activity text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'sub_activity'::text)), ''::text)) STORED,
    training_method text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'training_method'::text)), ''::text)) STORED,
    main_activity_type text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'main_activity_type'::text)), ''::text)) STORED,
    jeevika_jankar_id text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'jeevika_jankar_id'::text)), ''::text)) STORED,
    cluster_coordinator_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'cluster_coordinator_name'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'training-form'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_user_hierarchies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_user_hierarchies (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    level_1_user text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'level_1_user'::text)), ''::text)) STORED,
    level_2_user text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'level_2_user'::text)), ''::text)) STORED,
    level_3_user text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'level_3_user'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'user-hierarchy-mapping'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_user_hierarchy_list_a4542a91; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_user_hierarchy_list_a4542a91 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'user-hierarchy-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_user_management_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_user_management_roles (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'user-management-role'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_vrp_active_status_history_5a746fcf; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_vrp_active_status_history_5a746fcf (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'vrp-active-status-history'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_vrp_activity_list_7d178b72; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_vrp_activity_list_7d178b72 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'vrp-activity-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_vrp_approval_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_vrp_approval_histories (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'vrp-approval-history'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_vrp_bill_add_50a221ea; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_vrp_bill_add_50a221ea (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'vrp-bill-add'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_vrp_bill_list_0ef6fdc4; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_vrp_bill_list_0ef6fdc4 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'vrp-bill-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_vrp_registration_list_6a8aeba6; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_vrp_registration_list_6a8aeba6 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'vrp-registration-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_vrp_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_vrp_types (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    vrp_type_name text GENERATED ALWAYS AS (NULLIF(btrim((data ->> 'vrp_type_name'::text)), ''::text)) STORED,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    source_slug character varying DEFAULT 'add-vrp-type'::character varying NOT NULL,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_weekly_activity_progress_22c35d60; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_weekly_activity_progress_22c35d60 (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'weekly-activity-progress'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_weekly_progress_report_1157600e; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_weekly_progress_report_1157600e (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'weekly-progress-report'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_weekly_target_add_ef9d741d; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_weekly_target_add_ef9d741d (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'weekly-target-add'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_weekly_target_list_91c4fe5d; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_weekly_target_list_91c4fe5d (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    source_slug character varying DEFAULT 'weekly-target-list'::character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status text GENERATED ALWAYS AS ((data ->> 'status'::text)) STORED,
    active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED,
    payload_text text,
    catalogue_active boolean GENERATED ALWAYS AS ((NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))) STORED
);


--
-- Name: module_entries; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.module_entries AS
 SELECT stored.id,
    stored.module_slug,
    stored.data,
    stored.created_at,
    stored.updated_at,
    stored.xmin,
    stored.ctid,
    identities.storage_order
   FROM (( SELECT module_access_controls.id,
            'access-control'::text AS module_slug,
            module_access_controls.payload_text AS data,
            module_access_controls.created_at,
            module_access_controls.updated_at,
            (module_access_controls.xmin)::text AS xmin,
            (module_access_controls.ctid)::text AS ctid
           FROM public.module_access_controls
        UNION ALL
         SELECT module_access_control_list_b9d538d4.id,
            'access-control-list'::text AS module_slug,
            module_access_control_list_b9d538d4.payload_text AS data,
            module_access_control_list_b9d538d4.created_at,
            module_access_control_list_b9d538d4.updated_at,
            (module_access_control_list_b9d538d4.xmin)::text AS xmin,
            (module_access_control_list_b9d538d4.ctid)::text AS ctid
           FROM public.module_access_control_list_b9d538d4
        UNION ALL
         SELECT module_activity_group_list_34a52e96.id,
            'activity-group-list'::text AS module_slug,
            module_activity_group_list_34a52e96.payload_text AS data,
            module_activity_group_list_34a52e96.created_at,
            module_activity_group_list_34a52e96.updated_at,
            (module_activity_group_list_34a52e96.xmin)::text AS xmin,
            (module_activity_group_list_34a52e96.ctid)::text AS ctid
           FROM public.module_activity_group_list_34a52e96
        UNION ALL
         SELECT module_activity_master_2e19bce0.id,
            'activity-master'::text AS module_slug,
            module_activity_master_2e19bce0.payload_text AS data,
            module_activity_master_2e19bce0.created_at,
            module_activity_master_2e19bce0.updated_at,
            (module_activity_master_2e19bce0.xmin)::text AS xmin,
            (module_activity_master_2e19bce0.ctid)::text AS ctid
           FROM public.module_activity_master_2e19bce0
        UNION ALL
         SELECT module_main_activities.id,
            'add-activity-group'::text AS module_slug,
            module_main_activities.payload_text AS data,
            module_main_activities.created_at,
            module_main_activities.updated_at,
            (module_main_activities.xmin)::text AS xmin,
            (module_main_activities.ctid)::text AS ctid
           FROM public.module_main_activities
        UNION ALL
         SELECT module_farmer_forms.id,
            'add-farmer-form'::text AS module_slug,
            module_farmer_forms.payload_text AS data,
            module_farmer_forms.created_at,
            module_farmer_forms.updated_at,
            (module_farmer_forms.xmin)::text AS xmin,
            (module_farmer_forms.ctid)::text AS ctid
           FROM public.module_farmer_forms
        UNION ALL
         SELECT module_sub_activities.id,
            'add-vrp-activity'::text AS module_slug,
            module_sub_activities.payload_text AS data,
            module_sub_activities.created_at,
            module_sub_activities.updated_at,
            (module_sub_activities.xmin)::text AS xmin,
            (module_sub_activities.ctid)::text AS ctid
           FROM public.module_sub_activities
        UNION ALL
         SELECT module_vrp_types.id,
            'add-vrp-type'::text AS module_slug,
            module_vrp_types.payload_text AS data,
            module_vrp_types.created_at,
            module_vrp_types.updated_at,
            (module_vrp_types.xmin)::text AS xmin,
            (module_vrp_types.ctid)::text AS ctid
           FROM public.module_vrp_types
        UNION ALL
         SELECT module_all_user_b8d83be4.id,
            'all-user'::text AS module_slug,
            module_all_user_b8d83be4.payload_text AS data,
            module_all_user_b8d83be4.created_at,
            module_all_user_b8d83be4.updated_at,
            (module_all_user_b8d83be4.xmin)::text AS xmin,
            (module_all_user_b8d83be4.ctid)::text AS ctid
           FROM public.module_all_user_b8d83be4
        UNION ALL
         SELECT module_approval_list_27d1da1f.id,
            'approval-list'::text AS module_slug,
            module_approval_list_27d1da1f.payload_text AS data,
            module_approval_list_27d1da1f.created_at,
            module_approval_list_27d1da1f.updated_at,
            (module_approval_list_27d1da1f.xmin)::text AS xmin,
            (module_approval_list_27d1da1f.ctid)::text AS ctid
           FROM public.module_approval_list_27d1da1f
        UNION ALL
         SELECT module_approvals.id,
            'approval-master'::text AS module_slug,
            module_approvals.payload_text AS data,
            module_approvals.created_at,
            module_approvals.updated_at,
            (module_approvals.xmin)::text AS xmin,
            (module_approvals.ctid)::text AS ctid
           FROM public.module_approvals
        UNION ALL
         SELECT module_approval_status_summary_1483b5d5.id,
            'approval-status-summary'::text AS module_slug,
            module_approval_status_summary_1483b5d5.payload_text AS data,
            module_approval_status_summary_1483b5d5.created_at,
            module_approval_status_summary_1483b5d5.updated_at,
            (module_approval_status_summary_1483b5d5.xmin)::text AS xmin,
            (module_approval_status_summary_1483b5d5.ctid)::text AS ctid
           FROM public.module_approval_status_summary_1483b5d5
        UNION ALL
         SELECT module_bank_master_9e57e6ab.id,
            'bank-master'::text AS module_slug,
            module_bank_master_9e57e6ab.payload_text AS data,
            module_bank_master_9e57e6ab.created_at,
            module_bank_master_9e57e6ab.updated_at,
            (module_bank_master_9e57e6ab.xmin)::text AS xmin,
            (module_bank_master_9e57e6ab.ctid)::text AS ctid
           FROM public.module_bank_master_9e57e6ab
        UNION ALL
         SELECT lg_blocks.id,
            'block-master'::text AS module_slug,
            lg_blocks.payload_text AS data,
            lg_blocks.created_at,
            lg_blocks.updated_at,
            (lg_blocks.xmin)::text AS xmin,
            (lg_blocks.ctid)::text AS ctid
           FROM public.lg_blocks
        UNION ALL
         SELECT lg_districts.id,
            'district-master'::text AS module_slug,
            lg_districts.payload_text AS data,
            lg_districts.created_at,
            lg_districts.updated_at,
            (lg_districts.xmin)::text AS xmin,
            (lg_districts.ctid)::text AS ctid
           FROM public.lg_districts
        UNION ALL
         SELECT lg_gram_panchayats.id,
            'gram-panchayat-master'::text AS module_slug,
            lg_gram_panchayats.payload_text AS data,
            lg_gram_panchayats.created_at,
            lg_gram_panchayats.updated_at,
            (lg_gram_panchayats.xmin)::text AS xmin,
            (lg_gram_panchayats.ctid)::text AS ctid
           FROM public.lg_gram_panchayats
        UNION ALL
         SELECT module_ics_master_483e7ffc.id,
            'ics-master'::text AS module_slug,
            module_ics_master_483e7ffc.payload_text AS data,
            module_ics_master_483e7ffc.created_at,
            module_ics_master_483e7ffc.updated_at,
            (module_ics_master_483e7ffc.xmin)::text AS xmin,
            (module_ics_master_483e7ffc.ctid)::text AS ctid
           FROM public.module_ics_master_483e7ffc
        UNION ALL
         SELECT module_bill_approval_histories.id,
            'jeevika-jankar-bill-approval-history'::text AS module_slug,
            module_bill_approval_histories.payload_text AS data,
            module_bill_approval_histories.created_at,
            module_bill_approval_histories.updated_at,
            (module_bill_approval_histories.xmin)::text AS xmin,
            (module_bill_approval_histories.ctid)::text AS ctid
           FROM public.module_bill_approval_histories
        UNION ALL
         SELECT module_jeevika_jankar_bill_list_083c76c4.id,
            'jeevika-jankar-bill-list'::text AS module_slug,
            module_jeevika_jankar_bill_list_083c76c4.payload_text AS data,
            module_jeevika_jankar_bill_list_083c76c4.created_at,
            module_jeevika_jankar_bill_list_083c76c4.updated_at,
            (module_jeevika_jankar_bill_list_083c76c4.xmin)::text AS xmin,
            (module_jeevika_jankar_bill_list_083c76c4.ctid)::text AS ctid
           FROM public.module_jeevika_jankar_bill_list_083c76c4
        UNION ALL
         SELECT module_bills.id,
            'jeevika-jankar-bill-process'::text AS module_slug,
            module_bills.payload_text AS data,
            module_bills.created_at,
            module_bills.updated_at,
            (module_bills.xmin)::text AS xmin,
            (module_bills.ctid)::text AS ctid
           FROM public.module_bills
        UNION ALL
         SELECT module_jeevika_jankar_completed_payment_l_bad7b61b.id,
            'jeevika-jankar-completed-payment-list'::text AS module_slug,
            module_jeevika_jankar_completed_payment_l_bad7b61b.payload_text AS data,
            module_jeevika_jankar_completed_payment_l_bad7b61b.created_at,
            module_jeevika_jankar_completed_payment_l_bad7b61b.updated_at,
            (module_jeevika_jankar_completed_payment_l_bad7b61b.xmin)::text AS xmin,
            (module_jeevika_jankar_completed_payment_l_bad7b61b.ctid)::text AS ctid
           FROM public.module_jeevika_jankar_completed_payment_l_bad7b61b
        UNION ALL
         SELECT module_jeevika_jankar_observation_list_9bfb7dc5.id,
            'jeevika-jankar-observation-list'::text AS module_slug,
            module_jeevika_jankar_observation_list_9bfb7dc5.payload_text AS data,
            module_jeevika_jankar_observation_list_9bfb7dc5.created_at,
            module_jeevika_jankar_observation_list_9bfb7dc5.updated_at,
            (module_jeevika_jankar_observation_list_9bfb7dc5.xmin)::text AS xmin,
            (module_jeevika_jankar_observation_list_9bfb7dc5.ctid)::text AS ctid
           FROM public.module_jeevika_jankar_observation_list_9bfb7dc5
        UNION ALL
         SELECT module_payment_details.id,
            'jeevika-jankar-payment-detail'::text AS module_slug,
            module_payment_details.payload_text AS data,
            module_payment_details.created_at,
            module_payment_details.updated_at,
            (module_payment_details.xmin)::text AS xmin,
            (module_payment_details.ctid)::text AS ctid
           FROM public.module_payment_details
        UNION ALL
         SELECT module_jeevika_jankar_payment_list_2e70d942.id,
            'jeevika-jankar-payment-list'::text AS module_slug,
            module_jeevika_jankar_payment_list_2e70d942.payload_text AS data,
            module_jeevika_jankar_payment_list_2e70d942.created_at,
            module_jeevika_jankar_payment_list_2e70d942.updated_at,
            (module_jeevika_jankar_payment_list_2e70d942.xmin)::text AS xmin,
            (module_jeevika_jankar_payment_list_2e70d942.ctid)::text AS ctid
           FROM public.module_jeevika_jankar_payment_list_2e70d942
        UNION ALL
         SELECT module_jeevika_jankar_payment_list_detail_d8114659.id,
            'jeevika-jankar-payment-list-detail'::text AS module_slug,
            module_jeevika_jankar_payment_list_detail_d8114659.payload_text AS data,
            module_jeevika_jankar_payment_list_detail_d8114659.created_at,
            module_jeevika_jankar_payment_list_detail_d8114659.updated_at,
            (module_jeevika_jankar_payment_list_detail_d8114659.xmin)::text AS xmin,
            (module_jeevika_jankar_payment_list_detail_d8114659.ctid)::text AS ctid
           FROM public.module_jeevika_jankar_payment_list_detail_d8114659
        UNION ALL
         SELECT module_jj_transfers.id,
            'jeevika-jankar-transfer'::text AS module_slug,
            module_jj_transfers.payload_text AS data,
            module_jj_transfers.created_at,
            module_jj_transfers.updated_at,
            (module_jj_transfers.xmin)::text AS xmin,
            (module_jj_transfers.ctid)::text AS ctid
           FROM public.module_jj_transfers
        UNION ALL
         SELECT module_jeevika_jankar_transfer_list_73f1674d.id,
            'jeevika-jankar-transfer-list'::text AS module_slug,
            module_jeevika_jankar_transfer_list_73f1674d.payload_text AS data,
            module_jeevika_jankar_transfer_list_73f1674d.created_at,
            module_jeevika_jankar_transfer_list_73f1674d.updated_at,
            (module_jeevika_jankar_transfer_list_73f1674d.xmin)::text AS xmin,
            (module_jeevika_jankar_transfer_list_73f1674d.ctid)::text AS ctid
           FROM public.module_jeevika_jankar_transfer_list_73f1674d
        UNION ALL
         SELECT module_lg_directory_import_status_0543ee43.id,
            'lg-directory-import-status'::text AS module_slug,
            module_lg_directory_import_status_0543ee43.payload_text AS data,
            module_lg_directory_import_status_0543ee43.created_at,
            module_lg_directory_import_status_0543ee43.updated_at,
            (module_lg_directory_import_status_0543ee43.xmin)::text AS xmin,
            (module_lg_directory_import_status_0543ee43.ctid)::text AS ctid
           FROM public.module_lg_directory_import_status_0543ee43
        UNION ALL
         SELECT lg_villages.id,
            (lg_villages.source_slug)::text AS module_slug,
            lg_villages.payload_text AS data,
            lg_villages.created_at,
            lg_villages.updated_at,
            (lg_villages.xmin)::text AS xmin,
            (lg_villages.ctid)::text AS ctid
           FROM public.lg_villages
        UNION ALL
         SELECT module_months.id,
            'month-master'::text AS module_slug,
            module_months.payload_text AS data,
            module_months.created_at,
            module_months.updated_at,
            (module_months.xmin)::text AS xmin,
            (module_months.ctid)::text AS ctid
           FROM public.module_months
        UNION ALL
         SELECT module_monthly_bill_summary_816eb1f0.id,
            'monthly-bill-summary'::text AS module_slug,
            module_monthly_bill_summary_816eb1f0.payload_text AS data,
            module_monthly_bill_summary_816eb1f0.created_at,
            module_monthly_bill_summary_816eb1f0.updated_at,
            (module_monthly_bill_summary_816eb1f0.xmin)::text AS xmin,
            (module_monthly_bill_summary_816eb1f0.ctid)::text AS ctid
           FROM public.module_monthly_bill_summary_816eb1f0
        UNION ALL
         SELECT module_new_user_6724757d.id,
            'new-user'::text AS module_slug,
            module_new_user_6724757d.payload_text AS data,
            module_new_user_6724757d.created_at,
            module_new_user_6724757d.updated_at,
            (module_new_user_6724757d.xmin)::text AS xmin,
            (module_new_user_6724757d.ctid)::text AS ctid
           FROM public.module_new_user_6724757d
        UNION ALL
         SELECT module_office_categories.id,
            'office-category-add'::text AS module_slug,
            module_office_categories.payload_text AS data,
            module_office_categories.created_at,
            module_office_categories.updated_at,
            (module_office_categories.xmin)::text AS xmin,
            (module_office_categories.ctid)::text AS ctid
           FROM public.module_office_categories
        UNION ALL
         SELECT module_office_list_286e3232.id,
            'office-list'::text AS module_slug,
            module_office_list_286e3232.payload_text AS data,
            module_office_list_286e3232.created_at,
            module_office_list_286e3232.updated_at,
            (module_office_list_286e3232.xmin)::text AS xmin,
            (module_office_list_286e3232.ctid)::text AS ctid
           FROM public.module_office_list_286e3232
        UNION ALL
         SELECT module_sub_offices.id,
            'office-mapping-add'::text AS module_slug,
            module_sub_offices.payload_text AS data,
            module_sub_offices.created_at,
            module_sub_offices.updated_at,
            (module_sub_offices.xmin)::text AS xmin,
            (module_sub_offices.ctid)::text AS ctid
           FROM public.module_sub_offices
        UNION ALL
         SELECT module_other_targets.id,
            'other-target'::text AS module_slug,
            module_other_targets.payload_text AS data,
            module_other_targets.created_at,
            module_other_targets.updated_at,
            (module_other_targets.xmin)::text AS xmin,
            (module_other_targets.ctid)::text AS ctid
           FROM public.module_other_targets
        UNION ALL
         SELECT module_other_target_list_410d4f4c.id,
            'other-target-list'::text AS module_slug,
            module_other_target_list_410d4f4c.payload_text AS data,
            module_other_target_list_410d4f4c.created_at,
            module_other_target_list_410d4f4c.updated_at,
            (module_other_target_list_410d4f4c.xmin)::text AS xmin,
            (module_other_target_list_410d4f4c.ctid)::text AS ctid
           FROM public.module_other_target_list_410d4f4c
        UNION ALL
         SELECT module_other_farmer_targets.id,
            'other-target-with-farmer'::text AS module_slug,
            module_other_farmer_targets.payload_text AS data,
            module_other_farmer_targets.created_at,
            module_other_farmer_targets.updated_at,
            (module_other_farmer_targets.xmin)::text AS xmin,
            (module_other_farmer_targets.ctid)::text AS ctid
           FROM public.module_other_farmer_targets
        UNION ALL
         SELECT module_other_target_with_farmer_list_0d98bf9f.id,
            'other-target-with-farmer-list'::text AS module_slug,
            module_other_target_with_farmer_list_0d98bf9f.payload_text AS data,
            module_other_target_with_farmer_list_0d98bf9f.created_at,
            module_other_target_with_farmer_list_0d98bf9f.updated_at,
            (module_other_target_with_farmer_list_0d98bf9f.xmin)::text AS xmin,
            (module_other_target_with_farmer_list_0d98bf9f.ctid)::text AS ctid
           FROM public.module_other_target_with_farmer_list_0d98bf9f
        UNION ALL
         SELECT module_papl360_target_e2ff67fc.id,
            'papl360-target'::text AS module_slug,
            module_papl360_target_e2ff67fc.payload_text AS data,
            module_papl360_target_e2ff67fc.created_at,
            module_papl360_target_e2ff67fc.updated_at,
            (module_papl360_target_e2ff67fc.xmin)::text AS xmin,
            (module_papl360_target_e2ff67fc.ctid)::text AS ctid
           FROM public.module_papl360_target_e2ff67fc
        UNION ALL
         SELECT module_papl360_target_list_08d81bec.id,
            'papl360-target-list'::text AS module_slug,
            module_papl360_target_list_08d81bec.payload_text AS data,
            module_papl360_target_list_08d81bec.created_at,
            module_papl360_target_list_08d81bec.updated_at,
            (module_papl360_target_list_08d81bec.xmin)::text AS xmin,
            (module_papl360_target_list_08d81bec.ctid)::text AS ctid
           FROM public.module_papl360_target_list_08d81bec
        UNION ALL
         SELECT module_parent_offices.id,
            'parent-office-add'::text AS module_slug,
            module_parent_offices.payload_text AS data,
            module_parent_offices.created_at,
            module_parent_offices.updated_at,
            (module_parent_offices.xmin)::text AS xmin,
            (module_parent_offices.ctid)::text AS ctid
           FROM public.module_parent_offices
        UNION ALL
         SELECT module_payment_status_report_17d409eb.id,
            'payment-status-report'::text AS module_slug,
            module_payment_status_report_17d409eb.payload_text AS data,
            module_payment_status_report_17d409eb.created_at,
            module_payment_status_report_17d409eb.updated_at,
            (module_payment_status_report_17d409eb.xmin)::text AS xmin,
            (module_payment_status_report_17d409eb.ctid)::text AS ctid
           FROM public.module_payment_status_report_17d409eb
        UNION ALL
         SELECT module_person_types.id,
            'person-type'::text AS module_slug,
            module_person_types.payload_text AS data,
            module_person_types.created_at,
            module_person_types.updated_at,
            (module_person_types.xmin)::text AS xmin,
            (module_person_types.ctid)::text AS ctid
           FROM public.module_person_types
        UNION ALL
         SELECT module_position_type_486dc9a9.id,
            'position-type'::text AS module_slug,
            module_position_type_486dc9a9.payload_text AS data,
            module_position_type_486dc9a9.created_at,
            module_position_type_486dc9a9.updated_at,
            (module_position_type_486dc9a9.xmin)::text AS xmin,
            (module_position_type_486dc9a9.ctid)::text AS ctid
           FROM public.module_position_type_486dc9a9
        UNION ALL
         SELECT module_projects.id,
            'project-master'::text AS module_slug,
            module_projects.payload_text AS data,
            module_projects.created_at,
            module_projects.updated_at,
            (module_projects.xmin)::text AS xmin,
            (module_projects.ctid)::text AS ctid
           FROM public.module_projects
        UNION ALL
         SELECT module_role_managements.id,
            'role-management'::text AS module_slug,
            module_role_managements.payload_text AS data,
            module_role_managements.created_at,
            module_role_managements.updated_at,
            (module_role_managements.xmin)::text AS xmin,
            (module_role_managements.ctid)::text AS ctid
           FROM public.module_role_managements
        UNION ALL
         SELECT module_roles.id,
            'role-name'::text AS module_slug,
            module_roles.payload_text AS data,
            module_roles.created_at,
            module_roles.updated_at,
            (module_roles.xmin)::text AS xmin,
            (module_roles.ctid)::text AS ctid
           FROM public.module_roles
        UNION ALL
         SELECT module_seed_distribution_targets.id,
            'seed-distribution-target'::text AS module_slug,
            module_seed_distribution_targets.payload_text AS data,
            module_seed_distribution_targets.created_at,
            module_seed_distribution_targets.updated_at,
            (module_seed_distribution_targets.xmin)::text AS xmin,
            (module_seed_distribution_targets.ctid)::text AS ctid
           FROM public.module_seed_distribution_targets
        UNION ALL
         SELECT module_seed_distribution_target_list_5453661e.id,
            'seed-distribution-target-list'::text AS module_slug,
            module_seed_distribution_target_list_5453661e.payload_text AS data,
            module_seed_distribution_target_list_5453661e.created_at,
            module_seed_distribution_target_list_5453661e.updated_at,
            (module_seed_distribution_target_list_5453661e.xmin)::text AS xmin,
            (module_seed_distribution_target_list_5453661e.ctid)::text AS ctid
           FROM public.module_seed_distribution_target_list_5453661e
        UNION ALL
         SELECT module_stakeholders.id,
            'stakeholder-master'::text AS module_slug,
            module_stakeholders.payload_text AS data,
            module_stakeholders.created_at,
            module_stakeholders.updated_at,
            (module_stakeholders.xmin)::text AS xmin,
            (module_stakeholders.ctid)::text AS ctid
           FROM public.module_stakeholders
        UNION ALL
         SELECT module_stakeholder_profile_603e5d20.id,
            'stakeholder-profile'::text AS module_slug,
            module_stakeholder_profile_603e5d20.payload_text AS data,
            module_stakeholder_profile_603e5d20.created_at,
            module_stakeholder_profile_603e5d20.updated_at,
            (module_stakeholder_profile_603e5d20.xmin)::text AS xmin,
            (module_stakeholder_profile_603e5d20.ctid)::text AS ctid
           FROM public.module_stakeholder_profile_603e5d20
        UNION ALL
         SELECT module_stakeholder_roles.id,
            'stakeholder-role'::text AS module_slug,
            module_stakeholder_roles.payload_text AS data,
            module_stakeholder_roles.created_at,
            module_stakeholder_roles.updated_at,
            (module_stakeholder_roles.xmin)::text AS xmin,
            (module_stakeholder_roles.ctid)::text AS ctid
           FROM public.module_stakeholder_roles
        UNION ALL
         SELECT lg_states.id,
            'state-master'::text AS module_slug,
            lg_states.payload_text AS data,
            lg_states.created_at,
            lg_states.updated_at,
            (lg_states.xmin)::text AS xmin,
            (lg_states.ctid)::text AS ctid
           FROM public.lg_states
        UNION ALL
         SELECT module_task_completion_indicator_2dc4f3fb.id,
            'task-completion-indicator'::text AS module_slug,
            module_task_completion_indicator_2dc4f3fb.payload_text AS data,
            module_task_completion_indicator_2dc4f3fb.created_at,
            module_task_completion_indicator_2dc4f3fb.updated_at,
            (module_task_completion_indicator_2dc4f3fb.xmin)::text AS xmin,
            (module_task_completion_indicator_2dc4f3fb.ctid)::text AS ctid
           FROM public.module_task_completion_indicator_2dc4f3fb
        UNION ALL
         SELECT module_task_completion_indicator_list_fc8d2b85.id,
            'task-completion-indicator-list'::text AS module_slug,
            module_task_completion_indicator_list_fc8d2b85.payload_text AS data,
            module_task_completion_indicator_list_fc8d2b85.created_at,
            module_task_completion_indicator_list_fc8d2b85.updated_at,
            (module_task_completion_indicator_list_fc8d2b85.xmin)::text AS xmin,
            (module_task_completion_indicator_list_fc8d2b85.ctid)::text AS ctid
           FROM public.module_task_completion_indicator_list_fc8d2b85
        UNION ALL
         SELECT module_task_indicator_master_c07b884a.id,
            'task-indicator-master'::text AS module_slug,
            module_task_indicator_master_c07b884a.payload_text AS data,
            module_task_indicator_master_c07b884a.created_at,
            module_task_indicator_master_c07b884a.updated_at,
            (module_task_indicator_master_c07b884a.xmin)::text AS xmin,
            (module_task_indicator_master_c07b884a.ctid)::text AS ctid
           FROM public.module_task_indicator_master_c07b884a
        UNION ALL
         SELECT module_trainings.id,
            'training-form'::text AS module_slug,
            module_trainings.payload_text AS data,
            module_trainings.created_at,
            module_trainings.updated_at,
            (module_trainings.xmin)::text AS xmin,
            (module_trainings.ctid)::text AS ctid
           FROM public.module_trainings
        UNION ALL
         SELECT module_training_edit_requests.id,
            'training-form-edit-request'::text AS module_slug,
            module_training_edit_requests.payload_text AS data,
            module_training_edit_requests.created_at,
            module_training_edit_requests.updated_at,
            (module_training_edit_requests.xmin)::text AS xmin,
            (module_training_edit_requests.ctid)::text AS ctid
           FROM public.module_training_edit_requests
        UNION ALL
         SELECT module_training_form_list_88933913.id,
            'training-form-list'::text AS module_slug,
            module_training_form_list_88933913.payload_text AS data,
            module_training_form_list_88933913.created_at,
            module_training_form_list_88933913.updated_at,
            (module_training_form_list_88933913.xmin)::text AS xmin,
            (module_training_form_list_88933913.ctid)::text AS ctid
           FROM public.module_training_form_list_88933913
        UNION ALL
         SELECT module_training_topic_mappings.id,
            'training-topic-mapping'::text AS module_slug,
            module_training_topic_mappings.payload_text AS data,
            module_training_topic_mappings.created_at,
            module_training_topic_mappings.updated_at,
            (module_training_topic_mappings.xmin)::text AS xmin,
            (module_training_topic_mappings.ctid)::text AS ctid
           FROM public.module_training_topic_mappings
        UNION ALL
         SELECT module_user_hierarchy_list_a4542a91.id,
            'user-hierarchy-list'::text AS module_slug,
            module_user_hierarchy_list_a4542a91.payload_text AS data,
            module_user_hierarchy_list_a4542a91.created_at,
            module_user_hierarchy_list_a4542a91.updated_at,
            (module_user_hierarchy_list_a4542a91.xmin)::text AS xmin,
            (module_user_hierarchy_list_a4542a91.ctid)::text AS ctid
           FROM public.module_user_hierarchy_list_a4542a91
        UNION ALL
         SELECT module_user_hierarchies.id,
            'user-hierarchy-mapping'::text AS module_slug,
            module_user_hierarchies.payload_text AS data,
            module_user_hierarchies.created_at,
            module_user_hierarchies.updated_at,
            (module_user_hierarchies.xmin)::text AS xmin,
            (module_user_hierarchies.ctid)::text AS ctid
           FROM public.module_user_hierarchies
        UNION ALL
         SELECT module_user_management_roles.id,
            'user-management-role'::text AS module_slug,
            module_user_management_roles.payload_text AS data,
            module_user_management_roles.created_at,
            module_user_management_roles.updated_at,
            (module_user_management_roles.xmin)::text AS xmin,
            (module_user_management_roles.ctid)::text AS ctid
           FROM public.module_user_management_roles
        UNION ALL
         SELECT module_vrp_active_status_history_5a746fcf.id,
            'vrp-active-status-history'::text AS module_slug,
            module_vrp_active_status_history_5a746fcf.payload_text AS data,
            module_vrp_active_status_history_5a746fcf.created_at,
            module_vrp_active_status_history_5a746fcf.updated_at,
            (module_vrp_active_status_history_5a746fcf.xmin)::text AS xmin,
            (module_vrp_active_status_history_5a746fcf.ctid)::text AS ctid
           FROM public.module_vrp_active_status_history_5a746fcf
        UNION ALL
         SELECT module_vrp_activity_list_7d178b72.id,
            'vrp-activity-list'::text AS module_slug,
            module_vrp_activity_list_7d178b72.payload_text AS data,
            module_vrp_activity_list_7d178b72.created_at,
            module_vrp_activity_list_7d178b72.updated_at,
            (module_vrp_activity_list_7d178b72.xmin)::text AS xmin,
            (module_vrp_activity_list_7d178b72.ctid)::text AS ctid
           FROM public.module_vrp_activity_list_7d178b72
        UNION ALL
         SELECT module_vrp_approval_histories.id,
            'vrp-approval-history'::text AS module_slug,
            module_vrp_approval_histories.payload_text AS data,
            module_vrp_approval_histories.created_at,
            module_vrp_approval_histories.updated_at,
            (module_vrp_approval_histories.xmin)::text AS xmin,
            (module_vrp_approval_histories.ctid)::text AS ctid
           FROM public.module_vrp_approval_histories
        UNION ALL
         SELECT module_vrp_bill_add_50a221ea.id,
            'vrp-bill-add'::text AS module_slug,
            module_vrp_bill_add_50a221ea.payload_text AS data,
            module_vrp_bill_add_50a221ea.created_at,
            module_vrp_bill_add_50a221ea.updated_at,
            (module_vrp_bill_add_50a221ea.xmin)::text AS xmin,
            (module_vrp_bill_add_50a221ea.ctid)::text AS ctid
           FROM public.module_vrp_bill_add_50a221ea
        UNION ALL
         SELECT module_vrp_bill_list_0ef6fdc4.id,
            'vrp-bill-list'::text AS module_slug,
            module_vrp_bill_list_0ef6fdc4.payload_text AS data,
            module_vrp_bill_list_0ef6fdc4.created_at,
            module_vrp_bill_list_0ef6fdc4.updated_at,
            (module_vrp_bill_list_0ef6fdc4.xmin)::text AS xmin,
            (module_vrp_bill_list_0ef6fdc4.ctid)::text AS ctid
           FROM public.module_vrp_bill_list_0ef6fdc4
        UNION ALL
         SELECT module_vrp_registration_list_6a8aeba6.id,
            'vrp-registration-list'::text AS module_slug,
            module_vrp_registration_list_6a8aeba6.payload_text AS data,
            module_vrp_registration_list_6a8aeba6.created_at,
            module_vrp_registration_list_6a8aeba6.updated_at,
            (module_vrp_registration_list_6a8aeba6.xmin)::text AS xmin,
            (module_vrp_registration_list_6a8aeba6.ctid)::text AS ctid
           FROM public.module_vrp_registration_list_6a8aeba6
        UNION ALL
         SELECT module_weekly_activity_progress_22c35d60.id,
            'weekly-activity-progress'::text AS module_slug,
            module_weekly_activity_progress_22c35d60.payload_text AS data,
            module_weekly_activity_progress_22c35d60.created_at,
            module_weekly_activity_progress_22c35d60.updated_at,
            (module_weekly_activity_progress_22c35d60.xmin)::text AS xmin,
            (module_weekly_activity_progress_22c35d60.ctid)::text AS ctid
           FROM public.module_weekly_activity_progress_22c35d60
        UNION ALL
         SELECT module_weekly_progress_report_1157600e.id,
            'weekly-progress-report'::text AS module_slug,
            module_weekly_progress_report_1157600e.payload_text AS data,
            module_weekly_progress_report_1157600e.created_at,
            module_weekly_progress_report_1157600e.updated_at,
            (module_weekly_progress_report_1157600e.xmin)::text AS xmin,
            (module_weekly_progress_report_1157600e.ctid)::text AS ctid
           FROM public.module_weekly_progress_report_1157600e
        UNION ALL
         SELECT module_weekly_target_add_ef9d741d.id,
            'weekly-target-add'::text AS module_slug,
            module_weekly_target_add_ef9d741d.payload_text AS data,
            module_weekly_target_add_ef9d741d.created_at,
            module_weekly_target_add_ef9d741d.updated_at,
            (module_weekly_target_add_ef9d741d.xmin)::text AS xmin,
            (module_weekly_target_add_ef9d741d.ctid)::text AS ctid
           FROM public.module_weekly_target_add_ef9d741d
        UNION ALL
         SELECT module_weekly_target_list_91c4fe5d.id,
            'weekly-target-list'::text AS module_slug,
            module_weekly_target_list_91c4fe5d.payload_text AS data,
            module_weekly_target_list_91c4fe5d.created_at,
            module_weekly_target_list_91c4fe5d.updated_at,
            (module_weekly_target_list_91c4fe5d.xmin)::text AS xmin,
            (module_weekly_target_list_91c4fe5d.ctid)::text AS ctid
           FROM public.module_weekly_target_list_91c4fe5d) stored
     LEFT JOIN public.module_entry_identities identities ON ((identities.id = stored.id)));


--
-- Name: module_entry_payloads; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.module_entry_payloads AS
 SELECT stored.id,
    stored.module_slug,
    stored.data,
    stored.created_at,
    stored.updated_at,
    stored.catalogue_active,
    stored.record_active,
    identities.storage_order
   FROM (( SELECT module_access_controls.id,
            'access-control'::text AS module_slug,
            module_access_controls.data,
            module_access_controls.created_at,
            module_access_controls.updated_at,
            module_access_controls.catalogue_active,
            module_access_controls.active AS record_active
           FROM public.module_access_controls
        UNION ALL
         SELECT module_access_control_list_b9d538d4.id,
            'access-control-list'::text AS module_slug,
            module_access_control_list_b9d538d4.data,
            module_access_control_list_b9d538d4.created_at,
            module_access_control_list_b9d538d4.updated_at,
            module_access_control_list_b9d538d4.catalogue_active,
            module_access_control_list_b9d538d4.active AS record_active
           FROM public.module_access_control_list_b9d538d4
        UNION ALL
         SELECT module_activity_group_list_34a52e96.id,
            'activity-group-list'::text AS module_slug,
            module_activity_group_list_34a52e96.data,
            module_activity_group_list_34a52e96.created_at,
            module_activity_group_list_34a52e96.updated_at,
            module_activity_group_list_34a52e96.catalogue_active,
            module_activity_group_list_34a52e96.active AS record_active
           FROM public.module_activity_group_list_34a52e96
        UNION ALL
         SELECT module_activity_master_2e19bce0.id,
            'activity-master'::text AS module_slug,
            module_activity_master_2e19bce0.data,
            module_activity_master_2e19bce0.created_at,
            module_activity_master_2e19bce0.updated_at,
            module_activity_master_2e19bce0.catalogue_active,
            module_activity_master_2e19bce0.active AS record_active
           FROM public.module_activity_master_2e19bce0
        UNION ALL
         SELECT module_main_activities.id,
            'add-activity-group'::text AS module_slug,
            module_main_activities.data,
            module_main_activities.created_at,
            module_main_activities.updated_at,
            module_main_activities.catalogue_active,
            module_main_activities.active AS record_active
           FROM public.module_main_activities
        UNION ALL
         SELECT module_farmer_forms.id,
            'add-farmer-form'::text AS module_slug,
            module_farmer_forms.data,
            module_farmer_forms.created_at,
            module_farmer_forms.updated_at,
            module_farmer_forms.catalogue_active,
            module_farmer_forms.active AS record_active
           FROM public.module_farmer_forms
        UNION ALL
         SELECT module_sub_activities.id,
            'add-vrp-activity'::text AS module_slug,
            module_sub_activities.data,
            module_sub_activities.created_at,
            module_sub_activities.updated_at,
            module_sub_activities.catalogue_active,
            module_sub_activities.active AS record_active
           FROM public.module_sub_activities
        UNION ALL
         SELECT module_vrp_types.id,
            'add-vrp-type'::text AS module_slug,
            module_vrp_types.data,
            module_vrp_types.created_at,
            module_vrp_types.updated_at,
            module_vrp_types.catalogue_active,
            module_vrp_types.active AS record_active
           FROM public.module_vrp_types
        UNION ALL
         SELECT module_all_user_b8d83be4.id,
            'all-user'::text AS module_slug,
            module_all_user_b8d83be4.data,
            module_all_user_b8d83be4.created_at,
            module_all_user_b8d83be4.updated_at,
            module_all_user_b8d83be4.catalogue_active,
            module_all_user_b8d83be4.active AS record_active
           FROM public.module_all_user_b8d83be4
        UNION ALL
         SELECT module_approval_list_27d1da1f.id,
            'approval-list'::text AS module_slug,
            module_approval_list_27d1da1f.data,
            module_approval_list_27d1da1f.created_at,
            module_approval_list_27d1da1f.updated_at,
            module_approval_list_27d1da1f.catalogue_active,
            module_approval_list_27d1da1f.active AS record_active
           FROM public.module_approval_list_27d1da1f
        UNION ALL
         SELECT module_approvals.id,
            'approval-master'::text AS module_slug,
            module_approvals.data,
            module_approvals.created_at,
            module_approvals.updated_at,
            module_approvals.catalogue_active,
            module_approvals.active AS record_active
           FROM public.module_approvals
        UNION ALL
         SELECT module_approval_status_summary_1483b5d5.id,
            'approval-status-summary'::text AS module_slug,
            module_approval_status_summary_1483b5d5.data,
            module_approval_status_summary_1483b5d5.created_at,
            module_approval_status_summary_1483b5d5.updated_at,
            module_approval_status_summary_1483b5d5.catalogue_active,
            module_approval_status_summary_1483b5d5.active AS record_active
           FROM public.module_approval_status_summary_1483b5d5
        UNION ALL
         SELECT module_bank_master_9e57e6ab.id,
            'bank-master'::text AS module_slug,
            module_bank_master_9e57e6ab.data,
            module_bank_master_9e57e6ab.created_at,
            module_bank_master_9e57e6ab.updated_at,
            module_bank_master_9e57e6ab.catalogue_active,
            module_bank_master_9e57e6ab.active AS record_active
           FROM public.module_bank_master_9e57e6ab
        UNION ALL
         SELECT lg_blocks.id,
            'block-master'::text AS module_slug,
            lg_blocks.data,
            lg_blocks.created_at,
            lg_blocks.updated_at,
            lg_blocks.catalogue_active,
            lg_blocks.active AS record_active
           FROM public.lg_blocks
        UNION ALL
         SELECT lg_districts.id,
            'district-master'::text AS module_slug,
            lg_districts.data,
            lg_districts.created_at,
            lg_districts.updated_at,
            lg_districts.catalogue_active,
            lg_districts.active AS record_active
           FROM public.lg_districts
        UNION ALL
         SELECT lg_gram_panchayats.id,
            'gram-panchayat-master'::text AS module_slug,
            lg_gram_panchayats.data,
            lg_gram_panchayats.created_at,
            lg_gram_panchayats.updated_at,
            lg_gram_panchayats.catalogue_active,
            lg_gram_panchayats.active AS record_active
           FROM public.lg_gram_panchayats
        UNION ALL
         SELECT module_ics_master_483e7ffc.id,
            'ics-master'::text AS module_slug,
            module_ics_master_483e7ffc.data,
            module_ics_master_483e7ffc.created_at,
            module_ics_master_483e7ffc.updated_at,
            module_ics_master_483e7ffc.catalogue_active,
            module_ics_master_483e7ffc.active AS record_active
           FROM public.module_ics_master_483e7ffc
        UNION ALL
         SELECT module_bill_approval_histories.id,
            'jeevika-jankar-bill-approval-history'::text AS module_slug,
            module_bill_approval_histories.data,
            module_bill_approval_histories.created_at,
            module_bill_approval_histories.updated_at,
            module_bill_approval_histories.catalogue_active,
            module_bill_approval_histories.active AS record_active
           FROM public.module_bill_approval_histories
        UNION ALL
         SELECT module_jeevika_jankar_bill_list_083c76c4.id,
            'jeevika-jankar-bill-list'::text AS module_slug,
            module_jeevika_jankar_bill_list_083c76c4.data,
            module_jeevika_jankar_bill_list_083c76c4.created_at,
            module_jeevika_jankar_bill_list_083c76c4.updated_at,
            module_jeevika_jankar_bill_list_083c76c4.catalogue_active,
            module_jeevika_jankar_bill_list_083c76c4.active AS record_active
           FROM public.module_jeevika_jankar_bill_list_083c76c4
        UNION ALL
         SELECT module_bills.id,
            'jeevika-jankar-bill-process'::text AS module_slug,
            module_bills.data,
            module_bills.created_at,
            module_bills.updated_at,
            module_bills.catalogue_active,
            module_bills.active AS record_active
           FROM public.module_bills
        UNION ALL
         SELECT module_jeevika_jankar_completed_payment_l_bad7b61b.id,
            'jeevika-jankar-completed-payment-list'::text AS module_slug,
            module_jeevika_jankar_completed_payment_l_bad7b61b.data,
            module_jeevika_jankar_completed_payment_l_bad7b61b.created_at,
            module_jeevika_jankar_completed_payment_l_bad7b61b.updated_at,
            module_jeevika_jankar_completed_payment_l_bad7b61b.catalogue_active,
            module_jeevika_jankar_completed_payment_l_bad7b61b.active AS record_active
           FROM public.module_jeevika_jankar_completed_payment_l_bad7b61b
        UNION ALL
         SELECT module_jeevika_jankar_observation_list_9bfb7dc5.id,
            'jeevika-jankar-observation-list'::text AS module_slug,
            module_jeevika_jankar_observation_list_9bfb7dc5.data,
            module_jeevika_jankar_observation_list_9bfb7dc5.created_at,
            module_jeevika_jankar_observation_list_9bfb7dc5.updated_at,
            module_jeevika_jankar_observation_list_9bfb7dc5.catalogue_active,
            module_jeevika_jankar_observation_list_9bfb7dc5.active AS record_active
           FROM public.module_jeevika_jankar_observation_list_9bfb7dc5
        UNION ALL
         SELECT module_payment_details.id,
            'jeevika-jankar-payment-detail'::text AS module_slug,
            module_payment_details.data,
            module_payment_details.created_at,
            module_payment_details.updated_at,
            module_payment_details.catalogue_active,
            module_payment_details.active AS record_active
           FROM public.module_payment_details
        UNION ALL
         SELECT module_jeevika_jankar_payment_list_2e70d942.id,
            'jeevika-jankar-payment-list'::text AS module_slug,
            module_jeevika_jankar_payment_list_2e70d942.data,
            module_jeevika_jankar_payment_list_2e70d942.created_at,
            module_jeevika_jankar_payment_list_2e70d942.updated_at,
            module_jeevika_jankar_payment_list_2e70d942.catalogue_active,
            module_jeevika_jankar_payment_list_2e70d942.active AS record_active
           FROM public.module_jeevika_jankar_payment_list_2e70d942
        UNION ALL
         SELECT module_jeevika_jankar_payment_list_detail_d8114659.id,
            'jeevika-jankar-payment-list-detail'::text AS module_slug,
            module_jeevika_jankar_payment_list_detail_d8114659.data,
            module_jeevika_jankar_payment_list_detail_d8114659.created_at,
            module_jeevika_jankar_payment_list_detail_d8114659.updated_at,
            module_jeevika_jankar_payment_list_detail_d8114659.catalogue_active,
            module_jeevika_jankar_payment_list_detail_d8114659.active AS record_active
           FROM public.module_jeevika_jankar_payment_list_detail_d8114659
        UNION ALL
         SELECT module_jj_transfers.id,
            'jeevika-jankar-transfer'::text AS module_slug,
            module_jj_transfers.data,
            module_jj_transfers.created_at,
            module_jj_transfers.updated_at,
            module_jj_transfers.catalogue_active,
            module_jj_transfers.active AS record_active
           FROM public.module_jj_transfers
        UNION ALL
         SELECT module_jeevika_jankar_transfer_list_73f1674d.id,
            'jeevika-jankar-transfer-list'::text AS module_slug,
            module_jeevika_jankar_transfer_list_73f1674d.data,
            module_jeevika_jankar_transfer_list_73f1674d.created_at,
            module_jeevika_jankar_transfer_list_73f1674d.updated_at,
            module_jeevika_jankar_transfer_list_73f1674d.catalogue_active,
            module_jeevika_jankar_transfer_list_73f1674d.active AS record_active
           FROM public.module_jeevika_jankar_transfer_list_73f1674d
        UNION ALL
         SELECT module_lg_directory_import_status_0543ee43.id,
            'lg-directory-import-status'::text AS module_slug,
            module_lg_directory_import_status_0543ee43.data,
            module_lg_directory_import_status_0543ee43.created_at,
            module_lg_directory_import_status_0543ee43.updated_at,
            module_lg_directory_import_status_0543ee43.catalogue_active,
            module_lg_directory_import_status_0543ee43.active AS record_active
           FROM public.module_lg_directory_import_status_0543ee43
        UNION ALL
         SELECT lg_villages.id,
            (lg_villages.source_slug)::text AS module_slug,
            lg_villages.data,
            lg_villages.created_at,
            lg_villages.updated_at,
            lg_villages.catalogue_active,
            lg_villages.active AS record_active
           FROM public.lg_villages
        UNION ALL
         SELECT module_months.id,
            'month-master'::text AS module_slug,
            module_months.data,
            module_months.created_at,
            module_months.updated_at,
            module_months.catalogue_active,
            module_months.active AS record_active
           FROM public.module_months
        UNION ALL
         SELECT module_monthly_bill_summary_816eb1f0.id,
            'monthly-bill-summary'::text AS module_slug,
            module_monthly_bill_summary_816eb1f0.data,
            module_monthly_bill_summary_816eb1f0.created_at,
            module_monthly_bill_summary_816eb1f0.updated_at,
            module_monthly_bill_summary_816eb1f0.catalogue_active,
            module_monthly_bill_summary_816eb1f0.active AS record_active
           FROM public.module_monthly_bill_summary_816eb1f0
        UNION ALL
         SELECT module_new_user_6724757d.id,
            'new-user'::text AS module_slug,
            module_new_user_6724757d.data,
            module_new_user_6724757d.created_at,
            module_new_user_6724757d.updated_at,
            module_new_user_6724757d.catalogue_active,
            module_new_user_6724757d.active AS record_active
           FROM public.module_new_user_6724757d
        UNION ALL
         SELECT module_office_categories.id,
            'office-category-add'::text AS module_slug,
            module_office_categories.data,
            module_office_categories.created_at,
            module_office_categories.updated_at,
            module_office_categories.catalogue_active,
            module_office_categories.active AS record_active
           FROM public.module_office_categories
        UNION ALL
         SELECT module_office_list_286e3232.id,
            'office-list'::text AS module_slug,
            module_office_list_286e3232.data,
            module_office_list_286e3232.created_at,
            module_office_list_286e3232.updated_at,
            module_office_list_286e3232.catalogue_active,
            module_office_list_286e3232.active AS record_active
           FROM public.module_office_list_286e3232
        UNION ALL
         SELECT module_sub_offices.id,
            'office-mapping-add'::text AS module_slug,
            module_sub_offices.data,
            module_sub_offices.created_at,
            module_sub_offices.updated_at,
            module_sub_offices.catalogue_active,
            module_sub_offices.active AS record_active
           FROM public.module_sub_offices
        UNION ALL
         SELECT module_other_targets.id,
            'other-target'::text AS module_slug,
            module_other_targets.data,
            module_other_targets.created_at,
            module_other_targets.updated_at,
            module_other_targets.catalogue_active,
            module_other_targets.active AS record_active
           FROM public.module_other_targets
        UNION ALL
         SELECT module_other_target_list_410d4f4c.id,
            'other-target-list'::text AS module_slug,
            module_other_target_list_410d4f4c.data,
            module_other_target_list_410d4f4c.created_at,
            module_other_target_list_410d4f4c.updated_at,
            module_other_target_list_410d4f4c.catalogue_active,
            module_other_target_list_410d4f4c.active AS record_active
           FROM public.module_other_target_list_410d4f4c
        UNION ALL
         SELECT module_other_farmer_targets.id,
            'other-target-with-farmer'::text AS module_slug,
            module_other_farmer_targets.data,
            module_other_farmer_targets.created_at,
            module_other_farmer_targets.updated_at,
            module_other_farmer_targets.catalogue_active,
            module_other_farmer_targets.active AS record_active
           FROM public.module_other_farmer_targets
        UNION ALL
         SELECT module_other_target_with_farmer_list_0d98bf9f.id,
            'other-target-with-farmer-list'::text AS module_slug,
            module_other_target_with_farmer_list_0d98bf9f.data,
            module_other_target_with_farmer_list_0d98bf9f.created_at,
            module_other_target_with_farmer_list_0d98bf9f.updated_at,
            module_other_target_with_farmer_list_0d98bf9f.catalogue_active,
            module_other_target_with_farmer_list_0d98bf9f.active AS record_active
           FROM public.module_other_target_with_farmer_list_0d98bf9f
        UNION ALL
         SELECT module_papl360_target_e2ff67fc.id,
            'papl360-target'::text AS module_slug,
            module_papl360_target_e2ff67fc.data,
            module_papl360_target_e2ff67fc.created_at,
            module_papl360_target_e2ff67fc.updated_at,
            module_papl360_target_e2ff67fc.catalogue_active,
            module_papl360_target_e2ff67fc.active AS record_active
           FROM public.module_papl360_target_e2ff67fc
        UNION ALL
         SELECT module_papl360_target_list_08d81bec.id,
            'papl360-target-list'::text AS module_slug,
            module_papl360_target_list_08d81bec.data,
            module_papl360_target_list_08d81bec.created_at,
            module_papl360_target_list_08d81bec.updated_at,
            module_papl360_target_list_08d81bec.catalogue_active,
            module_papl360_target_list_08d81bec.active AS record_active
           FROM public.module_papl360_target_list_08d81bec
        UNION ALL
         SELECT module_parent_offices.id,
            'parent-office-add'::text AS module_slug,
            module_parent_offices.data,
            module_parent_offices.created_at,
            module_parent_offices.updated_at,
            module_parent_offices.catalogue_active,
            module_parent_offices.active AS record_active
           FROM public.module_parent_offices
        UNION ALL
         SELECT module_payment_status_report_17d409eb.id,
            'payment-status-report'::text AS module_slug,
            module_payment_status_report_17d409eb.data,
            module_payment_status_report_17d409eb.created_at,
            module_payment_status_report_17d409eb.updated_at,
            module_payment_status_report_17d409eb.catalogue_active,
            module_payment_status_report_17d409eb.active AS record_active
           FROM public.module_payment_status_report_17d409eb
        UNION ALL
         SELECT module_person_types.id,
            'person-type'::text AS module_slug,
            module_person_types.data,
            module_person_types.created_at,
            module_person_types.updated_at,
            module_person_types.catalogue_active,
            module_person_types.active AS record_active
           FROM public.module_person_types
        UNION ALL
         SELECT module_position_type_486dc9a9.id,
            'position-type'::text AS module_slug,
            module_position_type_486dc9a9.data,
            module_position_type_486dc9a9.created_at,
            module_position_type_486dc9a9.updated_at,
            module_position_type_486dc9a9.catalogue_active,
            module_position_type_486dc9a9.active AS record_active
           FROM public.module_position_type_486dc9a9
        UNION ALL
         SELECT module_projects.id,
            'project-master'::text AS module_slug,
            module_projects.data,
            module_projects.created_at,
            module_projects.updated_at,
            module_projects.catalogue_active,
            module_projects.active AS record_active
           FROM public.module_projects
        UNION ALL
         SELECT module_role_managements.id,
            'role-management'::text AS module_slug,
            module_role_managements.data,
            module_role_managements.created_at,
            module_role_managements.updated_at,
            module_role_managements.catalogue_active,
            module_role_managements.active AS record_active
           FROM public.module_role_managements
        UNION ALL
         SELECT module_roles.id,
            'role-name'::text AS module_slug,
            module_roles.data,
            module_roles.created_at,
            module_roles.updated_at,
            module_roles.catalogue_active,
            module_roles.active AS record_active
           FROM public.module_roles
        UNION ALL
         SELECT module_seed_distribution_targets.id,
            'seed-distribution-target'::text AS module_slug,
            module_seed_distribution_targets.data,
            module_seed_distribution_targets.created_at,
            module_seed_distribution_targets.updated_at,
            module_seed_distribution_targets.catalogue_active,
            module_seed_distribution_targets.active AS record_active
           FROM public.module_seed_distribution_targets
        UNION ALL
         SELECT module_seed_distribution_target_list_5453661e.id,
            'seed-distribution-target-list'::text AS module_slug,
            module_seed_distribution_target_list_5453661e.data,
            module_seed_distribution_target_list_5453661e.created_at,
            module_seed_distribution_target_list_5453661e.updated_at,
            module_seed_distribution_target_list_5453661e.catalogue_active,
            module_seed_distribution_target_list_5453661e.active AS record_active
           FROM public.module_seed_distribution_target_list_5453661e
        UNION ALL
         SELECT module_stakeholders.id,
            'stakeholder-master'::text AS module_slug,
            module_stakeholders.data,
            module_stakeholders.created_at,
            module_stakeholders.updated_at,
            module_stakeholders.catalogue_active,
            module_stakeholders.active AS record_active
           FROM public.module_stakeholders
        UNION ALL
         SELECT module_stakeholder_profile_603e5d20.id,
            'stakeholder-profile'::text AS module_slug,
            module_stakeholder_profile_603e5d20.data,
            module_stakeholder_profile_603e5d20.created_at,
            module_stakeholder_profile_603e5d20.updated_at,
            module_stakeholder_profile_603e5d20.catalogue_active,
            module_stakeholder_profile_603e5d20.active AS record_active
           FROM public.module_stakeholder_profile_603e5d20
        UNION ALL
         SELECT module_stakeholder_roles.id,
            'stakeholder-role'::text AS module_slug,
            module_stakeholder_roles.data,
            module_stakeholder_roles.created_at,
            module_stakeholder_roles.updated_at,
            module_stakeholder_roles.catalogue_active,
            module_stakeholder_roles.active AS record_active
           FROM public.module_stakeholder_roles
        UNION ALL
         SELECT lg_states.id,
            'state-master'::text AS module_slug,
            lg_states.data,
            lg_states.created_at,
            lg_states.updated_at,
            lg_states.catalogue_active,
            lg_states.active AS record_active
           FROM public.lg_states
        UNION ALL
         SELECT module_task_completion_indicator_2dc4f3fb.id,
            'task-completion-indicator'::text AS module_slug,
            module_task_completion_indicator_2dc4f3fb.data,
            module_task_completion_indicator_2dc4f3fb.created_at,
            module_task_completion_indicator_2dc4f3fb.updated_at,
            module_task_completion_indicator_2dc4f3fb.catalogue_active,
            module_task_completion_indicator_2dc4f3fb.active AS record_active
           FROM public.module_task_completion_indicator_2dc4f3fb
        UNION ALL
         SELECT module_task_completion_indicator_list_fc8d2b85.id,
            'task-completion-indicator-list'::text AS module_slug,
            module_task_completion_indicator_list_fc8d2b85.data,
            module_task_completion_indicator_list_fc8d2b85.created_at,
            module_task_completion_indicator_list_fc8d2b85.updated_at,
            module_task_completion_indicator_list_fc8d2b85.catalogue_active,
            module_task_completion_indicator_list_fc8d2b85.active AS record_active
           FROM public.module_task_completion_indicator_list_fc8d2b85
        UNION ALL
         SELECT module_task_indicator_master_c07b884a.id,
            'task-indicator-master'::text AS module_slug,
            module_task_indicator_master_c07b884a.data,
            module_task_indicator_master_c07b884a.created_at,
            module_task_indicator_master_c07b884a.updated_at,
            module_task_indicator_master_c07b884a.catalogue_active,
            module_task_indicator_master_c07b884a.active AS record_active
           FROM public.module_task_indicator_master_c07b884a
        UNION ALL
         SELECT module_trainings.id,
            'training-form'::text AS module_slug,
            module_trainings.data,
            module_trainings.created_at,
            module_trainings.updated_at,
            module_trainings.catalogue_active,
            module_trainings.active AS record_active
           FROM public.module_trainings
        UNION ALL
         SELECT module_training_edit_requests.id,
            'training-form-edit-request'::text AS module_slug,
            module_training_edit_requests.data,
            module_training_edit_requests.created_at,
            module_training_edit_requests.updated_at,
            module_training_edit_requests.catalogue_active,
            module_training_edit_requests.active AS record_active
           FROM public.module_training_edit_requests
        UNION ALL
         SELECT module_training_form_list_88933913.id,
            'training-form-list'::text AS module_slug,
            module_training_form_list_88933913.data,
            module_training_form_list_88933913.created_at,
            module_training_form_list_88933913.updated_at,
            module_training_form_list_88933913.catalogue_active,
            module_training_form_list_88933913.active AS record_active
           FROM public.module_training_form_list_88933913
        UNION ALL
         SELECT module_training_topic_mappings.id,
            'training-topic-mapping'::text AS module_slug,
            module_training_topic_mappings.data,
            module_training_topic_mappings.created_at,
            module_training_topic_mappings.updated_at,
            module_training_topic_mappings.catalogue_active,
            module_training_topic_mappings.active AS record_active
           FROM public.module_training_topic_mappings
        UNION ALL
         SELECT module_user_hierarchy_list_a4542a91.id,
            'user-hierarchy-list'::text AS module_slug,
            module_user_hierarchy_list_a4542a91.data,
            module_user_hierarchy_list_a4542a91.created_at,
            module_user_hierarchy_list_a4542a91.updated_at,
            module_user_hierarchy_list_a4542a91.catalogue_active,
            module_user_hierarchy_list_a4542a91.active AS record_active
           FROM public.module_user_hierarchy_list_a4542a91
        UNION ALL
         SELECT module_user_hierarchies.id,
            'user-hierarchy-mapping'::text AS module_slug,
            module_user_hierarchies.data,
            module_user_hierarchies.created_at,
            module_user_hierarchies.updated_at,
            module_user_hierarchies.catalogue_active,
            module_user_hierarchies.active AS record_active
           FROM public.module_user_hierarchies
        UNION ALL
         SELECT module_user_management_roles.id,
            'user-management-role'::text AS module_slug,
            module_user_management_roles.data,
            module_user_management_roles.created_at,
            module_user_management_roles.updated_at,
            module_user_management_roles.catalogue_active,
            module_user_management_roles.active AS record_active
           FROM public.module_user_management_roles
        UNION ALL
         SELECT module_vrp_active_status_history_5a746fcf.id,
            'vrp-active-status-history'::text AS module_slug,
            module_vrp_active_status_history_5a746fcf.data,
            module_vrp_active_status_history_5a746fcf.created_at,
            module_vrp_active_status_history_5a746fcf.updated_at,
            module_vrp_active_status_history_5a746fcf.catalogue_active,
            module_vrp_active_status_history_5a746fcf.active AS record_active
           FROM public.module_vrp_active_status_history_5a746fcf
        UNION ALL
         SELECT module_vrp_activity_list_7d178b72.id,
            'vrp-activity-list'::text AS module_slug,
            module_vrp_activity_list_7d178b72.data,
            module_vrp_activity_list_7d178b72.created_at,
            module_vrp_activity_list_7d178b72.updated_at,
            module_vrp_activity_list_7d178b72.catalogue_active,
            module_vrp_activity_list_7d178b72.active AS record_active
           FROM public.module_vrp_activity_list_7d178b72
        UNION ALL
         SELECT module_vrp_approval_histories.id,
            'vrp-approval-history'::text AS module_slug,
            module_vrp_approval_histories.data,
            module_vrp_approval_histories.created_at,
            module_vrp_approval_histories.updated_at,
            module_vrp_approval_histories.catalogue_active,
            module_vrp_approval_histories.active AS record_active
           FROM public.module_vrp_approval_histories
        UNION ALL
         SELECT module_vrp_bill_add_50a221ea.id,
            'vrp-bill-add'::text AS module_slug,
            module_vrp_bill_add_50a221ea.data,
            module_vrp_bill_add_50a221ea.created_at,
            module_vrp_bill_add_50a221ea.updated_at,
            module_vrp_bill_add_50a221ea.catalogue_active,
            module_vrp_bill_add_50a221ea.active AS record_active
           FROM public.module_vrp_bill_add_50a221ea
        UNION ALL
         SELECT module_vrp_bill_list_0ef6fdc4.id,
            'vrp-bill-list'::text AS module_slug,
            module_vrp_bill_list_0ef6fdc4.data,
            module_vrp_bill_list_0ef6fdc4.created_at,
            module_vrp_bill_list_0ef6fdc4.updated_at,
            module_vrp_bill_list_0ef6fdc4.catalogue_active,
            module_vrp_bill_list_0ef6fdc4.active AS record_active
           FROM public.module_vrp_bill_list_0ef6fdc4
        UNION ALL
         SELECT module_vrp_registration_list_6a8aeba6.id,
            'vrp-registration-list'::text AS module_slug,
            module_vrp_registration_list_6a8aeba6.data,
            module_vrp_registration_list_6a8aeba6.created_at,
            module_vrp_registration_list_6a8aeba6.updated_at,
            module_vrp_registration_list_6a8aeba6.catalogue_active,
            module_vrp_registration_list_6a8aeba6.active AS record_active
           FROM public.module_vrp_registration_list_6a8aeba6
        UNION ALL
         SELECT module_weekly_activity_progress_22c35d60.id,
            'weekly-activity-progress'::text AS module_slug,
            module_weekly_activity_progress_22c35d60.data,
            module_weekly_activity_progress_22c35d60.created_at,
            module_weekly_activity_progress_22c35d60.updated_at,
            module_weekly_activity_progress_22c35d60.catalogue_active,
            module_weekly_activity_progress_22c35d60.active AS record_active
           FROM public.module_weekly_activity_progress_22c35d60
        UNION ALL
         SELECT module_weekly_progress_report_1157600e.id,
            'weekly-progress-report'::text AS module_slug,
            module_weekly_progress_report_1157600e.data,
            module_weekly_progress_report_1157600e.created_at,
            module_weekly_progress_report_1157600e.updated_at,
            module_weekly_progress_report_1157600e.catalogue_active,
            module_weekly_progress_report_1157600e.active AS record_active
           FROM public.module_weekly_progress_report_1157600e
        UNION ALL
         SELECT module_weekly_target_add_ef9d741d.id,
            'weekly-target-add'::text AS module_slug,
            module_weekly_target_add_ef9d741d.data,
            module_weekly_target_add_ef9d741d.created_at,
            module_weekly_target_add_ef9d741d.updated_at,
            module_weekly_target_add_ef9d741d.catalogue_active,
            module_weekly_target_add_ef9d741d.active AS record_active
           FROM public.module_weekly_target_add_ef9d741d
        UNION ALL
         SELECT module_weekly_target_list_91c4fe5d.id,
            'weekly-target-list'::text AS module_slug,
            module_weekly_target_list_91c4fe5d.data,
            module_weekly_target_list_91c4fe5d.created_at,
            module_weekly_target_list_91c4fe5d.updated_at,
            module_weekly_target_list_91c4fe5d.catalogue_active,
            module_weekly_target_list_91c4fe5d.active AS record_active
           FROM public.module_weekly_target_list_91c4fe5d) stored
     LEFT JOIN public.module_entry_identities identities ON ((identities.id = stored.id)));


--
-- Name: module_entry_sources; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.module_entry_sources AS
 SELECT slug,
    table_name
   FROM ( VALUES ('access-control'::text,'module_access_controls'::text), ('access-control-list'::text,'module_access_control_list_b9d538d4'::text), ('activity-group-list'::text,'module_activity_group_list_34a52e96'::text), ('activity-master'::text,'module_activity_master_2e19bce0'::text), ('add-activity-group'::text,'module_main_activities'::text), ('add-farmer-form'::text,'module_farmer_forms'::text), ('add-vrp-activity'::text,'module_sub_activities'::text), ('add-vrp-type'::text,'module_vrp_types'::text), ('all-user'::text,'module_all_user_b8d83be4'::text), ('approval-list'::text,'module_approval_list_27d1da1f'::text), ('approval-master'::text,'module_approvals'::text), ('approval-status-summary'::text,'module_approval_status_summary_1483b5d5'::text), ('bank-master'::text,'module_bank_master_9e57e6ab'::text), ('block-master'::text,'lg_blocks'::text), ('district-master'::text,'lg_districts'::text), ('gram-panchayat-master'::text,'lg_gram_panchayats'::text), ('ics-master'::text,'module_ics_master_483e7ffc'::text), ('jeevika-jankar-bill-approval-history'::text,'module_bill_approval_histories'::text), ('jeevika-jankar-bill-list'::text,'module_jeevika_jankar_bill_list_083c76c4'::text), ('jeevika-jankar-bill-process'::text,'module_bills'::text), ('jeevika-jankar-completed-payment-list'::text,'module_jeevika_jankar_completed_payment_l_bad7b61b'::text), ('jeevika-jankar-observation-list'::text,'module_jeevika_jankar_observation_list_9bfb7dc5'::text), ('jeevika-jankar-payment-detail'::text,'module_payment_details'::text), ('jeevika-jankar-payment-list'::text,'module_jeevika_jankar_payment_list_2e70d942'::text), ('jeevika-jankar-payment-list-detail'::text,'module_jeevika_jankar_payment_list_detail_d8114659'::text), ('jeevika-jankar-transfer'::text,'module_jj_transfers'::text), ('jeevika-jankar-transfer-list'::text,'module_jeevika_jankar_transfer_list_73f1674d'::text), ('lg-directory-import-status'::text,'module_lg_directory_import_status_0543ee43'::text), ('lg-directory-list'::text,'lg_villages'::text), ('month-master'::text,'module_months'::text), ('monthly-bill-summary'::text,'module_monthly_bill_summary_816eb1f0'::text), ('new-user'::text,'module_new_user_6724757d'::text), ('office-category-add'::text,'module_office_categories'::text), ('office-list'::text,'module_office_list_286e3232'::text), ('office-mapping-add'::text,'module_sub_offices'::text), ('other-target'::text,'module_other_targets'::text), ('other-target-list'::text,'module_other_target_list_410d4f4c'::text), ('other-target-with-farmer'::text,'module_other_farmer_targets'::text), ('other-target-with-farmer-list'::text,'module_other_target_with_farmer_list_0d98bf9f'::text), ('papl360-target'::text,'module_papl360_target_e2ff67fc'::text), ('papl360-target-list'::text,'module_papl360_target_list_08d81bec'::text), ('parent-office-add'::text,'module_parent_offices'::text), ('payment-status-report'::text,'module_payment_status_report_17d409eb'::text), ('person-type'::text,'module_person_types'::text), ('position-type'::text,'module_position_type_486dc9a9'::text), ('project-master'::text,'module_projects'::text), ('role-management'::text,'module_role_managements'::text), ('role-name'::text,'module_roles'::text), ('seed-distribution-target'::text,'module_seed_distribution_targets'::text), ('seed-distribution-target-list'::text,'module_seed_distribution_target_list_5453661e'::text), ('stakeholder-master'::text,'module_stakeholders'::text), ('stakeholder-profile'::text,'module_stakeholder_profile_603e5d20'::text), ('stakeholder-role'::text,'module_stakeholder_roles'::text), ('state-master'::text,'lg_states'::text), ('task-completion-indicator'::text,'module_task_completion_indicator_2dc4f3fb'::text), ('task-completion-indicator-list'::text,'module_task_completion_indicator_list_fc8d2b85'::text), ('task-indicator-master'::text,'module_task_indicator_master_c07b884a'::text), ('training-form'::text,'module_trainings'::text), ('training-form-edit-request'::text,'module_training_edit_requests'::text), ('training-form-list'::text,'module_training_form_list_88933913'::text), ('training-topic-mapping'::text,'module_training_topic_mappings'::text), ('user-hierarchy-list'::text,'module_user_hierarchy_list_a4542a91'::text), ('user-hierarchy-mapping'::text,'module_user_hierarchies'::text), ('user-management-role'::text,'module_user_management_roles'::text), ('village-master'::text,'lg_villages'::text), ('vrp-active-status-history'::text,'module_vrp_active_status_history_5a746fcf'::text), ('vrp-activity-list'::text,'module_vrp_activity_list_7d178b72'::text), ('vrp-approval-history'::text,'module_vrp_approval_histories'::text), ('vrp-bill-add'::text,'module_vrp_bill_add_50a221ea'::text), ('vrp-bill-list'::text,'module_vrp_bill_list_0ef6fdc4'::text), ('vrp-registration-list'::text,'module_vrp_registration_list_6a8aeba6'::text), ('weekly-activity-progress'::text,'module_weekly_activity_progress_22c35d60'::text), ('weekly-progress-report'::text,'module_weekly_progress_report_1157600e'::text), ('weekly-target-add'::text,'module_weekly_target_add_ef9d741d'::text), ('weekly-target-list'::text,'module_weekly_target_list_91c4fe5d'::text)) sources(slug, table_name);


--
-- Name: module_record_read_version_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.module_record_read_version_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: module_record_read_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_record_read_versions (
    source_key character varying NOT NULL,
    revision bigint NOT NULL
);


--
-- Name: module_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_records (
    id bigint DEFAULT nextval('public.module_entry_id_seq'::regclass) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    data text NOT NULL,
    module_slug character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: module_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.module_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: module_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.module_records_id_seq OWNED BY public.module_records.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: target_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.target_mappings (
    id bigint NOT NULL,
    vrp_id bigint NOT NULL,
    vrp_ics_mapping_id bigint,
    fco_id character varying NOT NULL,
    fco_name character varying,
    ics_id character varying NOT NULL,
    ics_name character varying,
    village_id character varying NOT NULL,
    village_name character varying,
    farmer_count integer DEFAULT 0 NOT NULL,
    month_name character varying NOT NULL,
    activity_name character varying NOT NULL,
    target_quantity numeric(18,4) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    main_activity_name character varying,
    created_by_type character varying,
    created_by_id bigint,
    afl_ids text DEFAULT '[]'::text NOT NULL,
    completion_date date,
    opg_training_target numeric(18,4),
    week_wise_opg_target numeric(18,4),
    input_demo_inm_target numeric(18,4),
    input_demo_pm_target numeric(18,4),
    ffs_target numeric(18,4),
    week_1_target integer,
    week_2_target integer,
    week_3_target integer,
    week_4_target integer,
    cc_target numeric(18,4),
    target_entry_mode character varying DEFAULT 'ics_wise'::character varying NOT NULL
);


--
-- Name: target_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.target_mappings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: target_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.target_mappings_id_seq OWNED BY public.target_mappings.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    age integer,
    block character varying,
    created_at timestamp(6) without time zone NOT NULL,
    district character varying,
    email character varying,
    emergency_no character varying,
    first_name character varying,
    full_address text,
    gender character varying,
    gram_panchayat character varying,
    last_name character varying,
    mobile_no character varying,
    office character varying,
    parent_office character varying,
    password character varying,
    pincode character varying,
    role character varying,
    stakeholder character varying,
    state character varying,
    status character varying DEFAULT 'Active'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_name character varying NOT NULL,
    user_type character varying,
    village character varying,
    ics character varying,
    stakeholder_role character varying,
    user_management_role character varying,
    person_type character varying,
    role_name character varying,
    office_category character varying,
    office_name character varying,
    sub_office_name character varying
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: vrp_bank_masters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vrp_bank_masters (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    name character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: vrp_bank_masters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vrp_bank_masters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vrp_bank_masters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vrp_bank_masters_id_seq OWNED BY public.vrp_bank_masters.id;


--
-- Name: vrp_ics_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vrp_ics_mappings (
    id bigint NOT NULL,
    vrp_id bigint NOT NULL,
    fco_id character varying NOT NULL,
    fco_name character varying,
    ics_id character varying NOT NULL,
    ics_name character varying,
    village_id character varying NOT NULL,
    village_name character varying,
    afl_ids text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    created_by_type character varying,
    created_by_id bigint
);


--
-- Name: vrp_ics_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vrp_ics_mappings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vrp_ics_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vrp_ics_mappings_id_seq OWNED BY public.vrp_ics_mappings.id;


--
-- Name: vrp_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vrp_profiles (
    id bigint NOT NULL,
    block_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    district_id character varying NOT NULL,
    gram_panchayat_id character varying NOT NULL,
    state_id character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    village_id character varying NOT NULL,
    vrp_id integer NOT NULL
);


--
-- Name: vrp_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vrp_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vrp_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vrp_profiles_id_seq OWNED BY public.vrp_profiles.id;


--
-- Name: vrp_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vrp_types (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    type_name character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: vrp_types_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vrp_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vrp_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vrp_types_id_seq OWNED BY public.vrp_types.id;


--
-- Name: vrps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vrps (
    id bigint NOT NULL,
    aadhar_no character varying NOT NULL,
    account_no character varying NOT NULL,
    address text NOT NULL,
    branch character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_id integer,
    date_of_birth date NOT NULL,
    date_of_joining date NOT NULL,
    email character varying NOT NULL,
    experience_in_years integer NOT NULL,
    father_husband_name character varying NOT NULL,
    gender integer NOT NULL,
    gram_panchayat_ids text,
    ifsc_code character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    mobile_no character varying NOT NULL,
    name character varying NOT NULL,
    office_detail_id integer NOT NULL,
    project_master_ids text,
    status integer DEFAULT 25 NOT NULL,
    to_office_detail_id integer NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id integer,
    village_ids text,
    vrp_bank_master_id integer,
    vrp_type_ids text,
    bank_name character varying,
    ics_master_ids text,
    stakeholder character varying,
    stakeholder_role character varying,
    role character varying,
    user_management_role character varying,
    emergency_no character varying,
    user_name character varying,
    password character varying,
    person_type character varying,
    fcoc character varying,
    cluster_incharge character varying,
    agreement_accepted_at timestamp(6) without time zone,
    to_name character varying,
    agreement_signature_data text,
    created_by_type character varying
);


--
-- Name: vrps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vrps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vrps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vrps_id_seq OWNED BY public.vrps.id;


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: afls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.afls ALTER COLUMN id SET DEFAULT nextval('public.afls_id_seq'::regclass);


--
-- Name: app_user_logins id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user_logins ALTER COLUMN id SET DEFAULT nextval('public.app_user_logins_id_seq'::regclass);


--
-- Name: asa360_master id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asa360_master ALTER COLUMN id SET DEFAULT nextval('public.asa360_master_id_seq'::regclass);


--
-- Name: farmer_app_login_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_app_login_events ALTER COLUMN id SET DEFAULT nextval('public.farmer_app_login_events_id_seq'::regclass);


--
-- Name: farmer_app_logins id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_app_logins ALTER COLUMN id SET DEFAULT nextval('public.farmer_app_logins_id_seq'::regclass);


--
-- Name: farmer_devices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_devices ALTER COLUMN id SET DEFAULT nextval('public.farmer_devices_id_seq'::regclass);


--
-- Name: farmer_login_locks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_login_locks ALTER COLUMN id SET DEFAULT nextval('public.farmer_login_locks_id_seq'::regclass);


--
-- Name: farmer_login_otps id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_login_otps ALTER COLUMN id SET DEFAULT nextval('public.farmer_login_otps_id_seq'::regclass);


--
-- Name: farmer_news id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_news ALTER COLUMN id SET DEFAULT nextval('public.farmer_news_id_seq'::regclass);


--
-- Name: farmer_push_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_push_messages ALTER COLUMN id SET DEFAULT nextval('public.farmer_push_messages_id_seq'::regclass);


--
-- Name: farmer_videos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_videos ALTER COLUMN id SET DEFAULT nextval('public.farmer_videos_id_seq'::regclass);


--
-- Name: jj_quiz_answers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_answers ALTER COLUMN id SET DEFAULT nextval('public.jj_quiz_answers_id_seq'::regclass);


--
-- Name: jj_quiz_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_attempts ALTER COLUMN id SET DEFAULT nextval('public.jj_quiz_attempts_id_seq'::regclass);


--
-- Name: jj_quiz_questions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_questions ALTER COLUMN id SET DEFAULT nextval('public.jj_quiz_questions_id_seq'::regclass);


--
-- Name: jj_quizzes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quizzes ALTER COLUMN id SET DEFAULT nextval('public.jj_quizzes_id_seq'::regclass);


--
-- Name: module_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_entries ALTER COLUMN id SET DEFAULT nextval('public.module_entry_id_seq'::regclass);


--
-- Name: target_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.target_mappings ALTER COLUMN id SET DEFAULT nextval('public.target_mappings_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: vrp_bank_masters id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_bank_masters ALTER COLUMN id SET DEFAULT nextval('public.vrp_bank_masters_id_seq'::regclass);


--
-- Name: vrp_ics_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_ics_mappings ALTER COLUMN id SET DEFAULT nextval('public.vrp_ics_mappings_id_seq'::regclass);


--
-- Name: vrp_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_profiles ALTER COLUMN id SET DEFAULT nextval('public.vrp_profiles_id_seq'::regclass);


--
-- Name: vrp_types id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_types ALTER COLUMN id SET DEFAULT nextval('public.vrp_types_id_seq'::regclass);


--
-- Name: vrps id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrps ALTER COLUMN id SET DEFAULT nextval('public.vrps_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: afls afls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.afls
    ADD CONSTRAINT afls_pkey PRIMARY KEY (id);


--
-- Name: app_user_logins app_user_logins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user_logins
    ADD CONSTRAINT app_user_logins_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: asa360_master asa360_master_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asa360_master
    ADD CONSTRAINT asa360_master_pkey PRIMARY KEY (id);


--
-- Name: farmer_app_login_events farmer_app_login_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_app_login_events
    ADD CONSTRAINT farmer_app_login_events_pkey PRIMARY KEY (id);


--
-- Name: farmer_app_logins farmer_app_logins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_app_logins
    ADD CONSTRAINT farmer_app_logins_pkey PRIMARY KEY (id);


--
-- Name: farmer_devices farmer_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_devices
    ADD CONSTRAINT farmer_devices_pkey PRIMARY KEY (id);


--
-- Name: farmer_login_locks farmer_login_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_login_locks
    ADD CONSTRAINT farmer_login_locks_pkey PRIMARY KEY (id);


--
-- Name: farmer_login_otps farmer_login_otps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_login_otps
    ADD CONSTRAINT farmer_login_otps_pkey PRIMARY KEY (id);


--
-- Name: farmer_news farmer_news_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_news
    ADD CONSTRAINT farmer_news_pkey PRIMARY KEY (id);


--
-- Name: farmer_push_messages farmer_push_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_push_messages
    ADD CONSTRAINT farmer_push_messages_pkey PRIMARY KEY (id);


--
-- Name: farmer_videos farmer_videos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_videos
    ADD CONSTRAINT farmer_videos_pkey PRIMARY KEY (id);


--
-- Name: jj_quiz_answers jj_quiz_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_answers
    ADD CONSTRAINT jj_quiz_answers_pkey PRIMARY KEY (id);


--
-- Name: jj_quiz_attempts jj_quiz_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_attempts
    ADD CONSTRAINT jj_quiz_attempts_pkey PRIMARY KEY (id);


--
-- Name: jj_quiz_questions jj_quiz_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_questions
    ADD CONSTRAINT jj_quiz_questions_pkey PRIMARY KEY (id);


--
-- Name: jj_quizzes jj_quizzes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quizzes
    ADD CONSTRAINT jj_quizzes_pkey PRIMARY KEY (id);


--
-- Name: lg_blocks lg_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lg_blocks
    ADD CONSTRAINT lg_blocks_pkey PRIMARY KEY (id);


--
-- Name: lg_districts lg_districts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lg_districts
    ADD CONSTRAINT lg_districts_pkey PRIMARY KEY (id);


--
-- Name: lg_gram_panchayats lg_gram_panchayats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lg_gram_panchayats
    ADD CONSTRAINT lg_gram_panchayats_pkey PRIMARY KEY (id);


--
-- Name: lg_states lg_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lg_states
    ADD CONSTRAINT lg_states_pkey PRIMARY KEY (id);


--
-- Name: lg_villages lg_villages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lg_villages
    ADD CONSTRAINT lg_villages_pkey PRIMARY KEY (id);


--
-- Name: module_access_control_list_b9d538d4 module_access_control_list_b9d538d4_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_access_control_list_b9d538d4
    ADD CONSTRAINT module_access_control_list_b9d538d4_pkey PRIMARY KEY (id);


--
-- Name: module_access_controls module_access_controls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_access_controls
    ADD CONSTRAINT module_access_controls_pkey PRIMARY KEY (id);


--
-- Name: module_activity_group_list_34a52e96 module_activity_group_list_34a52e96_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_activity_group_list_34a52e96
    ADD CONSTRAINT module_activity_group_list_34a52e96_pkey PRIMARY KEY (id);


--
-- Name: module_activity_master_2e19bce0 module_activity_master_2e19bce0_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_activity_master_2e19bce0
    ADD CONSTRAINT module_activity_master_2e19bce0_pkey PRIMARY KEY (id);


--
-- Name: module_all_user_b8d83be4 module_all_user_b8d83be4_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_all_user_b8d83be4
    ADD CONSTRAINT module_all_user_b8d83be4_pkey PRIMARY KEY (id);


--
-- Name: module_approval_list_27d1da1f module_approval_list_27d1da1f_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_approval_list_27d1da1f
    ADD CONSTRAINT module_approval_list_27d1da1f_pkey PRIMARY KEY (id);


--
-- Name: module_approval_status_summary_1483b5d5 module_approval_status_summary_1483b5d5_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_approval_status_summary_1483b5d5
    ADD CONSTRAINT module_approval_status_summary_1483b5d5_pkey PRIMARY KEY (id);


--
-- Name: module_approvals module_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_approvals
    ADD CONSTRAINT module_approvals_pkey PRIMARY KEY (id);


--
-- Name: module_bank_master_9e57e6ab module_bank_master_9e57e6ab_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_bank_master_9e57e6ab
    ADD CONSTRAINT module_bank_master_9e57e6ab_pkey PRIMARY KEY (id);


--
-- Name: module_bill_approval_histories module_bill_approval_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_bill_approval_histories
    ADD CONSTRAINT module_bill_approval_histories_pkey PRIMARY KEY (id);


--
-- Name: module_bills module_bills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_bills
    ADD CONSTRAINT module_bills_pkey PRIMARY KEY (id);


--
-- Name: module_entry_identities module_entry_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_entry_identities
    ADD CONSTRAINT module_entry_identities_pkey PRIMARY KEY (id);


--
-- Name: module_farmer_forms module_farmer_forms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_farmer_forms
    ADD CONSTRAINT module_farmer_forms_pkey PRIMARY KEY (id);


--
-- Name: module_ics_master_483e7ffc module_ics_master_483e7ffc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_ics_master_483e7ffc
    ADD CONSTRAINT module_ics_master_483e7ffc_pkey PRIMARY KEY (id);


--
-- Name: module_jeevika_jankar_bill_list_083c76c4 module_jeevika_jankar_bill_list_083c76c4_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_jeevika_jankar_bill_list_083c76c4
    ADD CONSTRAINT module_jeevika_jankar_bill_list_083c76c4_pkey PRIMARY KEY (id);


--
-- Name: module_jeevika_jankar_completed_payment_l_bad7b61b module_jeevika_jankar_completed_payment_l_bad7b61b_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_jeevika_jankar_completed_payment_l_bad7b61b
    ADD CONSTRAINT module_jeevika_jankar_completed_payment_l_bad7b61b_pkey PRIMARY KEY (id);


--
-- Name: module_jeevika_jankar_observation_list_9bfb7dc5 module_jeevika_jankar_observation_list_9bfb7dc5_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_jeevika_jankar_observation_list_9bfb7dc5
    ADD CONSTRAINT module_jeevika_jankar_observation_list_9bfb7dc5_pkey PRIMARY KEY (id);


--
-- Name: module_jeevika_jankar_payment_list_2e70d942 module_jeevika_jankar_payment_list_2e70d942_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_jeevika_jankar_payment_list_2e70d942
    ADD CONSTRAINT module_jeevika_jankar_payment_list_2e70d942_pkey PRIMARY KEY (id);


--
-- Name: module_jeevika_jankar_payment_list_detail_d8114659 module_jeevika_jankar_payment_list_detail_d8114659_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_jeevika_jankar_payment_list_detail_d8114659
    ADD CONSTRAINT module_jeevika_jankar_payment_list_detail_d8114659_pkey PRIMARY KEY (id);


--
-- Name: module_jeevika_jankar_transfer_list_73f1674d module_jeevika_jankar_transfer_list_73f1674d_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_jeevika_jankar_transfer_list_73f1674d
    ADD CONSTRAINT module_jeevika_jankar_transfer_list_73f1674d_pkey PRIMARY KEY (id);


--
-- Name: module_jj_transfers module_jj_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_jj_transfers
    ADD CONSTRAINT module_jj_transfers_pkey PRIMARY KEY (id);


--
-- Name: module_lg_directory_import_status_0543ee43 module_lg_directory_import_status_0543ee43_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_lg_directory_import_status_0543ee43
    ADD CONSTRAINT module_lg_directory_import_status_0543ee43_pkey PRIMARY KEY (id);


--
-- Name: module_main_activities module_main_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_main_activities
    ADD CONSTRAINT module_main_activities_pkey PRIMARY KEY (id);


--
-- Name: module_monthly_bill_summary_816eb1f0 module_monthly_bill_summary_816eb1f0_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_monthly_bill_summary_816eb1f0
    ADD CONSTRAINT module_monthly_bill_summary_816eb1f0_pkey PRIMARY KEY (id);


--
-- Name: module_months module_months_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_months
    ADD CONSTRAINT module_months_pkey PRIMARY KEY (id);


--
-- Name: module_new_user_6724757d module_new_user_6724757d_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_new_user_6724757d
    ADD CONSTRAINT module_new_user_6724757d_pkey PRIMARY KEY (id);


--
-- Name: module_office_categories module_office_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_office_categories
    ADD CONSTRAINT module_office_categories_pkey PRIMARY KEY (id);


--
-- Name: module_office_list_286e3232 module_office_list_286e3232_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_office_list_286e3232
    ADD CONSTRAINT module_office_list_286e3232_pkey PRIMARY KEY (id);


--
-- Name: module_other_farmer_targets module_other_farmer_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_other_farmer_targets
    ADD CONSTRAINT module_other_farmer_targets_pkey PRIMARY KEY (id);


--
-- Name: module_other_target_list_410d4f4c module_other_target_list_410d4f4c_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_other_target_list_410d4f4c
    ADD CONSTRAINT module_other_target_list_410d4f4c_pkey PRIMARY KEY (id);


--
-- Name: module_other_target_with_farmer_list_0d98bf9f module_other_target_with_farmer_list_0d98bf9f_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_other_target_with_farmer_list_0d98bf9f
    ADD CONSTRAINT module_other_target_with_farmer_list_0d98bf9f_pkey PRIMARY KEY (id);


--
-- Name: module_other_targets module_other_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_other_targets
    ADD CONSTRAINT module_other_targets_pkey PRIMARY KEY (id);


--
-- Name: module_papl360_target_e2ff67fc module_papl360_target_e2ff67fc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_papl360_target_e2ff67fc
    ADD CONSTRAINT module_papl360_target_e2ff67fc_pkey PRIMARY KEY (id);


--
-- Name: module_papl360_target_list_08d81bec module_papl360_target_list_08d81bec_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_papl360_target_list_08d81bec
    ADD CONSTRAINT module_papl360_target_list_08d81bec_pkey PRIMARY KEY (id);


--
-- Name: module_parent_offices module_parent_offices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_parent_offices
    ADD CONSTRAINT module_parent_offices_pkey PRIMARY KEY (id);


--
-- Name: module_payment_details module_payment_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_payment_details
    ADD CONSTRAINT module_payment_details_pkey PRIMARY KEY (id);


--
-- Name: module_payment_status_report_17d409eb module_payment_status_report_17d409eb_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_payment_status_report_17d409eb
    ADD CONSTRAINT module_payment_status_report_17d409eb_pkey PRIMARY KEY (id);


--
-- Name: module_person_types module_person_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_person_types
    ADD CONSTRAINT module_person_types_pkey PRIMARY KEY (id);


--
-- Name: module_position_type_486dc9a9 module_position_type_486dc9a9_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_position_type_486dc9a9
    ADD CONSTRAINT module_position_type_486dc9a9_pkey PRIMARY KEY (id);


--
-- Name: module_projects module_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_projects
    ADD CONSTRAINT module_projects_pkey PRIMARY KEY (id);


--
-- Name: module_record_read_versions module_record_read_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_record_read_versions
    ADD CONSTRAINT module_record_read_versions_pkey PRIMARY KEY (source_key);


--
-- Name: module_records module_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_records
    ADD CONSTRAINT module_records_pkey PRIMARY KEY (id);


--
-- Name: module_role_managements module_role_managements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_role_managements
    ADD CONSTRAINT module_role_managements_pkey PRIMARY KEY (id);


--
-- Name: module_roles module_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_roles
    ADD CONSTRAINT module_roles_pkey PRIMARY KEY (id);


--
-- Name: module_seed_distribution_target_list_5453661e module_seed_distribution_target_list_5453661e_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_seed_distribution_target_list_5453661e
    ADD CONSTRAINT module_seed_distribution_target_list_5453661e_pkey PRIMARY KEY (id);


--
-- Name: module_seed_distribution_targets module_seed_distribution_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_seed_distribution_targets
    ADD CONSTRAINT module_seed_distribution_targets_pkey PRIMARY KEY (id);


--
-- Name: module_stakeholder_profile_603e5d20 module_stakeholder_profile_603e5d20_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_stakeholder_profile_603e5d20
    ADD CONSTRAINT module_stakeholder_profile_603e5d20_pkey PRIMARY KEY (id);


--
-- Name: module_stakeholder_roles module_stakeholder_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_stakeholder_roles
    ADD CONSTRAINT module_stakeholder_roles_pkey PRIMARY KEY (id);


--
-- Name: module_stakeholders module_stakeholders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_stakeholders
    ADD CONSTRAINT module_stakeholders_pkey PRIMARY KEY (id);


--
-- Name: module_sub_activities module_sub_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_sub_activities
    ADD CONSTRAINT module_sub_activities_pkey PRIMARY KEY (id);


--
-- Name: module_sub_offices module_sub_offices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_sub_offices
    ADD CONSTRAINT module_sub_offices_pkey PRIMARY KEY (id);


--
-- Name: module_task_completion_indicator_2dc4f3fb module_task_completion_indicator_2dc4f3fb_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_task_completion_indicator_2dc4f3fb
    ADD CONSTRAINT module_task_completion_indicator_2dc4f3fb_pkey PRIMARY KEY (id);


--
-- Name: module_task_completion_indicator_list_fc8d2b85 module_task_completion_indicator_list_fc8d2b85_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_task_completion_indicator_list_fc8d2b85
    ADD CONSTRAINT module_task_completion_indicator_list_fc8d2b85_pkey PRIMARY KEY (id);


--
-- Name: module_task_indicator_master_c07b884a module_task_indicator_master_c07b884a_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_task_indicator_master_c07b884a
    ADD CONSTRAINT module_task_indicator_master_c07b884a_pkey PRIMARY KEY (id);


--
-- Name: module_training_edit_requests module_training_edit_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_training_edit_requests
    ADD CONSTRAINT module_training_edit_requests_pkey PRIMARY KEY (id);


--
-- Name: module_training_form_list_88933913 module_training_form_list_88933913_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_training_form_list_88933913
    ADD CONSTRAINT module_training_form_list_88933913_pkey PRIMARY KEY (id);


--
-- Name: module_training_topic_mappings module_training_topic_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_training_topic_mappings
    ADD CONSTRAINT module_training_topic_mappings_pkey PRIMARY KEY (id);


--
-- Name: module_trainings module_trainings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_trainings
    ADD CONSTRAINT module_trainings_pkey PRIMARY KEY (id);


--
-- Name: module_user_hierarchies module_user_hierarchies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_user_hierarchies
    ADD CONSTRAINT module_user_hierarchies_pkey PRIMARY KEY (id);


--
-- Name: module_user_hierarchy_list_a4542a91 module_user_hierarchy_list_a4542a91_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_user_hierarchy_list_a4542a91
    ADD CONSTRAINT module_user_hierarchy_list_a4542a91_pkey PRIMARY KEY (id);


--
-- Name: module_user_management_roles module_user_management_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_user_management_roles
    ADD CONSTRAINT module_user_management_roles_pkey PRIMARY KEY (id);


--
-- Name: module_vrp_active_status_history_5a746fcf module_vrp_active_status_history_5a746fcf_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_vrp_active_status_history_5a746fcf
    ADD CONSTRAINT module_vrp_active_status_history_5a746fcf_pkey PRIMARY KEY (id);


--
-- Name: module_vrp_activity_list_7d178b72 module_vrp_activity_list_7d178b72_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_vrp_activity_list_7d178b72
    ADD CONSTRAINT module_vrp_activity_list_7d178b72_pkey PRIMARY KEY (id);


--
-- Name: module_vrp_approval_histories module_vrp_approval_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_vrp_approval_histories
    ADD CONSTRAINT module_vrp_approval_histories_pkey PRIMARY KEY (id);


--
-- Name: module_vrp_bill_add_50a221ea module_vrp_bill_add_50a221ea_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_vrp_bill_add_50a221ea
    ADD CONSTRAINT module_vrp_bill_add_50a221ea_pkey PRIMARY KEY (id);


--
-- Name: module_vrp_bill_list_0ef6fdc4 module_vrp_bill_list_0ef6fdc4_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_vrp_bill_list_0ef6fdc4
    ADD CONSTRAINT module_vrp_bill_list_0ef6fdc4_pkey PRIMARY KEY (id);


--
-- Name: module_vrp_registration_list_6a8aeba6 module_vrp_registration_list_6a8aeba6_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_vrp_registration_list_6a8aeba6
    ADD CONSTRAINT module_vrp_registration_list_6a8aeba6_pkey PRIMARY KEY (id);


--
-- Name: module_vrp_types module_vrp_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_vrp_types
    ADD CONSTRAINT module_vrp_types_pkey PRIMARY KEY (id);


--
-- Name: module_weekly_activity_progress_22c35d60 module_weekly_activity_progress_22c35d60_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_weekly_activity_progress_22c35d60
    ADD CONSTRAINT module_weekly_activity_progress_22c35d60_pkey PRIMARY KEY (id);


--
-- Name: module_weekly_progress_report_1157600e module_weekly_progress_report_1157600e_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_weekly_progress_report_1157600e
    ADD CONSTRAINT module_weekly_progress_report_1157600e_pkey PRIMARY KEY (id);


--
-- Name: module_weekly_target_add_ef9d741d module_weekly_target_add_ef9d741d_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_weekly_target_add_ef9d741d
    ADD CONSTRAINT module_weekly_target_add_ef9d741d_pkey PRIMARY KEY (id);


--
-- Name: module_weekly_target_list_91c4fe5d module_weekly_target_list_91c4fe5d_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_weekly_target_list_91c4fe5d
    ADD CONSTRAINT module_weekly_target_list_91c4fe5d_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: target_mappings target_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.target_mappings
    ADD CONSTRAINT target_mappings_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: vrp_bank_masters vrp_bank_masters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_bank_masters
    ADD CONSTRAINT vrp_bank_masters_pkey PRIMARY KEY (id);


--
-- Name: vrp_ics_mappings vrp_ics_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_ics_mappings
    ADD CONSTRAINT vrp_ics_mappings_pkey PRIMARY KEY (id);


--
-- Name: vrp_profiles vrp_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_profiles
    ADD CONSTRAINT vrp_profiles_pkey PRIMARY KEY (id);


--
-- Name: vrp_types vrp_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_types
    ADD CONSTRAINT vrp_types_pkey PRIMARY KEY (id);


--
-- Name: vrps vrps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrps
    ADD CONSTRAINT vrps_pkey PRIMARY KEY (id);


--
-- Name: idx_jj_answers_on_attempt_and_question; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_jj_answers_on_attempt_and_question ON public.jj_quiz_answers USING btree (jj_quiz_attempt_id, jj_quiz_question_id);


--
-- Name: idx_on_created_at_151063a974; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_created_at_151063a974 ON public.module_jeevika_jankar_observation_list_9bfb7dc5 USING btree (created_at);


--
-- Name: idx_on_created_at_2b43a9ffc0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_created_at_2b43a9ffc0 ON public.module_jeevika_jankar_transfer_list_73f1674d USING btree (created_at);


--
-- Name: idx_on_created_at_3516a8b79e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_created_at_3516a8b79e ON public.module_jeevika_jankar_completed_payment_l_bad7b61b USING btree (created_at);


--
-- Name: idx_on_created_at_7c99fa6737; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_created_at_7c99fa6737 ON public.module_task_completion_indicator_list_fc8d2b85 USING btree (created_at);


--
-- Name: idx_on_created_at_9c89d2a1b3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_created_at_9c89d2a1b3 ON public.module_jeevika_jankar_payment_list_detail_d8114659 USING btree (created_at);


--
-- Name: idx_on_created_at_a59f031d7e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_created_at_a59f031d7e ON public.module_jeevika_jankar_payment_list_2e70d942 USING btree (created_at);


--
-- Name: idx_on_created_at_c7072152d4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_created_at_c7072152d4 ON public.module_seed_distribution_target_list_5453661e USING btree (created_at);


--
-- Name: idx_on_created_at_ca2b8c330d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_created_at_ca2b8c330d ON public.module_other_target_with_farmer_list_0d98bf9f USING btree (created_at);


--
-- Name: idx_on_main_activity_sub_activity_name_7a91dcb2a3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_main_activity_sub_activity_name_7a91dcb2a3 ON public.module_sub_activities USING btree (main_activity, sub_activity_name);


--
-- Name: idx_on_stakeholder_category_office_level_5bb4cc8ce0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_stakeholder_category_office_level_5bb4cc8ce0 ON public.module_parent_offices USING btree (stakeholder_category, office_level);


--
-- Name: idx_on_stakeholder_category_stakeholder_role_5f7f62ad08; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_stakeholder_category_stakeholder_role_5f7f62ad08 ON public.module_roles USING btree (stakeholder_category, stakeholder_role);


--
-- Name: idx_on_stakeholder_category_stakeholder_role_cd8b188480; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_stakeholder_category_stakeholder_role_cd8b188480 ON public.module_stakeholder_roles USING btree (stakeholder_category, stakeholder_role);


--
-- Name: idx_on_updated_at_03f3d68a4b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_updated_at_03f3d68a4b ON public.module_jeevika_jankar_completed_payment_l_bad7b61b USING btree (updated_at);


--
-- Name: idx_on_updated_at_24c69125b6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_updated_at_24c69125b6 ON public.module_jeevika_jankar_transfer_list_73f1674d USING btree (updated_at);


--
-- Name: idx_on_updated_at_4abfb08ab5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_updated_at_4abfb08ab5 ON public.module_jeevika_jankar_payment_list_detail_d8114659 USING btree (updated_at);


--
-- Name: idx_on_updated_at_974f366457; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_updated_at_974f366457 ON public.module_seed_distribution_target_list_5453661e USING btree (updated_at);


--
-- Name: idx_on_updated_at_9b09b7ee1e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_updated_at_9b09b7ee1e ON public.module_jeevika_jankar_observation_list_9bfb7dc5 USING btree (updated_at);


--
-- Name: idx_on_updated_at_a3320af5d0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_updated_at_a3320af5d0 ON public.module_jeevika_jankar_payment_list_2e70d942 USING btree (updated_at);


--
-- Name: idx_on_updated_at_c4e9e19a39; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_updated_at_c4e9e19a39 ON public.module_other_target_with_farmer_list_0d98bf9f USING btree (updated_at);


--
-- Name: idx_on_updated_at_d121c80dce; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_updated_at_d121c80dce ON public.module_task_completion_indicator_list_fc8d2b85 USING btree (updated_at);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_afls_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_created_at ON public.afls USING btree (created_at);


--
-- Name: index_afls_on_farm_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_farm_id ON public.afls USING btree (farm_id);


--
-- Name: index_afls_on_farmer_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_farmer_name ON public.afls USING btree (farmer_name);


--
-- Name: index_afls_on_mapping_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_mapping_lookup ON public.afls USING btree (fco_id, ics_id, village_id);


--
-- Name: index_afls_on_mobile_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_mobile_no ON public.afls USING btree (mobile_no);


--
-- Name: index_afls_on_normalized_fco_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_normalized_fco_id ON public.afls USING btree (lower(btrim((fco_id)::text)));


--
-- Name: index_afls_on_normalized_fco_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_normalized_fco_name ON public.afls USING btree (lower(btrim((fco)::text)));


--
-- Name: index_afls_on_slip_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_slip_no ON public.afls USING btree (slip_no);


--
-- Name: index_afls_on_tracenet_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_tracenet_no ON public.afls USING btree (tracenet_no);


--
-- Name: index_afls_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_updated_at ON public.afls USING btree (updated_at DESC);


--
-- Name: index_afls_on_village_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_afls_on_village_id ON public.afls USING btree (village_id);


--
-- Name: index_app_user_logins_on_logged_in_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_user_logins_on_logged_in_at ON public.app_user_logins USING btree (logged_in_at DESC);


--
-- Name: index_app_user_logins_on_user_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_user_logins_on_user_and_time ON public.app_user_logins USING btree (record_type, record_id, logged_in_at);


--
-- Name: index_entry_bill_history_on_bill_and_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_bill_history_on_bill_and_order ON public.module_bill_approval_histories USING btree ((((payload_text)::jsonb ->> 'bill_id'::text)), created_at, id);


--
-- Name: index_entry_edits_on_record_and_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_edits_on_record_and_latest ON public.module_training_edit_requests USING btree ((((payload_text)::jsonb ->> 'record_id'::text)), id DESC);


--
-- Name: index_entry_edits_on_status_and_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_edits_on_status_and_latest ON public.module_training_edit_requests USING btree ((((payload_text)::jsonb ->> 'status'::text)), id DESC);


--
-- Name: index_entry_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_users_on_lower_email ON public.module_new_user_6724757d USING btree (lower(((payload_text)::jsonb ->> 'email'::text)));


--
-- Name: index_entry_users_on_lower_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_users_on_lower_username ON public.module_new_user_6724757d USING btree (lower(((payload_text)::jsonb ->> 'user_name'::text)));


--
-- Name: index_entry_users_on_mobile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_users_on_mobile ON public.module_new_user_6724757d USING btree ((((payload_text)::jsonb ->> 'mobile_no'::text)));


--
-- Name: index_entry_users_on_normalized_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_users_on_normalized_email ON public.module_new_user_6724757d USING btree (lower(btrim(((payload_text)::jsonb ->> 'email'::text))));


--
-- Name: index_entry_users_on_normalized_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_users_on_normalized_username ON public.module_new_user_6724757d USING btree (lower(btrim(COALESCE(((payload_text)::jsonb ->> 'user_name'::text), ''::text))));


--
-- Name: index_entry_users_on_username_and_updated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_users_on_username_and_updated ON public.module_new_user_6724757d USING btree ((((payload_text)::jsonb ->> 'user_name'::text)), updated_at DESC);


--
-- Name: index_entry_vrp_history_on_owner_and_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entry_vrp_history_on_owner_and_order ON public.module_vrp_approval_histories USING btree ((((payload_text)::jsonb ->> 'vrp_id'::text)), created_at, id);


--
-- Name: index_farmer_app_login_events_on_logged_in_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_app_login_events_on_logged_in_at ON public.farmer_app_login_events USING btree (logged_in_at DESC);


--
-- Name: index_farmer_app_logins_on_aadhaar_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_app_logins_on_aadhaar_digest ON public.farmer_app_logins USING btree (aadhaar_digest);


--
-- Name: index_farmer_app_logins_on_farmer_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_farmer_app_logins_on_farmer_external_id ON public.farmer_app_logins USING btree (farmer_external_id);


--
-- Name: index_farmer_app_logins_on_last_logged_in_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_app_logins_on_last_logged_in_at ON public.farmer_app_logins USING btree (last_logged_in_at DESC);


--
-- Name: index_farmer_app_logins_on_mobile_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_app_logins_on_mobile_no ON public.farmer_app_logins USING btree (mobile_no);


--
-- Name: index_farmer_app_logins_on_state_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_app_logins_on_state_id ON public.farmer_app_logins USING btree (state_id);


--
-- Name: index_farmer_devices_on_login_and_seen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_devices_on_login_and_seen ON public.farmer_devices USING btree (farmer_app_login_id, last_seen_at);


--
-- Name: index_farmer_devices_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_farmer_devices_on_token ON public.farmer_devices USING btree (token);


--
-- Name: index_farmer_login_events_on_login_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_login_events_on_login_and_time ON public.farmer_app_login_events USING btree (farmer_app_login_id, logged_in_at);


--
-- Name: index_farmer_login_locks_on_locked_until; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_login_locks_on_locked_until ON public.farmer_login_locks USING btree (locked_until);


--
-- Name: index_farmer_login_locks_on_mobile_no; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_farmer_login_locks_on_mobile_no ON public.farmer_login_locks USING btree (mobile_no);


--
-- Name: index_farmer_login_otps_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_login_otps_on_expires_at ON public.farmer_login_otps USING btree (expires_at);


--
-- Name: index_farmer_login_otps_on_jti; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_farmer_login_otps_on_jti ON public.farmer_login_otps USING btree (jti);


--
-- Name: index_farmer_login_otps_on_mobile_no_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_login_otps_on_mobile_no_and_created_at ON public.farmer_login_otps USING btree (mobile_no, created_at);


--
-- Name: index_farmer_news_on_feed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_news_on_feed ON public.farmer_news USING btree (status, state_id, published_at DESC);


--
-- Name: index_farmer_push_messages_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_push_messages_on_created_at ON public.farmer_push_messages USING btree (created_at DESC);


--
-- Name: index_farmer_push_messages_on_notifiable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_push_messages_on_notifiable ON public.farmer_push_messages USING btree (notifiable_type, notifiable_id);


--
-- Name: index_farmer_videos_on_feed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_farmer_videos_on_feed ON public.farmer_videos USING btree (status, state_id, published_at DESC);


--
-- Name: index_jj_bill_history_on_bill_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_bill_history_on_bill_id ON public.module_records USING btree ((((data)::jsonb ->> 'bill_id'::text))) WHERE ((module_slug)::text = 'jeevika-jankar-bill-approval-history'::text);


--
-- Name: index_jj_bills_on_module_slug_and_bill_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_bills_on_module_slug_and_bill_month ON public.module_records USING btree (module_slug, (((data)::jsonb ->> 'bill_month'::text))) WHERE ((module_slug)::text = 'jeevika-jankar-bill-process'::text);


--
-- Name: index_jj_quiz_answers_on_jj_quiz_attempt_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quiz_answers_on_jj_quiz_attempt_id ON public.jj_quiz_answers USING btree (jj_quiz_attempt_id);


--
-- Name: index_jj_quiz_answers_on_jj_quiz_question_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quiz_answers_on_jj_quiz_question_id ON public.jj_quiz_answers USING btree (jj_quiz_question_id);


--
-- Name: index_jj_quiz_attempts_on_access_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_jj_quiz_attempts_on_access_token ON public.jj_quiz_attempts USING btree (access_token);


--
-- Name: index_jj_quiz_attempts_on_jj_quiz_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quiz_attempts_on_jj_quiz_id ON public.jj_quiz_attempts USING btree (jj_quiz_id);


--
-- Name: index_jj_quiz_attempts_on_jj_quiz_id_and_vrp_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quiz_attempts_on_jj_quiz_id_and_vrp_id ON public.jj_quiz_attempts USING btree (jj_quiz_id, vrp_id);


--
-- Name: index_jj_quiz_attempts_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quiz_attempts_on_status ON public.jj_quiz_attempts USING btree (status);


--
-- Name: index_jj_quiz_attempts_on_vrp_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quiz_attempts_on_vrp_id ON public.jj_quiz_attempts USING btree (vrp_id);


--
-- Name: index_jj_quiz_questions_on_jj_quiz_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quiz_questions_on_jj_quiz_id ON public.jj_quiz_questions USING btree (jj_quiz_id);


--
-- Name: index_jj_quiz_questions_on_jj_quiz_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quiz_questions_on_jj_quiz_id_and_position ON public.jj_quiz_questions USING btree (jj_quiz_id, "position");


--
-- Name: index_jj_quiz_questions_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quiz_questions_on_status ON public.jj_quiz_questions USING btree (status);


--
-- Name: index_jj_quizzes_on_created_by_type_and_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quizzes_on_created_by_type_and_created_by_id ON public.jj_quizzes USING btree (created_by_type, created_by_id);


--
-- Name: index_jj_quizzes_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jj_quizzes_on_status ON public.jj_quizzes USING btree (status);


--
-- Name: index_lg_blocks_on_active_and_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_blocks_on_active_and_source ON public.lg_blocks USING btree (active, source_slug);


--
-- Name: index_lg_blocks_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_blocks_on_created_at ON public.lg_blocks USING btree (created_at);


--
-- Name: index_lg_blocks_on_normalized_district; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_blocks_on_normalized_district ON public.lg_blocks USING btree (lower(btrim((district_name)::text)));


--
-- Name: index_lg_blocks_on_normalized_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_blocks_on_normalized_name ON public.lg_blocks USING btree (lower(btrim((block_name)::text)));


--
-- Name: index_lg_blocks_on_source_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_blocks_on_source_slug ON public.lg_blocks USING btree (source_slug);


--
-- Name: index_lg_districts_on_active_and_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_districts_on_active_and_source ON public.lg_districts USING btree (active, source_slug);


--
-- Name: index_lg_districts_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_districts_on_created_at ON public.lg_districts USING btree (created_at);


--
-- Name: index_lg_districts_on_normalized_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_districts_on_normalized_name ON public.lg_districts USING btree (lower(btrim((district_name)::text)));


--
-- Name: index_lg_districts_on_normalized_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_districts_on_normalized_state ON public.lg_districts USING btree (lower(btrim((state_name)::text)));


--
-- Name: index_lg_districts_on_source_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_districts_on_source_slug ON public.lg_districts USING btree (source_slug);


--
-- Name: index_lg_gps_on_normalized_block; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_gps_on_normalized_block ON public.lg_gram_panchayats USING btree (lower(btrim((block_name)::text)));


--
-- Name: index_lg_gps_on_normalized_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_gps_on_normalized_name ON public.lg_gram_panchayats USING btree (lower(btrim((gram_panchayat_name)::text)));


--
-- Name: index_lg_gram_panchayats_on_active_and_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_gram_panchayats_on_active_and_source ON public.lg_gram_panchayats USING btree (active, source_slug);


--
-- Name: index_lg_gram_panchayats_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_gram_panchayats_on_created_at ON public.lg_gram_panchayats USING btree (created_at);


--
-- Name: index_lg_gram_panchayats_on_source_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_gram_panchayats_on_source_slug ON public.lg_gram_panchayats USING btree (source_slug);


--
-- Name: index_lg_states_on_active_and_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_states_on_active_and_source ON public.lg_states USING btree (active, source_slug);


--
-- Name: index_lg_states_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_states_on_created_at ON public.lg_states USING btree (created_at);


--
-- Name: index_lg_states_on_normalized_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_states_on_normalized_name ON public.lg_states USING btree (lower(btrim((state_name)::text)));


--
-- Name: index_lg_states_on_source_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_states_on_source_slug ON public.lg_states USING btree (source_slug);


--
-- Name: index_lg_villages_on_active_and_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_villages_on_active_and_source ON public.lg_villages USING btree (active, source_slug);


--
-- Name: index_lg_villages_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_villages_on_created_at ON public.lg_villages USING btree (created_at);


--
-- Name: index_lg_villages_on_normalized_block; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_villages_on_normalized_block ON public.lg_villages USING btree (lower(btrim((block_name)::text)));


--
-- Name: index_lg_villages_on_normalized_gp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_villages_on_normalized_gp ON public.lg_villages USING btree (lower(btrim((gram_panchayat_name)::text)));


--
-- Name: index_lg_villages_on_normalized_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_villages_on_normalized_name ON public.lg_villages USING btree (lower(btrim((village_name)::text)));


--
-- Name: index_lg_villages_on_source_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_villages_on_source_slug ON public.lg_villages USING btree (source_slug);


--
-- Name: index_lg_villages_on_village_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lg_villages_on_village_code ON public.lg_villages USING btree (village_code);


--
-- Name: index_module_access_control_list_b9d538d4_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_control_list_b9d538d4_on_created_at ON public.module_access_control_list_b9d538d4 USING btree (created_at);


--
-- Name: index_module_access_control_list_b9d538d4_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_control_list_b9d538d4_on_updated_at ON public.module_access_control_list_b9d538d4 USING btree (updated_at);


--
-- Name: index_module_access_controls_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_controls_on_active ON public.module_access_controls USING btree (active);


--
-- Name: index_module_access_controls_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_controls_on_created_at ON public.module_access_controls USING btree (created_at);


--
-- Name: index_module_access_controls_on_normalized_can_view; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_controls_on_normalized_can_view ON public.module_access_controls USING btree (lower(btrim(can_view)));


--
-- Name: index_module_access_controls_on_normalized_role_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_controls_on_normalized_role_name ON public.module_access_controls USING btree (lower(btrim(role_name)));


--
-- Name: index_module_access_controls_on_normalized_stakeholder; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_controls_on_normalized_stakeholder ON public.module_access_controls USING btree (lower(btrim(stakeholder)));


--
-- Name: index_module_access_controls_on_normalized_stakeholder_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_controls_on_normalized_stakeholder_role ON public.module_access_controls USING btree (lower(btrim(stakeholder_role)));


--
-- Name: index_module_access_controls_on_role_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_controls_on_role_name ON public.module_access_controls USING btree (role_name);


--
-- Name: index_module_access_controls_on_stakeholder_role_and_role_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_access_controls_on_stakeholder_role_and_role_name ON public.module_access_controls USING btree (stakeholder_role, role_name);


--
-- Name: index_module_activity_group_list_34a52e96_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_activity_group_list_34a52e96_on_created_at ON public.module_activity_group_list_34a52e96 USING btree (created_at);


--
-- Name: index_module_activity_group_list_34a52e96_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_activity_group_list_34a52e96_on_updated_at ON public.module_activity_group_list_34a52e96 USING btree (updated_at);


--
-- Name: index_module_activity_master_2e19bce0_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_activity_master_2e19bce0_on_created_at ON public.module_activity_master_2e19bce0 USING btree (created_at);


--
-- Name: index_module_activity_master_2e19bce0_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_activity_master_2e19bce0_on_updated_at ON public.module_activity_master_2e19bce0 USING btree (updated_at);


--
-- Name: index_module_all_user_b8d83be4_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_all_user_b8d83be4_on_created_at ON public.module_all_user_b8d83be4 USING btree (created_at);


--
-- Name: index_module_all_user_b8d83be4_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_all_user_b8d83be4_on_updated_at ON public.module_all_user_b8d83be4 USING btree (updated_at);


--
-- Name: index_module_approval_list_27d1da1f_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approval_list_27d1da1f_on_created_at ON public.module_approval_list_27d1da1f USING btree (created_at);


--
-- Name: index_module_approval_list_27d1da1f_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approval_list_27d1da1f_on_updated_at ON public.module_approval_list_27d1da1f USING btree (updated_at);


--
-- Name: index_module_approval_status_summary_1483b5d5_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approval_status_summary_1483b5d5_on_created_at ON public.module_approval_status_summary_1483b5d5 USING btree (created_at);


--
-- Name: index_module_approval_status_summary_1483b5d5_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approval_status_summary_1483b5d5_on_updated_at ON public.module_approval_status_summary_1483b5d5 USING btree (updated_at);


--
-- Name: index_module_approvals_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approvals_on_active ON public.module_approvals USING btree (active);


--
-- Name: index_module_approvals_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approvals_on_created_at ON public.module_approvals USING btree (created_at);


--
-- Name: index_module_approvals_on_module_name_and_approval_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approvals_on_module_name_and_approval_level ON public.module_approvals USING btree (module_name, approval_level);


--
-- Name: index_module_approvals_on_normalized_approval_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approvals_on_normalized_approval_level ON public.module_approvals USING btree (lower(btrim(approval_level)));


--
-- Name: index_module_approvals_on_normalized_module_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approvals_on_normalized_module_name ON public.module_approvals USING btree (lower(btrim(module_name)));


--
-- Name: index_module_approvals_on_normalized_role_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approvals_on_normalized_role_name ON public.module_approvals USING btree (lower(btrim(role_name)));


--
-- Name: index_module_approvals_on_normalized_stakeholder_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_approvals_on_normalized_stakeholder_role ON public.module_approvals USING btree (lower(btrim(stakeholder_role)));


--
-- Name: index_module_bank_master_9e57e6ab_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bank_master_9e57e6ab_on_created_at ON public.module_bank_master_9e57e6ab USING btree (created_at);


--
-- Name: index_module_bank_master_9e57e6ab_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bank_master_9e57e6ab_on_updated_at ON public.module_bank_master_9e57e6ab USING btree (updated_at);


--
-- Name: index_module_bill_approval_histories_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bill_approval_histories_on_created_at ON public.module_bill_approval_histories USING btree (created_at);


--
-- Name: index_module_bill_approval_histories_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bill_approval_histories_on_updated_at ON public.module_bill_approval_histories USING btree (updated_at);


--
-- Name: index_module_bills_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_active ON public.module_bills USING btree (active);


--
-- Name: index_module_bills_on_bill_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_bill_month ON public.module_bills USING btree (bill_month);


--
-- Name: index_module_bills_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_created_at ON public.module_bills USING btree (created_at);


--
-- Name: index_module_bills_on_normalized_bill_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_normalized_bill_month ON public.module_bills USING btree (lower(btrim(bill_month)));


--
-- Name: index_module_bills_on_normalized_bill_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_normalized_bill_status ON public.module_bills USING btree (lower(btrim(bill_status)));


--
-- Name: index_module_bills_on_normalized_grand_total; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_normalized_grand_total ON public.module_bills USING btree (lower(btrim(grand_total)));


--
-- Name: index_module_bills_on_normalized_select_vrp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_normalized_select_vrp ON public.module_bills USING btree (lower(btrim(select_vrp)));


--
-- Name: index_module_bills_on_payload_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_payload_month ON public.module_bills USING btree (((data ->> 'bill_month'::text)));


--
-- Name: index_module_bills_on_payload_owner_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_payload_owner_month ON public.module_bills USING btree (((data ->> 'select_vrp'::text)), ((data ->> 'bill_month'::text)));


--
-- Name: index_module_bills_on_select_vrp_and_bill_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_bills_on_select_vrp_and_bill_month ON public.module_bills USING btree (select_vrp, bill_month);


--
-- Name: index_module_entry_identities_on_module_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_entry_identities_on_module_slug ON public.module_entry_identities USING btree (module_slug);


--
-- Name: index_module_farmer_forms_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_farmer_forms_on_created_at ON public.module_farmer_forms USING btree (created_at);


--
-- Name: index_module_farmer_forms_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_farmer_forms_on_updated_at ON public.module_farmer_forms USING btree (updated_at);


--
-- Name: index_module_ics_master_483e7ffc_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_ics_master_483e7ffc_on_created_at ON public.module_ics_master_483e7ffc USING btree (created_at);


--
-- Name: index_module_ics_master_483e7ffc_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_ics_master_483e7ffc_on_updated_at ON public.module_ics_master_483e7ffc USING btree (updated_at);


--
-- Name: index_module_jeevika_jankar_bill_list_083c76c4_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jeevika_jankar_bill_list_083c76c4_on_created_at ON public.module_jeevika_jankar_bill_list_083c76c4 USING btree (created_at);


--
-- Name: index_module_jeevika_jankar_bill_list_083c76c4_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jeevika_jankar_bill_list_083c76c4_on_updated_at ON public.module_jeevika_jankar_bill_list_083c76c4 USING btree (updated_at);


--
-- Name: index_module_jj_transfers_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jj_transfers_on_active ON public.module_jj_transfers USING btree (active);


--
-- Name: index_module_jj_transfers_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jj_transfers_on_created_at ON public.module_jj_transfers USING btree (created_at);


--
-- Name: index_module_jj_transfers_on_fcoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jj_transfers_on_fcoc ON public.module_jj_transfers USING btree (fcoc);


--
-- Name: index_module_jj_transfers_on_normalized_fcoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jj_transfers_on_normalized_fcoc ON public.module_jj_transfers USING btree (lower(btrim(fcoc)));


--
-- Name: index_module_jj_transfers_on_normalized_sidebar_menu; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jj_transfers_on_normalized_sidebar_menu ON public.module_jj_transfers USING btree (lower(btrim(sidebar_menu)));


--
-- Name: index_module_jj_transfers_on_normalized_stakeholder_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jj_transfers_on_normalized_stakeholder_category ON public.module_jj_transfers USING btree (lower(btrim(stakeholder_category)));


--
-- Name: index_module_jj_transfers_on_normalized_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jj_transfers_on_normalized_user_name ON public.module_jj_transfers USING btree (lower(btrim(user_name)));


--
-- Name: index_module_jj_transfers_on_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_jj_transfers_on_user_name ON public.module_jj_transfers USING btree (user_name);


--
-- Name: index_module_lg_directory_import_status_0543ee43_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_lg_directory_import_status_0543ee43_on_created_at ON public.module_lg_directory_import_status_0543ee43 USING btree (created_at);


--
-- Name: index_module_lg_directory_import_status_0543ee43_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_lg_directory_import_status_0543ee43_on_updated_at ON public.module_lg_directory_import_status_0543ee43 USING btree (updated_at);


--
-- Name: index_module_main_activities_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_main_activities_on_active ON public.module_main_activities USING btree (active);


--
-- Name: index_module_main_activities_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_main_activities_on_created_at ON public.module_main_activities USING btree (created_at);


--
-- Name: index_module_main_activities_on_main_activity_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_main_activities_on_main_activity_name ON public.module_main_activities USING btree (main_activity_name);


--
-- Name: index_module_main_activities_on_normalized_main_activity_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_main_activities_on_normalized_main_activity_name ON public.module_main_activities USING btree (lower(btrim(main_activity_name)));


--
-- Name: index_module_monthly_bill_summary_816eb1f0_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_monthly_bill_summary_816eb1f0_on_created_at ON public.module_monthly_bill_summary_816eb1f0 USING btree (created_at);


--
-- Name: index_module_monthly_bill_summary_816eb1f0_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_monthly_bill_summary_816eb1f0_on_updated_at ON public.module_monthly_bill_summary_816eb1f0 USING btree (updated_at);


--
-- Name: index_module_months_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_months_on_active ON public.module_months USING btree (active);


--
-- Name: index_module_months_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_months_on_created_at ON public.module_months USING btree (created_at);


--
-- Name: index_module_months_on_financial_year_and_month_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_months_on_financial_year_and_month_name ON public.module_months USING btree (financial_year, month_name);


--
-- Name: index_module_months_on_normalized_financial_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_months_on_normalized_financial_year ON public.module_months USING btree (lower(btrim(financial_year)));


--
-- Name: index_module_months_on_normalized_month_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_months_on_normalized_month_name ON public.module_months USING btree (lower(btrim(month_name)));


--
-- Name: index_module_new_user_6724757d_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_new_user_6724757d_on_created_at ON public.module_new_user_6724757d USING btree (created_at);


--
-- Name: index_module_new_user_6724757d_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_new_user_6724757d_on_updated_at ON public.module_new_user_6724757d USING btree (updated_at);


--
-- Name: index_module_office_categories_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_categories_on_active ON public.module_office_categories USING btree (active);


--
-- Name: index_module_office_categories_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_categories_on_created_at ON public.module_office_categories USING btree (created_at);


--
-- Name: index_module_office_categories_on_normalized_office_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_categories_on_normalized_office_level ON public.module_office_categories USING btree (lower(btrim(office_level)));


--
-- Name: index_module_office_categories_on_normalized_office_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_categories_on_normalized_office_name ON public.module_office_categories USING btree (lower(btrim(office_name)));


--
-- Name: index_module_office_categories_on_normalized_parent_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_categories_on_normalized_parent_category ON public.module_office_categories USING btree (lower(btrim(parent_category)));


--
-- Name: index_module_office_categories_on_normalized_stakeholder_catego; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_categories_on_normalized_stakeholder_catego ON public.module_office_categories USING btree (lower(btrim(stakeholder_category)));


--
-- Name: index_module_office_categories_on_office_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_categories_on_office_name ON public.module_office_categories USING btree (office_name);


--
-- Name: index_module_office_categories_on_parent_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_categories_on_parent_category ON public.module_office_categories USING btree (parent_category);


--
-- Name: index_module_office_list_286e3232_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_list_286e3232_on_created_at ON public.module_office_list_286e3232 USING btree (created_at);


--
-- Name: index_module_office_list_286e3232_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_office_list_286e3232_on_updated_at ON public.module_office_list_286e3232 USING btree (updated_at);


--
-- Name: index_module_other_farmer_targets_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_farmer_targets_on_active ON public.module_other_farmer_targets USING btree (active);


--
-- Name: index_module_other_farmer_targets_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_farmer_targets_on_created_at ON public.module_other_farmer_targets USING btree (created_at);


--
-- Name: index_module_other_farmer_targets_on_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_farmer_targets_on_month ON public.module_other_farmer_targets USING btree (month);


--
-- Name: index_module_other_farmer_targets_on_normalized_fcoc_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_farmer_targets_on_normalized_fcoc_name ON public.module_other_farmer_targets USING btree (lower(btrim(fcoc_name)));


--
-- Name: index_module_other_farmer_targets_on_normalized_jeevika_jankar_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_farmer_targets_on_normalized_jeevika_jankar_ ON public.module_other_farmer_targets USING btree (lower(btrim(jeevika_jankar_id)));


--
-- Name: index_module_other_farmer_targets_on_normalized_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_farmer_targets_on_normalized_month ON public.module_other_farmer_targets USING btree (lower(btrim(month)));


--
-- Name: index_module_other_farmer_targets_on_normalized_target_mapping_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_farmer_targets_on_normalized_target_mapping_ ON public.module_other_farmer_targets USING btree (lower(btrim(target_mapping_id)));


--
-- Name: index_module_other_farmer_targets_on_payload_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_farmer_targets_on_payload_month ON public.module_other_farmer_targets USING btree (lower(btrim((data ->> 'month'::text))));


--
-- Name: index_module_other_farmer_targets_on_target_mapping_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_farmer_targets_on_target_mapping_id ON public.module_other_farmer_targets USING btree (target_mapping_id);


--
-- Name: index_module_other_target_list_410d4f4c_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_target_list_410d4f4c_on_created_at ON public.module_other_target_list_410d4f4c USING btree (created_at);


--
-- Name: index_module_other_target_list_410d4f4c_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_target_list_410d4f4c_on_updated_at ON public.module_other_target_list_410d4f4c USING btree (updated_at);


--
-- Name: index_module_other_targets_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_active ON public.module_other_targets USING btree (active);


--
-- Name: index_module_other_targets_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_created_at ON public.module_other_targets USING btree (created_at);


--
-- Name: index_module_other_targets_on_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_month ON public.module_other_targets USING btree (month);


--
-- Name: index_module_other_targets_on_normalized_fcoc_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_normalized_fcoc_name ON public.module_other_targets USING btree (lower(btrim(fcoc_name)));


--
-- Name: index_module_other_targets_on_normalized_ics_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_normalized_ics_name ON public.module_other_targets USING btree (lower(btrim(ics_name)));


--
-- Name: index_module_other_targets_on_normalized_jeevika_jankar_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_normalized_jeevika_jankar_id ON public.module_other_targets USING btree (lower(btrim(jeevika_jankar_id)));


--
-- Name: index_module_other_targets_on_normalized_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_normalized_month ON public.module_other_targets USING btree (lower(btrim(month)));


--
-- Name: index_module_other_targets_on_normalized_target_mapping_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_normalized_target_mapping_id ON public.module_other_targets USING btree (lower(btrim(target_mapping_id)));


--
-- Name: index_module_other_targets_on_payload_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_payload_month ON public.module_other_targets USING btree (lower(btrim((data ->> 'month'::text))));


--
-- Name: index_module_other_targets_on_target_mapping_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_other_targets_on_target_mapping_id ON public.module_other_targets USING btree (target_mapping_id);


--
-- Name: index_module_papl360_target_e2ff67fc_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_papl360_target_e2ff67fc_on_created_at ON public.module_papl360_target_e2ff67fc USING btree (created_at);


--
-- Name: index_module_papl360_target_e2ff67fc_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_papl360_target_e2ff67fc_on_updated_at ON public.module_papl360_target_e2ff67fc USING btree (updated_at);


--
-- Name: index_module_papl360_target_list_08d81bec_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_papl360_target_list_08d81bec_on_created_at ON public.module_papl360_target_list_08d81bec USING btree (created_at);


--
-- Name: index_module_papl360_target_list_08d81bec_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_papl360_target_list_08d81bec_on_updated_at ON public.module_papl360_target_list_08d81bec USING btree (updated_at);


--
-- Name: index_module_parent_offices_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_parent_offices_on_active ON public.module_parent_offices USING btree (active);


--
-- Name: index_module_parent_offices_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_parent_offices_on_created_at ON public.module_parent_offices USING btree (created_at);


--
-- Name: index_module_parent_offices_on_normalized_office_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_parent_offices_on_normalized_office_level ON public.module_parent_offices USING btree (lower(btrim(office_level)));


--
-- Name: index_module_parent_offices_on_normalized_parent_office; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_parent_offices_on_normalized_parent_office ON public.module_parent_offices USING btree (lower(btrim(parent_office)));


--
-- Name: index_module_parent_offices_on_normalized_parent_office_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_parent_offices_on_normalized_parent_office_name ON public.module_parent_offices USING btree (lower(btrim(parent_office_name)));


--
-- Name: index_module_parent_offices_on_normalized_parent_office_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_parent_offices_on_normalized_parent_office_type ON public.module_parent_offices USING btree (lower(btrim(parent_office_type)));


--
-- Name: index_module_parent_offices_on_normalized_stakeholder_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_parent_offices_on_normalized_stakeholder_category ON public.module_parent_offices USING btree (lower(btrim(stakeholder_category)));


--
-- Name: index_module_parent_offices_on_parent_office_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_parent_offices_on_parent_office_name ON public.module_parent_offices USING btree (parent_office_name);


--
-- Name: index_module_payment_details_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_payment_details_on_active ON public.module_payment_details USING btree (active);


--
-- Name: index_module_payment_details_on_bill_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_payment_details_on_bill_month ON public.module_payment_details USING btree (bill_month);


--
-- Name: index_module_payment_details_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_payment_details_on_created_at ON public.module_payment_details USING btree (created_at);


--
-- Name: index_module_payment_details_on_normalized_bill_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_payment_details_on_normalized_bill_month ON public.module_payment_details USING btree (lower(btrim(bill_month)));


--
-- Name: index_module_payment_details_on_normalized_bill_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_payment_details_on_normalized_bill_status ON public.module_payment_details USING btree (lower(btrim(bill_status)));


--
-- Name: index_module_payment_details_on_normalized_select_vrp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_payment_details_on_normalized_select_vrp ON public.module_payment_details USING btree (lower(btrim(select_vrp)));


--
-- Name: index_module_payment_status_report_17d409eb_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_payment_status_report_17d409eb_on_created_at ON public.module_payment_status_report_17d409eb USING btree (created_at);


--
-- Name: index_module_payment_status_report_17d409eb_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_payment_status_report_17d409eb_on_updated_at ON public.module_payment_status_report_17d409eb USING btree (updated_at);


--
-- Name: index_module_person_types_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_person_types_on_created_at ON public.module_person_types USING btree (created_at);


--
-- Name: index_module_person_types_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_person_types_on_updated_at ON public.module_person_types USING btree (updated_at);


--
-- Name: index_module_position_type_486dc9a9_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_position_type_486dc9a9_on_created_at ON public.module_position_type_486dc9a9 USING btree (created_at);


--
-- Name: index_module_position_type_486dc9a9_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_position_type_486dc9a9_on_updated_at ON public.module_position_type_486dc9a9 USING btree (updated_at);


--
-- Name: index_module_projects_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_projects_on_active ON public.module_projects USING btree (active);


--
-- Name: index_module_projects_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_projects_on_created_at ON public.module_projects USING btree (created_at);


--
-- Name: index_module_projects_on_normalized_project_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_projects_on_normalized_project_name ON public.module_projects USING btree (lower(btrim(project_name)));


--
-- Name: index_module_projects_on_project_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_projects_on_project_name ON public.module_projects USING btree (project_name);


--
-- Name: index_module_records_active_slug_month_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_active_slug_month_created_at ON public.module_records USING btree (module_slug, lower(btrim(((data)::jsonb ->> 'month'::text))), created_at DESC) WHERE ((COALESCE(lower(btrim(((data)::jsonb ->> 'deleted'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND (COALESCE(lower(btrim(((data)::jsonb ->> 'is_deleted'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND (COALESCE(lower(btrim(((data)::jsonb ->> 'discarded'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND ((COALESCE(btrim(((data)::jsonb ->> 'status'::text)), ''::text) = ''::text) OR (lower(btrim(((data)::jsonb ->> 'status'::text))) = 'active'::text)));


--
-- Name: index_module_records_new_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_new_users_on_lower_email ON public.module_records USING btree (lower(((data)::jsonb ->> 'email'::text))) WHERE ((module_slug)::text = 'new-user'::text);


--
-- Name: index_module_records_new_users_on_lower_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_new_users_on_lower_user_name ON public.module_records USING btree (lower(((data)::jsonb ->> 'user_name'::text))) WHERE ((module_slug)::text = 'new-user'::text);


--
-- Name: index_module_records_new_users_on_mobile_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_new_users_on_mobile_no ON public.module_records USING btree ((((data)::jsonb ->> 'mobile_no'::text))) WHERE ((module_slug)::text = 'new-user'::text);


--
-- Name: index_module_records_new_users_on_user_name_and_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_new_users_on_user_name_and_updated_at ON public.module_records USING btree ((((data)::jsonb ->> 'user_name'::text)), updated_at DESC) WHERE ((module_slug)::text = 'new-user'::text);


--
-- Name: index_module_records_on_active_catalogue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_on_active_catalogue ON public.module_records USING btree (module_slug, created_at DESC) WHERE ((COALESCE(lower(btrim(((data)::jsonb ->> 'deleted'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND (COALESCE(lower(btrim(((data)::jsonb ->> 'is_deleted'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND (COALESCE(lower(btrim(((data)::jsonb ->> 'discarded'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND ((COALESCE(btrim(((data)::jsonb ->> 'status'::text)), ''::text) = ''::text) OR (lower(btrim(((data)::jsonb ->> 'status'::text))) = 'active'::text)));


--
-- Name: index_module_records_on_json_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_on_json_data ON public.module_records USING gin (((data)::jsonb));


--
-- Name: index_module_records_on_module_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_on_module_slug ON public.module_records USING btree (module_slug);


--
-- Name: index_module_records_on_slug_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_on_slug_and_created_at ON public.module_records USING btree (module_slug, created_at DESC);


--
-- Name: index_module_records_on_slug_and_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_on_slug_and_updated_at ON public.module_records USING btree (module_slug, updated_at DESC);


--
-- Name: index_module_records_on_slug_normalized_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_on_slug_normalized_month ON public.module_records USING btree (module_slug, lower(btrim(((data)::jsonb ->> 'month'::text))));


--
-- Name: index_module_records_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_on_updated_at ON public.module_records USING btree (updated_at DESC);


--
-- Name: index_module_records_village_code_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_village_code_lookup ON public.module_records USING btree ((((data)::jsonb ->> 'village_code'::text))) WHERE ((module_slug)::text = ANY ((ARRAY['village-master'::character varying, 'lg-directory-list'::character varying])::text[]));


--
-- Name: index_module_records_village_id_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_records_village_id_lookup ON public.module_records USING btree ((((data)::jsonb ->> 'village_id'::text))) WHERE ((module_slug)::text = ANY ((ARRAY['village-master'::character varying, 'lg-directory-list'::character varying])::text[]));


--
-- Name: index_module_role_managements_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_role_managements_on_created_at ON public.module_role_managements USING btree (created_at);


--
-- Name: index_module_role_managements_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_role_managements_on_updated_at ON public.module_role_managements USING btree (updated_at);


--
-- Name: index_module_roles_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_roles_on_active ON public.module_roles USING btree (active);


--
-- Name: index_module_roles_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_roles_on_created_at ON public.module_roles USING btree (created_at);


--
-- Name: index_module_roles_on_normalized_role_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_roles_on_normalized_role_name ON public.module_roles USING btree (lower(btrim(role_name)));


--
-- Name: index_module_roles_on_normalized_stakeholder_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_roles_on_normalized_stakeholder_category ON public.module_roles USING btree (lower(btrim(stakeholder_category)));


--
-- Name: index_module_roles_on_normalized_stakeholder_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_roles_on_normalized_stakeholder_role ON public.module_roles USING btree (lower(btrim(stakeholder_role)));


--
-- Name: index_module_roles_on_role_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_roles_on_role_name ON public.module_roles USING btree (role_name);


--
-- Name: index_module_seed_distribution_targets_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_seed_distribution_targets_on_created_at ON public.module_seed_distribution_targets USING btree (created_at);


--
-- Name: index_module_seed_distribution_targets_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_seed_distribution_targets_on_updated_at ON public.module_seed_distribution_targets USING btree (updated_at);


--
-- Name: index_module_stakeholder_profile_603e5d20_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholder_profile_603e5d20_on_created_at ON public.module_stakeholder_profile_603e5d20 USING btree (created_at);


--
-- Name: index_module_stakeholder_profile_603e5d20_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholder_profile_603e5d20_on_updated_at ON public.module_stakeholder_profile_603e5d20 USING btree (updated_at);


--
-- Name: index_module_stakeholder_roles_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholder_roles_on_active ON public.module_stakeholder_roles USING btree (active);


--
-- Name: index_module_stakeholder_roles_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholder_roles_on_created_at ON public.module_stakeholder_roles USING btree (created_at);


--
-- Name: index_module_stakeholder_roles_on_normalized_stakeholder_catego; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholder_roles_on_normalized_stakeholder_catego ON public.module_stakeholder_roles USING btree (lower(btrim(stakeholder_category)));


--
-- Name: index_module_stakeholder_roles_on_normalized_stakeholder_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholder_roles_on_normalized_stakeholder_role ON public.module_stakeholder_roles USING btree (lower(btrim(stakeholder_role)));


--
-- Name: index_module_stakeholders_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholders_on_active ON public.module_stakeholders USING btree (active);


--
-- Name: index_module_stakeholders_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholders_on_created_at ON public.module_stakeholders USING btree (created_at);


--
-- Name: index_module_stakeholders_on_normalized_logo_upload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholders_on_normalized_logo_upload ON public.module_stakeholders USING btree (lower(btrim(logo_upload)));


--
-- Name: index_module_stakeholders_on_normalized_stakeholder_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholders_on_normalized_stakeholder_name ON public.module_stakeholders USING btree (lower(btrim(stakeholder_name)));


--
-- Name: index_module_stakeholders_on_normalized_stakeholder_name_hindi; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholders_on_normalized_stakeholder_name_hindi ON public.module_stakeholders USING btree (lower(btrim(stakeholder_name_hindi)));


--
-- Name: index_module_stakeholders_on_stakeholder_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_stakeholders_on_stakeholder_name ON public.module_stakeholders USING btree (stakeholder_name);


--
-- Name: index_module_sub_activities_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_activities_on_active ON public.module_sub_activities USING btree (active);


--
-- Name: index_module_sub_activities_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_activities_on_created_at ON public.module_sub_activities USING btree (created_at);


--
-- Name: index_module_sub_activities_on_normalized_main_activity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_activities_on_normalized_main_activity ON public.module_sub_activities USING btree (lower(btrim(main_activity)));


--
-- Name: index_module_sub_activities_on_normalized_sub_activity_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_activities_on_normalized_sub_activity_name ON public.module_sub_activities USING btree (lower(btrim(sub_activity_name)));


--
-- Name: index_module_sub_activities_on_normalized_unit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_activities_on_normalized_unit ON public.module_sub_activities USING btree (lower(btrim(unit)));


--
-- Name: index_module_sub_offices_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_offices_on_active ON public.module_sub_offices USING btree (active);


--
-- Name: index_module_sub_offices_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_offices_on_created_at ON public.module_sub_offices USING btree (created_at);


--
-- Name: index_module_sub_offices_on_normalized_office_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_offices_on_normalized_office_level ON public.module_sub_offices USING btree (lower(btrim(office_level)));


--
-- Name: index_module_sub_offices_on_normalized_office_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_offices_on_normalized_office_name ON public.module_sub_offices USING btree (lower(btrim(office_name)));


--
-- Name: index_module_sub_offices_on_normalized_parent_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_offices_on_normalized_parent_category ON public.module_sub_offices USING btree (lower(btrim(parent_category)));


--
-- Name: index_module_sub_offices_on_normalized_stakeholder_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_offices_on_normalized_stakeholder_category ON public.module_sub_offices USING btree (lower(btrim(stakeholder_category)));


--
-- Name: index_module_sub_offices_on_normalized_sub_office_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_offices_on_normalized_sub_office_name ON public.module_sub_offices USING btree (lower(btrim(sub_office_name)));


--
-- Name: index_module_sub_offices_on_office_name_and_sub_office_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_offices_on_office_name_and_sub_office_name ON public.module_sub_offices USING btree (office_name, sub_office_name);


--
-- Name: index_module_sub_offices_on_parent_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_sub_offices_on_parent_category ON public.module_sub_offices USING btree (parent_category);


--
-- Name: index_module_task_completion_indicator_2dc4f3fb_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_task_completion_indicator_2dc4f3fb_on_created_at ON public.module_task_completion_indicator_2dc4f3fb USING btree (created_at);


--
-- Name: index_module_task_completion_indicator_2dc4f3fb_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_task_completion_indicator_2dc4f3fb_on_updated_at ON public.module_task_completion_indicator_2dc4f3fb USING btree (updated_at);


--
-- Name: index_module_task_indicator_master_c07b884a_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_task_indicator_master_c07b884a_on_created_at ON public.module_task_indicator_master_c07b884a USING btree (created_at);


--
-- Name: index_module_task_indicator_master_c07b884a_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_task_indicator_master_c07b884a_on_updated_at ON public.module_task_indicator_master_c07b884a USING btree (updated_at);


--
-- Name: index_module_training_edit_requests_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_training_edit_requests_on_created_at ON public.module_training_edit_requests USING btree (created_at);


--
-- Name: index_module_training_edit_requests_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_training_edit_requests_on_updated_at ON public.module_training_edit_requests USING btree (updated_at);


--
-- Name: index_module_training_form_list_88933913_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_training_form_list_88933913_on_created_at ON public.module_training_form_list_88933913 USING btree (created_at);


--
-- Name: index_module_training_form_list_88933913_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_training_form_list_88933913_on_updated_at ON public.module_training_form_list_88933913 USING btree (updated_at);


--
-- Name: index_module_training_topic_mappings_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_training_topic_mappings_on_created_at ON public.module_training_topic_mappings USING btree (created_at);


--
-- Name: index_module_training_topic_mappings_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_training_topic_mappings_on_updated_at ON public.module_training_topic_mappings USING btree (updated_at);


--
-- Name: index_module_trainings_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_active ON public.module_trainings USING btree (active);


--
-- Name: index_module_trainings_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_created_at ON public.module_trainings USING btree (created_at);


--
-- Name: index_module_trainings_on_jeevika_jankar_id_and_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_jeevika_jankar_id_and_month ON public.module_trainings USING btree (jeevika_jankar_id, month);


--
-- Name: index_module_trainings_on_main_activity_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_main_activity_type ON public.module_trainings USING btree (main_activity_type);


--
-- Name: index_module_trainings_on_month_and_training_method; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_month_and_training_method ON public.module_trainings USING btree (month, training_method);


--
-- Name: index_module_trainings_on_normalized_cluster_coordinator_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_normalized_cluster_coordinator_name ON public.module_trainings USING btree (lower(btrim(cluster_coordinator_name)));


--
-- Name: index_module_trainings_on_normalized_jeevika_jankar_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_normalized_jeevika_jankar_id ON public.module_trainings USING btree (lower(btrim(jeevika_jankar_id)));


--
-- Name: index_module_trainings_on_normalized_main_activity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_normalized_main_activity ON public.module_trainings USING btree (lower(btrim(main_activity)));


--
-- Name: index_module_trainings_on_normalized_main_activity_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_normalized_main_activity_type ON public.module_trainings USING btree (lower(btrim(main_activity_type)));


--
-- Name: index_module_trainings_on_normalized_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_normalized_month ON public.module_trainings USING btree (lower(btrim(month)));


--
-- Name: index_module_trainings_on_normalized_sub_activity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_normalized_sub_activity ON public.module_trainings USING btree (lower(btrim(sub_activity)));


--
-- Name: index_module_trainings_on_normalized_training_method; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_normalized_training_method ON public.module_trainings USING btree (lower(btrim(training_method)));


--
-- Name: index_module_trainings_on_payload_month_and_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_trainings_on_payload_month_and_created ON public.module_trainings USING btree (lower(btrim((data ->> 'month'::text))), created_at DESC);


--
-- Name: index_module_user_hierarchies_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_hierarchies_on_active ON public.module_user_hierarchies USING btree (active);


--
-- Name: index_module_user_hierarchies_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_hierarchies_on_created_at ON public.module_user_hierarchies USING btree (created_at);


--
-- Name: index_module_user_hierarchies_on_level_1_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_hierarchies_on_level_1_user ON public.module_user_hierarchies USING btree (level_1_user);


--
-- Name: index_module_user_hierarchies_on_normalized_level_1_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_hierarchies_on_normalized_level_1_user ON public.module_user_hierarchies USING btree (lower(btrim(level_1_user)));


--
-- Name: index_module_user_hierarchies_on_normalized_level_2_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_hierarchies_on_normalized_level_2_user ON public.module_user_hierarchies USING btree (lower(btrim(level_2_user)));


--
-- Name: index_module_user_hierarchies_on_normalized_level_3_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_hierarchies_on_normalized_level_3_user ON public.module_user_hierarchies USING btree (lower(btrim(level_3_user)));


--
-- Name: index_module_user_hierarchy_list_a4542a91_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_hierarchy_list_a4542a91_on_created_at ON public.module_user_hierarchy_list_a4542a91 USING btree (created_at);


--
-- Name: index_module_user_hierarchy_list_a4542a91_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_hierarchy_list_a4542a91_on_updated_at ON public.module_user_hierarchy_list_a4542a91 USING btree (updated_at);


--
-- Name: index_module_user_management_roles_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_management_roles_on_created_at ON public.module_user_management_roles USING btree (created_at);


--
-- Name: index_module_user_management_roles_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_user_management_roles_on_updated_at ON public.module_user_management_roles USING btree (updated_at);


--
-- Name: index_module_vrp_active_status_history_5a746fcf_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_active_status_history_5a746fcf_on_created_at ON public.module_vrp_active_status_history_5a746fcf USING btree (created_at);


--
-- Name: index_module_vrp_active_status_history_5a746fcf_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_active_status_history_5a746fcf_on_updated_at ON public.module_vrp_active_status_history_5a746fcf USING btree (updated_at);


--
-- Name: index_module_vrp_activity_list_7d178b72_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_activity_list_7d178b72_on_created_at ON public.module_vrp_activity_list_7d178b72 USING btree (created_at);


--
-- Name: index_module_vrp_activity_list_7d178b72_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_activity_list_7d178b72_on_updated_at ON public.module_vrp_activity_list_7d178b72 USING btree (updated_at);


--
-- Name: index_module_vrp_approval_histories_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_approval_histories_on_created_at ON public.module_vrp_approval_histories USING btree (created_at);


--
-- Name: index_module_vrp_approval_histories_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_approval_histories_on_updated_at ON public.module_vrp_approval_histories USING btree (updated_at);


--
-- Name: index_module_vrp_bill_add_50a221ea_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_bill_add_50a221ea_on_created_at ON public.module_vrp_bill_add_50a221ea USING btree (created_at);


--
-- Name: index_module_vrp_bill_add_50a221ea_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_bill_add_50a221ea_on_updated_at ON public.module_vrp_bill_add_50a221ea USING btree (updated_at);


--
-- Name: index_module_vrp_bill_list_0ef6fdc4_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_bill_list_0ef6fdc4_on_created_at ON public.module_vrp_bill_list_0ef6fdc4 USING btree (created_at);


--
-- Name: index_module_vrp_bill_list_0ef6fdc4_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_bill_list_0ef6fdc4_on_updated_at ON public.module_vrp_bill_list_0ef6fdc4 USING btree (updated_at);


--
-- Name: index_module_vrp_registration_list_6a8aeba6_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_registration_list_6a8aeba6_on_created_at ON public.module_vrp_registration_list_6a8aeba6 USING btree (created_at);


--
-- Name: index_module_vrp_registration_list_6a8aeba6_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_registration_list_6a8aeba6_on_updated_at ON public.module_vrp_registration_list_6a8aeba6 USING btree (updated_at);


--
-- Name: index_module_vrp_types_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_types_on_active ON public.module_vrp_types USING btree (active);


--
-- Name: index_module_vrp_types_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_types_on_created_at ON public.module_vrp_types USING btree (created_at);


--
-- Name: index_module_vrp_types_on_normalized_vrp_type_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_vrp_types_on_normalized_vrp_type_name ON public.module_vrp_types USING btree (lower(btrim(vrp_type_name)));


--
-- Name: index_module_weekly_activity_progress_22c35d60_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_weekly_activity_progress_22c35d60_on_created_at ON public.module_weekly_activity_progress_22c35d60 USING btree (created_at);


--
-- Name: index_module_weekly_activity_progress_22c35d60_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_weekly_activity_progress_22c35d60_on_updated_at ON public.module_weekly_activity_progress_22c35d60 USING btree (updated_at);


--
-- Name: index_module_weekly_progress_report_1157600e_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_weekly_progress_report_1157600e_on_created_at ON public.module_weekly_progress_report_1157600e USING btree (created_at);


--
-- Name: index_module_weekly_progress_report_1157600e_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_weekly_progress_report_1157600e_on_updated_at ON public.module_weekly_progress_report_1157600e USING btree (updated_at);


--
-- Name: index_module_weekly_target_add_ef9d741d_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_weekly_target_add_ef9d741d_on_created_at ON public.module_weekly_target_add_ef9d741d USING btree (created_at);


--
-- Name: index_module_weekly_target_add_ef9d741d_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_weekly_target_add_ef9d741d_on_updated_at ON public.module_weekly_target_add_ef9d741d USING btree (updated_at);


--
-- Name: index_module_weekly_target_list_91c4fe5d_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_weekly_target_list_91c4fe5d_on_created_at ON public.module_weekly_target_list_91c4fe5d USING btree (created_at);


--
-- Name: index_module_weekly_target_list_91c4fe5d_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_module_weekly_target_list_91c4fe5d_on_updated_at ON public.module_weekly_target_list_91c4fe5d USING btree (updated_at);


--
-- Name: index_target_mappings_on_activity_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_activity_scope ON public.target_mappings USING btree (fco_id, ics_id, village_id, main_activity_name, activity_name);


--
-- Name: index_target_mappings_on_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_creator ON public.target_mappings USING btree (created_by_type, created_by_id);


--
-- Name: index_target_mappings_on_creator_and_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_creator_and_updated_at ON public.target_mappings USING btree (created_by_type, created_by_id, updated_at DESC);


--
-- Name: index_target_mappings_on_entry_mode_and_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_entry_mode_and_month ON public.target_mappings USING btree (target_entry_mode, month_name);


--
-- Name: index_target_mappings_on_normalized_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_normalized_month ON public.target_mappings USING btree (lower(btrim((month_name)::text)));


--
-- Name: index_target_mappings_on_owner_normalized_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_owner_normalized_month ON public.target_mappings USING btree (vrp_id, lower(btrim((month_name)::text)));


--
-- Name: index_target_mappings_on_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_scope ON public.target_mappings USING btree (vrp_id, vrp_ics_mapping_id, month_name, activity_name);


--
-- Name: index_target_mappings_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_updated_at ON public.target_mappings USING btree (updated_at DESC);


--
-- Name: index_target_mappings_on_village_id_for_agreements; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_village_id_for_agreements ON public.target_mappings USING btree (village_id);


--
-- Name: index_target_mappings_on_vrp_and_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_vrp_and_updated_at ON public.target_mappings USING btree (vrp_id, updated_at DESC);


--
-- Name: index_target_mappings_on_vrp_ics_mapping_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_vrp_ics_mapping_id ON public.target_mappings USING btree (vrp_ics_mapping_id);


--
-- Name: index_target_mappings_on_vrp_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_target_mappings_on_vrp_id ON public.target_mappings USING btree (vrp_id);


--
-- Name: index_training_edits_on_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_training_edits_on_record_id ON public.module_records USING btree ((((data)::jsonb ->> 'record_id'::text))) WHERE ((module_slug)::text = 'training-form-edit-request'::text);


--
-- Name: index_training_edits_on_record_id_and_latest_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_training_edits_on_record_id_and_latest_id ON public.module_records USING btree ((((data)::jsonb ->> 'record_id'::text)), id DESC) WHERE ((module_slug)::text = 'training-form-edit-request'::text);


--
-- Name: index_training_edits_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_training_edits_on_status ON public.module_records USING btree ((((data)::jsonb ->> 'status'::text))) WHERE ((module_slug)::text = 'training-form-edit-request'::text);


--
-- Name: index_training_edits_on_status_and_latest_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_training_edits_on_status_and_latest_id ON public.module_records USING btree ((((data)::jsonb ->> 'status'::text)), id DESC) WHERE ((module_slug)::text = 'training-form-edit-request'::text);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_lower_email ON public.users USING btree (lower((email)::text));


--
-- Name: index_users_on_lower_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_lower_user_name ON public.users USING btree (lower((user_name)::text));


--
-- Name: index_users_on_mobile_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_mobile_no ON public.users USING btree (mobile_no);


--
-- Name: index_users_on_updated_at_desc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_updated_at_desc ON public.users USING btree (updated_at DESC);


--
-- Name: index_users_on_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_user_name ON public.users USING btree (user_name);


--
-- Name: index_vrp_ics_mappings_on_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrp_ics_mappings_on_creator ON public.vrp_ics_mappings USING btree (created_by_type, created_by_id);


--
-- Name: index_vrp_ics_mappings_on_mapping_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_vrp_ics_mappings_on_mapping_scope ON public.vrp_ics_mappings USING btree (vrp_id, fco_id, ics_id, village_id);


--
-- Name: index_vrp_ics_mappings_on_village_id_for_agreements; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrp_ics_mappings_on_village_id_for_agreements ON public.vrp_ics_mappings USING btree (village_id);


--
-- Name: index_vrp_ics_mappings_on_vrp_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrp_ics_mappings_on_vrp_id ON public.vrp_ics_mappings USING btree (vrp_id);


--
-- Name: index_vrp_profiles_on_vrp_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrp_profiles_on_vrp_id ON public.vrp_profiles USING btree (vrp_id);


--
-- Name: index_vrps_on_aadhar_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_aadhar_no ON public.vrps USING btree (aadhar_no);


--
-- Name: index_vrps_on_agreement_accepted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_agreement_accepted_at ON public.vrps USING btree (agreement_accepted_at);


--
-- Name: index_vrps_on_cluster_incharge; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_cluster_incharge ON public.vrps USING btree (cluster_incharge);


--
-- Name: index_vrps_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_created_by_id ON public.vrps USING btree (created_by_id);


--
-- Name: index_vrps_on_created_by_type_and_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_created_by_type_and_created_by_id ON public.vrps USING btree (created_by_type, created_by_id);


--
-- Name: index_vrps_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_email ON public.vrps USING btree (email);


--
-- Name: index_vrps_on_fcoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_fcoc ON public.vrps USING btree (fcoc);


--
-- Name: index_vrps_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_lower_email ON public.vrps USING btree (lower((email)::text));


--
-- Name: index_vrps_on_lower_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_lower_user_name ON public.vrps USING btree (lower((user_name)::text));


--
-- Name: index_vrps_on_mobile_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_mobile_no ON public.vrps USING btree (mobile_no);


--
-- Name: index_vrps_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_status ON public.vrps USING btree (status);


--
-- Name: index_vrps_on_to_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_to_name ON public.vrps USING btree (to_name);


--
-- Name: index_vrps_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_updated_at ON public.vrps USING btree (updated_at DESC);


--
-- Name: index_vrps_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_user_id ON public.vrps USING btree (user_id);


--
-- Name: index_vrps_on_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_user_name ON public.vrps USING btree (user_name);


--
-- Name: index_vrps_on_vrp_bank_master_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vrps_on_vrp_bank_master_id ON public.vrps USING btree (vrp_bank_master_id);


--
-- Name: module_records jj_lg_directory_sync_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_lg_directory_sync_delete AFTER DELETE ON public.module_records FOR EACH ROW EXECUTE FUNCTION public.jj_lg_directory_sync();


--
-- Name: module_records jj_lg_directory_sync_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_lg_directory_sync_write AFTER INSERT OR UPDATE ON public.module_records FOR EACH ROW EXECUTE FUNCTION public.jj_lg_directory_sync();


--
-- Name: lg_blocks jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.lg_blocks REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: lg_districts jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.lg_districts REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: lg_gram_panchayats jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.lg_gram_panchayats REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: lg_states jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.lg_states REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: lg_villages jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.lg_villages REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_access_control_list_b9d538d4 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_access_control_list_b9d538d4 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_access_controls jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_access_controls REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_activity_group_list_34a52e96 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_activity_group_list_34a52e96 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_activity_master_2e19bce0 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_activity_master_2e19bce0 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_all_user_b8d83be4 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_all_user_b8d83be4 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_approval_list_27d1da1f jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_approval_list_27d1da1f REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_approval_status_summary_1483b5d5 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_approval_status_summary_1483b5d5 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_approvals jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_approvals REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_bank_master_9e57e6ab jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_bank_master_9e57e6ab REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_bill_approval_histories jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_bill_approval_histories REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_bills jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_bills REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_farmer_forms jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_farmer_forms REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_ics_master_483e7ffc jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_ics_master_483e7ffc REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_jeevika_jankar_bill_list_083c76c4 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_jeevika_jankar_bill_list_083c76c4 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_jeevika_jankar_completed_payment_l_bad7b61b jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_jeevika_jankar_completed_payment_l_bad7b61b REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_jeevika_jankar_observation_list_9bfb7dc5 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_jeevika_jankar_observation_list_9bfb7dc5 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_jeevika_jankar_payment_list_2e70d942 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_jeevika_jankar_payment_list_2e70d942 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_jeevika_jankar_payment_list_detail_d8114659 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_jeevika_jankar_payment_list_detail_d8114659 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_jeevika_jankar_transfer_list_73f1674d jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_jeevika_jankar_transfer_list_73f1674d REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_jj_transfers jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_jj_transfers REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_lg_directory_import_status_0543ee43 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_lg_directory_import_status_0543ee43 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_main_activities jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_main_activities REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_monthly_bill_summary_816eb1f0 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_monthly_bill_summary_816eb1f0 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_months jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_months REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_new_user_6724757d jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_new_user_6724757d REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_office_categories jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_office_categories REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_office_list_286e3232 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_office_list_286e3232 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_other_farmer_targets jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_other_farmer_targets REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_other_target_list_410d4f4c jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_other_target_list_410d4f4c REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_other_target_with_farmer_list_0d98bf9f jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_other_target_with_farmer_list_0d98bf9f REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_other_targets jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_other_targets REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_papl360_target_e2ff67fc jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_papl360_target_e2ff67fc REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_papl360_target_list_08d81bec jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_papl360_target_list_08d81bec REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_parent_offices jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_parent_offices REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_payment_details jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_payment_details REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_payment_status_report_17d409eb jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_payment_status_report_17d409eb REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_person_types jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_person_types REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_position_type_486dc9a9 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_position_type_486dc9a9 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_projects jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_projects REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_role_managements jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_role_managements REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_roles jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_roles REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_seed_distribution_target_list_5453661e jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_seed_distribution_target_list_5453661e REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_seed_distribution_targets jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_seed_distribution_targets REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_stakeholder_profile_603e5d20 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_stakeholder_profile_603e5d20 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_stakeholder_roles jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_stakeholder_roles REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_stakeholders jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_stakeholders REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_sub_activities jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_sub_activities REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_sub_offices jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_sub_offices REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_task_completion_indicator_2dc4f3fb jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_task_completion_indicator_2dc4f3fb REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_task_completion_indicator_list_fc8d2b85 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_task_completion_indicator_list_fc8d2b85 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_task_indicator_master_c07b884a jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_task_indicator_master_c07b884a REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_training_edit_requests jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_training_edit_requests REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_training_form_list_88933913 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_training_form_list_88933913 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_training_topic_mappings jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_training_topic_mappings REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_trainings jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_trainings REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_user_hierarchies jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_user_hierarchies REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_user_hierarchy_list_a4542a91 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_user_hierarchy_list_a4542a91 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_user_management_roles jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_user_management_roles REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_vrp_active_status_history_5a746fcf jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_vrp_active_status_history_5a746fcf REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_vrp_activity_list_7d178b72 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_vrp_activity_list_7d178b72 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_vrp_approval_histories jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_vrp_approval_histories REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_vrp_bill_add_50a221ea jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_vrp_bill_add_50a221ea REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_vrp_bill_list_0ef6fdc4 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_vrp_bill_list_0ef6fdc4 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_vrp_registration_list_6a8aeba6 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_vrp_registration_list_6a8aeba6 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_vrp_types jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_vrp_types REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_weekly_activity_progress_22c35d60 jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_weekly_activity_progress_22c35d60 REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_weekly_progress_report_1157600e jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_weekly_progress_report_1157600e REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_weekly_target_add_ef9d741d jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_weekly_target_add_ef9d741d REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: module_weekly_target_list_91c4fe5d jj_module_entries_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_delete AFTER DELETE ON public.module_weekly_target_list_91c4fe5d REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_delete();


--
-- Name: lg_blocks jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.lg_blocks REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: lg_districts jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.lg_districts REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: lg_gram_panchayats jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.lg_gram_panchayats REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: lg_states jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.lg_states REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: lg_villages jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.lg_villages REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_access_control_list_b9d538d4 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_access_control_list_b9d538d4 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_access_controls jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_access_controls REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_activity_group_list_34a52e96 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_activity_group_list_34a52e96 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_activity_master_2e19bce0 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_activity_master_2e19bce0 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_all_user_b8d83be4 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_all_user_b8d83be4 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_approval_list_27d1da1f jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_approval_list_27d1da1f REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_approval_status_summary_1483b5d5 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_approval_status_summary_1483b5d5 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_approvals jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_approvals REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_bank_master_9e57e6ab jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_bank_master_9e57e6ab REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_bill_approval_histories jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_bill_approval_histories REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_bills jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_bills REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_farmer_forms jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_farmer_forms REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_ics_master_483e7ffc jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_ics_master_483e7ffc REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_jeevika_jankar_bill_list_083c76c4 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_jeevika_jankar_bill_list_083c76c4 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_jeevika_jankar_completed_payment_l_bad7b61b jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_jeevika_jankar_completed_payment_l_bad7b61b REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_jeevika_jankar_observation_list_9bfb7dc5 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_jeevika_jankar_observation_list_9bfb7dc5 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_jeevika_jankar_payment_list_2e70d942 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_jeevika_jankar_payment_list_2e70d942 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_jeevika_jankar_payment_list_detail_d8114659 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_jeevika_jankar_payment_list_detail_d8114659 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_jeevika_jankar_transfer_list_73f1674d jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_jeevika_jankar_transfer_list_73f1674d REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_jj_transfers jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_jj_transfers REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_lg_directory_import_status_0543ee43 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_lg_directory_import_status_0543ee43 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_main_activities jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_main_activities REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_monthly_bill_summary_816eb1f0 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_monthly_bill_summary_816eb1f0 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_months jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_months REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_new_user_6724757d jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_new_user_6724757d REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_office_categories jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_office_categories REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_office_list_286e3232 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_office_list_286e3232 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_other_farmer_targets jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_other_farmer_targets REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_other_target_list_410d4f4c jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_other_target_list_410d4f4c REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_other_target_with_farmer_list_0d98bf9f jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_other_target_with_farmer_list_0d98bf9f REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_other_targets jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_other_targets REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_papl360_target_e2ff67fc jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_papl360_target_e2ff67fc REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_papl360_target_list_08d81bec jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_papl360_target_list_08d81bec REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_parent_offices jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_parent_offices REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_payment_details jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_payment_details REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_payment_status_report_17d409eb jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_payment_status_report_17d409eb REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_person_types jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_person_types REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_position_type_486dc9a9 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_position_type_486dc9a9 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_projects jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_projects REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_role_managements jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_role_managements REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_roles jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_roles REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_seed_distribution_target_list_5453661e jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_seed_distribution_target_list_5453661e REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_seed_distribution_targets jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_seed_distribution_targets REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_stakeholder_profile_603e5d20 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_stakeholder_profile_603e5d20 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_stakeholder_roles jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_stakeholder_roles REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_stakeholders jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_stakeholders REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_sub_activities jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_sub_activities REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_sub_offices jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_sub_offices REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_task_completion_indicator_2dc4f3fb jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_task_completion_indicator_2dc4f3fb REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_task_completion_indicator_list_fc8d2b85 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_task_completion_indicator_list_fc8d2b85 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_task_indicator_master_c07b884a jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_task_indicator_master_c07b884a REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_training_edit_requests jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_training_edit_requests REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_training_form_list_88933913 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_training_form_list_88933913 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_training_topic_mappings jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_training_topic_mappings REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_trainings jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_trainings REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_user_hierarchies jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_user_hierarchies REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_user_hierarchy_list_a4542a91 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_user_hierarchy_list_a4542a91 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_user_management_roles jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_user_management_roles REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_vrp_active_status_history_5a746fcf jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_vrp_active_status_history_5a746fcf REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_vrp_activity_list_7d178b72 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_vrp_activity_list_7d178b72 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_vrp_approval_histories jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_vrp_approval_histories REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_vrp_bill_add_50a221ea jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_vrp_bill_add_50a221ea REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_vrp_bill_list_0ef6fdc4 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_vrp_bill_list_0ef6fdc4 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_vrp_registration_list_6a8aeba6 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_vrp_registration_list_6a8aeba6 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_vrp_types jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_vrp_types REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_weekly_activity_progress_22c35d60 jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_weekly_activity_progress_22c35d60 REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_weekly_progress_report_1157600e jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_weekly_progress_report_1157600e REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_weekly_target_add_ef9d741d jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_weekly_target_add_ef9d741d REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: module_weekly_target_list_91c4fe5d jj_module_entries_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_insert AFTER INSERT ON public.module_weekly_target_list_91c4fe5d REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_insert();


--
-- Name: lg_blocks jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.lg_blocks FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: lg_districts jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.lg_districts FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: lg_gram_panchayats jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.lg_gram_panchayats FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: lg_states jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.lg_states FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: lg_villages jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.lg_villages FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_access_control_list_b9d538d4 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_access_control_list_b9d538d4 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_access_controls jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_access_controls FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_activity_group_list_34a52e96 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_activity_group_list_34a52e96 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_activity_master_2e19bce0 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_activity_master_2e19bce0 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_all_user_b8d83be4 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_all_user_b8d83be4 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_approval_list_27d1da1f jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_approval_list_27d1da1f FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_approval_status_summary_1483b5d5 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_approval_status_summary_1483b5d5 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_approvals jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_approvals FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_bank_master_9e57e6ab jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_bank_master_9e57e6ab FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_bill_approval_histories jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_bill_approval_histories FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_bills jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_bills FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_farmer_forms jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_farmer_forms FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_ics_master_483e7ffc jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_ics_master_483e7ffc FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_jeevika_jankar_bill_list_083c76c4 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_jeevika_jankar_bill_list_083c76c4 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_jeevika_jankar_completed_payment_l_bad7b61b jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_jeevika_jankar_completed_payment_l_bad7b61b FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_jeevika_jankar_observation_list_9bfb7dc5 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_jeevika_jankar_observation_list_9bfb7dc5 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_jeevika_jankar_payment_list_2e70d942 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_jeevika_jankar_payment_list_2e70d942 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_jeevika_jankar_payment_list_detail_d8114659 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_jeevika_jankar_payment_list_detail_d8114659 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_jeevika_jankar_transfer_list_73f1674d jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_jeevika_jankar_transfer_list_73f1674d FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_jj_transfers jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_jj_transfers FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_lg_directory_import_status_0543ee43 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_lg_directory_import_status_0543ee43 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_main_activities jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_main_activities FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_monthly_bill_summary_816eb1f0 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_monthly_bill_summary_816eb1f0 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_months jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_months FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_new_user_6724757d jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_new_user_6724757d FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_office_categories jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_office_categories FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_office_list_286e3232 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_office_list_286e3232 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_other_farmer_targets jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_other_farmer_targets FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_other_target_list_410d4f4c jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_other_target_list_410d4f4c FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_other_target_with_farmer_list_0d98bf9f jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_other_target_with_farmer_list_0d98bf9f FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_other_targets jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_other_targets FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_papl360_target_e2ff67fc jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_papl360_target_e2ff67fc FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_papl360_target_list_08d81bec jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_papl360_target_list_08d81bec FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_parent_offices jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_parent_offices FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_payment_details jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_payment_details FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_payment_status_report_17d409eb jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_payment_status_report_17d409eb FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_person_types jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_person_types FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_position_type_486dc9a9 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_position_type_486dc9a9 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_projects jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_projects FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_role_managements jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_role_managements FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_roles jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_roles FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_seed_distribution_target_list_5453661e jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_seed_distribution_target_list_5453661e FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_seed_distribution_targets jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_seed_distribution_targets FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_stakeholder_profile_603e5d20 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_stakeholder_profile_603e5d20 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_stakeholder_roles jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_stakeholder_roles FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_stakeholders jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_stakeholders FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_sub_activities jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_sub_activities FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_sub_offices jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_sub_offices FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_task_completion_indicator_2dc4f3fb jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_task_completion_indicator_2dc4f3fb FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_task_completion_indicator_list_fc8d2b85 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_task_completion_indicator_list_fc8d2b85 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_task_indicator_master_c07b884a jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_task_indicator_master_c07b884a FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_training_edit_requests jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_training_edit_requests FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_training_form_list_88933913 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_training_form_list_88933913 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_training_topic_mappings jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_training_topic_mappings FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_trainings jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_trainings FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_user_hierarchies jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_user_hierarchies FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_user_hierarchy_list_a4542a91 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_user_hierarchy_list_a4542a91 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_user_management_roles jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_user_management_roles FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_vrp_active_status_history_5a746fcf jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_vrp_active_status_history_5a746fcf FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_vrp_activity_list_7d178b72 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_vrp_activity_list_7d178b72 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_vrp_approval_histories jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_vrp_approval_histories FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_vrp_bill_add_50a221ea jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_vrp_bill_add_50a221ea FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_vrp_bill_list_0ef6fdc4 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_vrp_bill_list_0ef6fdc4 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_vrp_registration_list_6a8aeba6 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_vrp_registration_list_6a8aeba6 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_vrp_types jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_vrp_types FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_weekly_activity_progress_22c35d60 jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_weekly_activity_progress_22c35d60 FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_weekly_progress_report_1157600e jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_weekly_progress_report_1157600e FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_weekly_target_add_ef9d741d jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_weekly_target_add_ef9d741d FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: module_weekly_target_list_91c4fe5d jj_module_entries_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON public.module_weekly_target_list_91c4fe5d FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_truncate();


--
-- Name: lg_blocks jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.lg_blocks REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: lg_districts jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.lg_districts REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: lg_gram_panchayats jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.lg_gram_panchayats REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: lg_states jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.lg_states REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: lg_villages jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.lg_villages REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_access_control_list_b9d538d4 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_access_control_list_b9d538d4 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_access_controls jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_access_controls REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_activity_group_list_34a52e96 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_activity_group_list_34a52e96 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_activity_master_2e19bce0 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_activity_master_2e19bce0 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_all_user_b8d83be4 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_all_user_b8d83be4 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_approval_list_27d1da1f jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_approval_list_27d1da1f REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_approval_status_summary_1483b5d5 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_approval_status_summary_1483b5d5 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_approvals jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_approvals REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_bank_master_9e57e6ab jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_bank_master_9e57e6ab REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_bill_approval_histories jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_bill_approval_histories REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_bills jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_bills REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_farmer_forms jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_farmer_forms REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_ics_master_483e7ffc jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_ics_master_483e7ffc REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_jeevika_jankar_bill_list_083c76c4 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_jeevika_jankar_bill_list_083c76c4 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_jeevika_jankar_completed_payment_l_bad7b61b jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_jeevika_jankar_completed_payment_l_bad7b61b REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_jeevika_jankar_observation_list_9bfb7dc5 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_jeevika_jankar_observation_list_9bfb7dc5 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_jeevika_jankar_payment_list_2e70d942 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_jeevika_jankar_payment_list_2e70d942 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_jeevika_jankar_payment_list_detail_d8114659 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_jeevika_jankar_payment_list_detail_d8114659 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_jeevika_jankar_transfer_list_73f1674d jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_jeevika_jankar_transfer_list_73f1674d REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_jj_transfers jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_jj_transfers REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_lg_directory_import_status_0543ee43 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_lg_directory_import_status_0543ee43 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_main_activities jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_main_activities REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_monthly_bill_summary_816eb1f0 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_monthly_bill_summary_816eb1f0 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_months jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_months REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_new_user_6724757d jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_new_user_6724757d REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_office_categories jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_office_categories REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_office_list_286e3232 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_office_list_286e3232 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_other_farmer_targets jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_other_farmer_targets REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_other_target_list_410d4f4c jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_other_target_list_410d4f4c REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_other_target_with_farmer_list_0d98bf9f jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_other_target_with_farmer_list_0d98bf9f REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_other_targets jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_other_targets REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_papl360_target_e2ff67fc jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_papl360_target_e2ff67fc REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_papl360_target_list_08d81bec jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_papl360_target_list_08d81bec REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_parent_offices jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_parent_offices REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_payment_details jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_payment_details REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_payment_status_report_17d409eb jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_payment_status_report_17d409eb REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_person_types jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_person_types REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_position_type_486dc9a9 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_position_type_486dc9a9 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_projects jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_projects REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_role_managements jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_role_managements REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_roles jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_roles REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_seed_distribution_target_list_5453661e jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_seed_distribution_target_list_5453661e REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_seed_distribution_targets jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_seed_distribution_targets REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_stakeholder_profile_603e5d20 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_stakeholder_profile_603e5d20 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_stakeholder_roles jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_stakeholder_roles REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_stakeholders jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_stakeholders REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_sub_activities jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_sub_activities REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_sub_offices jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_sub_offices REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_task_completion_indicator_2dc4f3fb jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_task_completion_indicator_2dc4f3fb REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_task_completion_indicator_list_fc8d2b85 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_task_completion_indicator_list_fc8d2b85 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_task_indicator_master_c07b884a jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_task_indicator_master_c07b884a REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_training_edit_requests jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_training_edit_requests REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_training_form_list_88933913 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_training_form_list_88933913 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_training_topic_mappings jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_training_topic_mappings REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_trainings jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_trainings REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_user_hierarchies jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_user_hierarchies REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_user_hierarchy_list_a4542a91 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_user_hierarchy_list_a4542a91 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_user_management_roles jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_user_management_roles REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_vrp_active_status_history_5a746fcf jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_vrp_active_status_history_5a746fcf REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_vrp_activity_list_7d178b72 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_vrp_activity_list_7d178b72 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_vrp_approval_histories jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_vrp_approval_histories REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_vrp_bill_add_50a221ea jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_vrp_bill_add_50a221ea REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_vrp_bill_list_0ef6fdc4 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_vrp_bill_list_0ef6fdc4 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_vrp_registration_list_6a8aeba6 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_vrp_registration_list_6a8aeba6 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_vrp_types jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_vrp_types REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_weekly_activity_progress_22c35d60 jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_weekly_activity_progress_22c35d60 REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_weekly_progress_report_1157600e jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_weekly_progress_report_1157600e REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_weekly_target_add_ef9d741d jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_weekly_target_add_ef9d741d REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: module_weekly_target_list_91c4fe5d jj_module_entries_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entries_versions_update AFTER UPDATE ON public.module_weekly_target_list_91c4fe5d REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entries_versions_update();


--
-- Name: afls jj_module_entry_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_dependency_changed AFTER INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.afls FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entry_dependency_changed();


--
-- Name: target_mappings jj_module_entry_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_dependency_changed AFTER INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.target_mappings FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entry_dependency_changed();


--
-- Name: users jj_module_entry_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_dependency_changed AFTER INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.users FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entry_dependency_changed();


--
-- Name: vrps jj_module_entry_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_dependency_changed AFTER INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.vrps FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_entry_dependency_changed();


--
-- Name: lg_blocks jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.lg_blocks FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: lg_districts jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.lg_districts FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: lg_gram_panchayats jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.lg_gram_panchayats FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: lg_states jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.lg_states FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: lg_villages jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.lg_villages FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_access_control_list_b9d538d4 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_access_control_list_b9d538d4 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_access_controls jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_access_controls FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_activity_group_list_34a52e96 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_activity_group_list_34a52e96 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_activity_master_2e19bce0 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_activity_master_2e19bce0 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_all_user_b8d83be4 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_all_user_b8d83be4 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_approval_list_27d1da1f jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_approval_list_27d1da1f FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_approval_status_summary_1483b5d5 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_approval_status_summary_1483b5d5 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_approvals jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_approvals FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_bank_master_9e57e6ab jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_bank_master_9e57e6ab FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_bill_approval_histories jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_bill_approval_histories FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_bills jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_bills FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_farmer_forms jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_farmer_forms FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_ics_master_483e7ffc jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_ics_master_483e7ffc FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_jeevika_jankar_bill_list_083c76c4 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_jeevika_jankar_bill_list_083c76c4 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_jeevika_jankar_completed_payment_l_bad7b61b jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_jeevika_jankar_completed_payment_l_bad7b61b FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_jeevika_jankar_observation_list_9bfb7dc5 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_jeevika_jankar_observation_list_9bfb7dc5 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_jeevika_jankar_payment_list_2e70d942 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_jeevika_jankar_payment_list_2e70d942 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_jeevika_jankar_payment_list_detail_d8114659 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_jeevika_jankar_payment_list_detail_d8114659 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_jeevika_jankar_transfer_list_73f1674d jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_jeevika_jankar_transfer_list_73f1674d FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_jj_transfers jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_jj_transfers FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_lg_directory_import_status_0543ee43 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_lg_directory_import_status_0543ee43 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_main_activities jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_main_activities FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_monthly_bill_summary_816eb1f0 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_monthly_bill_summary_816eb1f0 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_months jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_months FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_new_user_6724757d jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_new_user_6724757d FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_office_categories jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_office_categories FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_office_list_286e3232 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_office_list_286e3232 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_other_farmer_targets jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_other_farmer_targets FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_other_target_list_410d4f4c jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_other_target_list_410d4f4c FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_other_target_with_farmer_list_0d98bf9f jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_other_target_with_farmer_list_0d98bf9f FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_other_targets jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_other_targets FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_papl360_target_e2ff67fc jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_papl360_target_e2ff67fc FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_papl360_target_list_08d81bec jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_papl360_target_list_08d81bec FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_parent_offices jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_parent_offices FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_payment_details jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_payment_details FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_payment_status_report_17d409eb jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_payment_status_report_17d409eb FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_person_types jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_person_types FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_position_type_486dc9a9 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_position_type_486dc9a9 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_projects jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_projects FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_role_managements jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_role_managements FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_roles jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_roles FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_seed_distribution_target_list_5453661e jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_seed_distribution_target_list_5453661e FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_seed_distribution_targets jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_seed_distribution_targets FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_stakeholder_profile_603e5d20 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_stakeholder_profile_603e5d20 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_stakeholder_roles jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_stakeholder_roles FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_stakeholders jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_stakeholders FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_sub_activities jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_sub_activities FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_sub_offices jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_sub_offices FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_task_completion_indicator_2dc4f3fb jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_task_completion_indicator_2dc4f3fb FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_task_completion_indicator_list_fc8d2b85 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_task_completion_indicator_list_fc8d2b85 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_task_indicator_master_c07b884a jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_task_indicator_master_c07b884a FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_training_edit_requests jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_training_edit_requests FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_training_form_list_88933913 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_training_form_list_88933913 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_training_topic_mappings jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_training_topic_mappings FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_trainings jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_trainings FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_user_hierarchies jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_user_hierarchies FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_user_hierarchy_list_a4542a91 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_user_hierarchy_list_a4542a91 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_user_management_roles jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_user_management_roles FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_vrp_active_status_history_5a746fcf jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_vrp_active_status_history_5a746fcf FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_vrp_activity_list_7d178b72 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_vrp_activity_list_7d178b72 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_vrp_approval_histories jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_vrp_approval_histories FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_vrp_bill_add_50a221ea jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_vrp_bill_add_50a221ea FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_vrp_bill_list_0ef6fdc4 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_vrp_bill_list_0ef6fdc4 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_vrp_registration_list_6a8aeba6 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_vrp_registration_list_6a8aeba6 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_vrp_types jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_vrp_types FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_weekly_activity_progress_22c35d60 jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_weekly_activity_progress_22c35d60 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_weekly_progress_report_1157600e jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_weekly_progress_report_1157600e FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_weekly_target_add_ef9d741d jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_weekly_target_add_ef9d741d FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: module_weekly_target_list_91c4fe5d jj_module_entry_identity_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON public.module_weekly_target_list_91c4fe5d FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_identity_delete();


--
-- Name: lg_blocks jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.lg_blocks FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: lg_districts jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.lg_districts FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: lg_gram_panchayats jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.lg_gram_panchayats FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: lg_states jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.lg_states FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: lg_villages jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.lg_villages FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_access_control_list_b9d538d4 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_access_control_list_b9d538d4 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_access_controls jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_access_controls FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_activity_group_list_34a52e96 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_activity_group_list_34a52e96 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_activity_master_2e19bce0 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_activity_master_2e19bce0 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_all_user_b8d83be4 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_all_user_b8d83be4 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_approval_list_27d1da1f jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_approval_list_27d1da1f FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_approval_status_summary_1483b5d5 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_approval_status_summary_1483b5d5 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_approvals jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_approvals FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_bank_master_9e57e6ab jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_bank_master_9e57e6ab FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_bill_approval_histories jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_bill_approval_histories FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_bills jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_bills FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_farmer_forms jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_farmer_forms FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_ics_master_483e7ffc jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_ics_master_483e7ffc FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_jeevika_jankar_bill_list_083c76c4 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_jeevika_jankar_bill_list_083c76c4 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_jeevika_jankar_completed_payment_l_bad7b61b jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_jeevika_jankar_completed_payment_l_bad7b61b FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_jeevika_jankar_observation_list_9bfb7dc5 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_jeevika_jankar_observation_list_9bfb7dc5 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_jeevika_jankar_payment_list_2e70d942 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_jeevika_jankar_payment_list_2e70d942 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_jeevika_jankar_payment_list_detail_d8114659 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_jeevika_jankar_payment_list_detail_d8114659 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_jeevika_jankar_transfer_list_73f1674d jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_jeevika_jankar_transfer_list_73f1674d FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_jj_transfers jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_jj_transfers FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_lg_directory_import_status_0543ee43 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_lg_directory_import_status_0543ee43 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_main_activities jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_main_activities FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_monthly_bill_summary_816eb1f0 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_monthly_bill_summary_816eb1f0 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_months jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_months FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_new_user_6724757d jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_new_user_6724757d FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_office_categories jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_office_categories FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_office_list_286e3232 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_office_list_286e3232 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_other_farmer_targets jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_other_farmer_targets FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_other_target_list_410d4f4c jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_other_target_list_410d4f4c FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_other_target_with_farmer_list_0d98bf9f jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_other_target_with_farmer_list_0d98bf9f FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_other_targets jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_other_targets FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_papl360_target_e2ff67fc jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_papl360_target_e2ff67fc FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_papl360_target_list_08d81bec jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_papl360_target_list_08d81bec FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_parent_offices jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_parent_offices FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_payment_details jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_payment_details FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_payment_status_report_17d409eb jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_payment_status_report_17d409eb FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_person_types jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_person_types FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_position_type_486dc9a9 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_position_type_486dc9a9 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_projects jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_projects FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_role_managements jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_role_managements FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_roles jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_roles FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_seed_distribution_target_list_5453661e jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_seed_distribution_target_list_5453661e FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_seed_distribution_targets jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_seed_distribution_targets FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_stakeholder_profile_603e5d20 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_stakeholder_profile_603e5d20 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_stakeholder_roles jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_stakeholder_roles FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_stakeholders jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_stakeholders FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_sub_activities jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_sub_activities FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_sub_offices jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_sub_offices FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_task_completion_indicator_2dc4f3fb jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_task_completion_indicator_2dc4f3fb FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_task_completion_indicator_list_fc8d2b85 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_task_completion_indicator_list_fc8d2b85 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_task_indicator_master_c07b884a jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_task_indicator_master_c07b884a FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_training_edit_requests jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_training_edit_requests FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_training_form_list_88933913 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_training_form_list_88933913 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_training_topic_mappings jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_training_topic_mappings FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_trainings jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_trainings FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_user_hierarchies jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_user_hierarchies FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_user_hierarchy_list_a4542a91 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_user_hierarchy_list_a4542a91 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_user_management_roles jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_user_management_roles FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_vrp_active_status_history_5a746fcf jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_vrp_active_status_history_5a746fcf FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_vrp_activity_list_7d178b72 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_vrp_activity_list_7d178b72 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_vrp_approval_histories jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_vrp_approval_histories FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_vrp_bill_add_50a221ea jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_vrp_bill_add_50a221ea FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_vrp_bill_list_0ef6fdc4 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_vrp_bill_list_0ef6fdc4 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_vrp_registration_list_6a8aeba6 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_vrp_registration_list_6a8aeba6 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_vrp_types jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_vrp_types FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_weekly_activity_progress_22c35d60 jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_weekly_activity_progress_22c35d60 FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_weekly_progress_report_1157600e jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_weekly_progress_report_1157600e FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_weekly_target_add_ef9d741d jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_weekly_target_add_ef9d741d FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_weekly_target_list_91c4fe5d jj_module_entry_prepare; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON public.module_weekly_target_list_91c4fe5d FOR EACH ROW EXECUTE FUNCTION public.jj_module_entry_prepare();


--
-- Name: module_records jj_module_master_sync_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_master_sync_delete AFTER DELETE ON public.module_records FOR EACH ROW EXECUTE FUNCTION public.jj_module_master_sync();


--
-- Name: module_records jj_module_master_sync_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_master_sync_write AFTER INSERT OR UPDATE ON public.module_records FOR EACH ROW EXECUTE FUNCTION public.jj_module_master_sync();


--
-- Name: module_records jj_module_mirrors_sync_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_mirrors_sync_truncate AFTER TRUNCATE ON public.module_records FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_mirrors_truncate();


--
-- Name: module_records jj_module_record_versions_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_record_versions_delete AFTER DELETE ON public.module_records REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_record_versions_delete();


--
-- Name: module_records jj_module_record_versions_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_record_versions_insert AFTER INSERT ON public.module_records REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_record_versions_insert();


--
-- Name: module_records jj_module_record_versions_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_record_versions_truncate AFTER TRUNCATE ON public.module_records FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_record_versions_truncate();


--
-- Name: module_records jj_module_record_versions_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jj_module_record_versions_update AFTER UPDATE ON public.module_records REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.jj_module_record_versions_update();


--
-- Name: module_entries module_entries_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER module_entries_write INSTEAD OF INSERT OR DELETE OR UPDATE ON public.module_entries FOR EACH ROW EXECUTE FUNCTION public.jj_module_entries_write();


--
-- Name: module_records zz_module_entries_legacy_bridge; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_module_entries_legacy_bridge AFTER INSERT OR DELETE OR UPDATE ON public.module_records FOR EACH ROW EXECUTE FUNCTION public.jj_module_entries_legacy_bridge();


--
-- Name: vrp_ics_mappings fk_rails_00d6e4a276; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_ics_mappings
    ADD CONSTRAINT fk_rails_00d6e4a276 FOREIGN KEY (vrp_id) REFERENCES public.vrps(id);


--
-- Name: jj_quiz_attempts fk_rails_0b0220e6ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_attempts
    ADD CONSTRAINT fk_rails_0b0220e6ba FOREIGN KEY (vrp_id) REFERENCES public.vrps(id);


--
-- Name: jj_quiz_answers fk_rails_3df597e699; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_answers
    ADD CONSTRAINT fk_rails_3df597e699 FOREIGN KEY (jj_quiz_question_id) REFERENCES public.jj_quiz_questions(id);


--
-- Name: target_mappings fk_rails_443541e4cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.target_mappings
    ADD CONSTRAINT fk_rails_443541e4cc FOREIGN KEY (vrp_id) REFERENCES public.vrps(id);


--
-- Name: jj_quiz_questions fk_rails_5bbd4693d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_questions
    ADD CONSTRAINT fk_rails_5bbd4693d0 FOREIGN KEY (jj_quiz_id) REFERENCES public.jj_quizzes(id);


--
-- Name: vrps fk_rails_899fa5030c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrps
    ADD CONSTRAINT fk_rails_899fa5030c FOREIGN KEY (vrp_bank_master_id) REFERENCES public.vrp_bank_masters(id);


--
-- Name: farmer_app_login_events fk_rails_96a10b58cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_app_login_events
    ADD CONSTRAINT fk_rails_96a10b58cc FOREIGN KEY (farmer_app_login_id) REFERENCES public.farmer_app_logins(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: jj_quiz_attempts fk_rails_a229f42c8c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_attempts
    ADD CONSTRAINT fk_rails_a229f42c8c FOREIGN KEY (jj_quiz_id) REFERENCES public.jj_quizzes(id);


--
-- Name: vrp_profiles fk_rails_bc7847ac80; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vrp_profiles
    ADD CONSTRAINT fk_rails_bc7847ac80 FOREIGN KEY (vrp_id) REFERENCES public.vrps(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: target_mappings fk_rails_e1183819bc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.target_mappings
    ADD CONSTRAINT fk_rails_e1183819bc FOREIGN KEY (vrp_ics_mapping_id) REFERENCES public.vrp_ics_mappings(id);


--
-- Name: farmer_devices fk_rails_f166242f7a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.farmer_devices
    ADD CONSTRAINT fk_rails_f166242f7a FOREIGN KEY (farmer_app_login_id) REFERENCES public.farmer_app_logins(id);


--
-- Name: jj_quiz_answers fk_rails_f90d6bc11a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jj_quiz_answers
    ADD CONSTRAINT fk_rails_f90d6bc11a FOREIGN KEY (jj_quiz_attempt_id) REFERENCES public.jj_quiz_attempts(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261124180000'),
('20261124170000'),
('20261124160000'),
('20261124150000'),
('20261124140000'),
('20261124120000'),
('20261124100000'),
('20261123171000'),
('20261123170000'),
('20261123161000'),
('20261123160000'),
('20261123110000'),
('20261123100000'),
('20261121100000'),
('20261119100000'),
('20261116120000'),
('20261111140000'),
('20261111100000'),
('20261110180000'),
('20261110160000'),
('20261110140000'),
('20261110120000'),
('20261027163000'),
('20261026180000'),
('20261015130000'),
('20261015120000'),
('20261014130000'),
('20261014110000'),
('20261013090000'),
('20261012120000'),
('20261012100000'),
('20261005140000'),
('20261005130000'),
('20260929120000'),
('20260919102909'),
('20260915110000'),
('20260915100000'),
('20260908102043'),
('20260803114000'),
('20260801124500'),
('20260801113000'),
('20260801090000'),
('20260721120000'),
('20260721010000'),
('20260717170000'),
('20260626093000'),
('20260623062000'),
('20260619111000'),
('20260619110000'),
('20260619105000'),
('20260619104000'),
('20260619103000'),
('20260619102000'),
('20260619101000'),
('20260619100000'),
('20260619095000'),
('20260619094000'),
('20260619093000'),
('20260619092000'),
('20260619091000'),
('20260619090000'),
('20260615174000'),
('20260615173000'),
('20260615172000'),
('20260615170000'),
('20260615133000'),
('20260609113000'),
('20260609110000'),
('20260608100000'),
('20260606121000'),
('20260606120000'),
('20260604143000'),
('20260603114000'),
('20260603113000'),
('20260603111500'),
('20260603110000'),
('20260602120000'),
('20260602115000'),
('20260602114000'),
('20260602113000'),
('20260602112000'),
('20260602111000'),
('20260602110000'),
('20260602105000'),
('20260602104000'),
('20260602103000'),
('20260602102000'),
('20260602101000'),
('20260602100000'),
('20260602093000'),
('20260602091000'),
('20260602090000'),
('20260601093000'),
('20260527092000'),
('20260527091000'),
('20260525111000'),
('20260525110000');

