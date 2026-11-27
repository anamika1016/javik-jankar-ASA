# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_24_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "afls", force: :cascade do |t|
    t.string "aadhar"
    t.string "broker_id"
    t.datetime "created_at", null: false
    t.date "date"
    t.string "dispoce"
    t.decimal "estimate_quantity", precision: 18, scale: 4
    t.decimal "estimate_quantity_admin", precision: 18, scale: 4
    t.string "farm_id"
    t.string "farmer_name"
    t.string "father_name"
    t.string "fco"
    t.string "fco_id"
    t.string "fpo_id"
    t.string "fpo_name"
    t.string "fy"
    t.string "ginning_id"
    t.string "ics_id"
    t.string "ics_name"
    t.string "import_key"
    t.string "ip"
    t.string "khasara_no"
    t.decimal "lattitude", precision: 20, scale: 8
    t.decimal "longitude", precision: 20, scale: 8
    t.string "mobile_no"
    t.date "purchase_date"
    t.string "purchase_product"
    t.string "purchase_product_type"
    t.decimal "purchase_quantity", precision: 18, scale: 4
    t.decimal "purchase_quantity_amount", precision: 18, scale: 4
    t.string "qr_aadhar"
    t.string "qr_mobile"
    t.text "qrcode"
    t.datetime "qrcode_date"
    t.string "reg_type"
    t.string "slip_no"
    t.string "status"
    t.decimal "total_farm_area", precision: 18, scale: 4
    t.string "tracenet_no"
    t.datetime "updated_at", null: false
    t.string "village_id"
    t.string "village_name"
    t.index "lower(btrim((fco)::text))", name: "index_afls_on_normalized_fco_name"
    t.index "lower(btrim((fco_id)::text))", name: "index_afls_on_normalized_fco_id"
    t.index ["created_at"], name: "index_afls_on_created_at"
    t.index ["farm_id"], name: "index_afls_on_farm_id"
    t.index ["farmer_name"], name: "index_afls_on_farmer_name"
    t.index ["fco_id", "ics_id", "village_id"], name: "index_afls_on_mapping_lookup"
    t.index ["mobile_no"], name: "index_afls_on_mobile_no"
    t.index ["slip_no"], name: "index_afls_on_slip_no"
    t.index ["tracenet_no"], name: "index_afls_on_tracenet_no"
    t.index ["updated_at"], name: "index_afls_on_updated_at", order: :desc
    t.index ["village_id"], name: "index_afls_on_village_id"
  end

  create_table "app_user_logins", force: :cascade do |t|
    t.string "app_version"
    t.datetime "created_at", null: false
    t.string "device"
    t.string "fcoc"
    t.string "ip"
    t.datetime "logged_in_at", null: false
    t.string "login_method", default: "password", null: false
    t.string "mobile_no"
    t.string "name"
    t.string "office_name"
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["logged_in_at"], name: "index_app_user_logins_on_logged_in_at", order: :desc
    t.index ["record_type", "record_id", "logged_in_at"], name: "index_app_user_logins_on_user_and_time"
  end

  create_table "asa360_master", force: :cascade do |t|
    t.integer "o_id"
    t.string "o_name", limit: 200
    t.string "o_type", limit: 50
  end

  create_table "farmer_app_login_events", force: :cascade do |t|
    t.string "app_version"
    t.datetime "created_at", null: false
    t.string "device"
    t.bigint "farmer_app_login_id", null: false
    t.string "identifier_type"
    t.string "ip"
    t.decimal "latitude", precision: 10, scale: 7
    t.datetime "logged_in_at", null: false
    t.decimal "longitude", precision: 10, scale: 7
    t.string "place"
    t.datetime "updated_at", null: false
    t.index ["farmer_app_login_id", "logged_in_at"], name: "index_farmer_login_events_on_login_and_time"
    t.index ["logged_in_at"], name: "index_farmer_app_login_events_on_logged_in_at", order: :desc
  end

  create_table "farmer_app_logins", force: :cascade do |t|
    t.string "aadhaar_digest"
    t.string "aadhaar_last4", limit: 4
    t.string "block_name"
    t.datetime "created_at", null: false
    t.string "district_name"
    t.string "farmer_external_id"
    t.string "father_husband_name"
    t.string "fco_name"
    t.datetime "first_logged_in_at"
    t.string "full_name"
    t.string "ics_name"
    t.string "last_app_version"
    t.string "last_device"
    t.string "last_identifier_type"
    t.datetime "last_logged_in_at"
    t.string "last_login_ip"
    t.decimal "last_login_latitude", precision: 10, scale: 7
    t.decimal "last_login_longitude", precision: 10, scale: 7
    t.string "last_login_place"
    t.integer "login_count", default: 0, null: false
    t.string "mobile_no"
    t.string "state_id"
    t.string "state_name"
    t.string "tracenet_id"
    t.datetime "updated_at", null: false
    t.string "village_name"
    t.index ["aadhaar_digest"], name: "index_farmer_app_logins_on_aadhaar_digest"
    t.index ["farmer_external_id"], name: "index_farmer_app_logins_on_farmer_external_id", unique: true
    t.index ["last_logged_in_at"], name: "index_farmer_app_logins_on_last_logged_in_at", order: :desc
    t.index ["mobile_no"], name: "index_farmer_app_logins_on_mobile_no"
    t.index ["state_id"], name: "index_farmer_app_logins_on_state_id"
  end

  create_table "farmer_devices", force: :cascade do |t|
    t.string "app_version"
    t.datetime "created_at", null: false
    t.bigint "farmer_app_login_id", null: false
    t.datetime "last_seen_at", null: false
    t.string "platform"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["farmer_app_login_id", "last_seen_at"], name: "index_farmer_devices_on_login_and_seen"
    t.index ["token"], name: "index_farmer_devices_on_token", unique: true
  end

  create_table "farmer_login_locks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "last_failed_at"
    t.datetime "locked_until"
    t.string "mobile_no", null: false
    t.datetime "updated_at", null: false
    t.index ["locked_until"], name: "index_farmer_login_locks_on_locked_until"
    t.index ["mobile_no"], name: "index_farmer_login_locks_on_mobile_no", unique: true
  end

  create_table "farmer_login_otps", force: :cascade do |t|
    t.string "aadhaar_digest"
    t.integer "attempts", default: 0, null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "identifier_type"
    t.string "jti", null: false
    t.string "mobile_no", null: false
    t.string "otp_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_farmer_login_otps_on_expires_at"
    t.index ["jti"], name: "index_farmer_login_otps_on_jti", unique: true
    t.index ["mobile_no", "created_at"], name: "index_farmer_login_otps_on_mobile_no_and_created_at"
  end

  create_table "farmer_news", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "created_by"
    t.string "image_path"
    t.string "link_url"
    t.datetime "published_at", null: false
    t.string "state_id"
    t.string "state_name"
    t.string "status", default: "Active", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "state_id", "published_at"], name: "index_farmer_news_on_feed", order: { published_at: :desc }
  end

  create_table "farmer_push_messages", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "device_count", default: 0, null: false
    t.text "error"
    t.integer "failed_count", default: 0, null: false
    t.bigint "notifiable_id", null: false
    t.string "notifiable_type", null: false
    t.datetime "sent_at"
    t.integer "sent_count", default: 0, null: false
    t.string "state_id"
    t.string "status", default: "Pending", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_farmer_push_messages_on_created_at", order: :desc
    t.index ["notifiable_type", "notifiable_id"], name: "index_farmer_push_messages_on_notifiable"
  end

  create_table "farmer_videos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "created_by"
    t.text "description"
    t.string "duration_label"
    t.datetime "published_at", null: false
    t.string "state_id"
    t.string "state_name"
    t.string "status", default: "Active", null: false
    t.string "thumbnail_path"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "video_path"
    t.string "video_url"
    t.index ["status", "state_id", "published_at"], name: "index_farmer_videos_on_feed", order: { published_at: :desc }
  end

  create_table "jj_quiz_answers", force: :cascade do |t|
    t.boolean "correct", default: false, null: false
    t.string "correct_option", null: false
    t.datetime "created_at", null: false
    t.bigint "jj_quiz_attempt_id", null: false
    t.bigint "jj_quiz_question_id", null: false
    t.decimal "marks_awarded", precision: 8, scale: 2, default: "0.0", null: false
    t.jsonb "question_snapshot", default: {}, null: false
    t.string "selected_option"
    t.datetime "updated_at", null: false
    t.index ["jj_quiz_attempt_id", "jj_quiz_question_id"], name: "idx_jj_answers_on_attempt_and_question", unique: true
    t.index ["jj_quiz_attempt_id"], name: "index_jj_quiz_answers_on_jj_quiz_attempt_id"
    t.index ["jj_quiz_question_id"], name: "index_jj_quiz_answers_on_jj_quiz_question_id"
  end

  create_table "jj_quiz_attempts", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "jj_quiz_id", null: false
    t.string "login_ip"
    t.boolean "passed", default: false, null: false
    t.decimal "percentage", precision: 7, scale: 2, default: "0.0", null: false
    t.decimal "score", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "started_at"
    t.string "status", default: "qr_issued", null: false
    t.datetime "submitted_at"
    t.decimal "total_marks", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "vrp_id", null: false
    t.index ["access_token"], name: "index_jj_quiz_attempts_on_access_token", unique: true
    t.index ["jj_quiz_id", "vrp_id"], name: "index_jj_quiz_attempts_on_jj_quiz_id_and_vrp_id"
    t.index ["jj_quiz_id"], name: "index_jj_quiz_attempts_on_jj_quiz_id"
    t.index ["status"], name: "index_jj_quiz_attempts_on_status"
    t.index ["vrp_id"], name: "index_jj_quiz_attempts_on_vrp_id"
  end

  create_table "jj_quiz_questions", force: :cascade do |t|
    t.string "correct_option", null: false
    t.datetime "created_at", null: false
    t.bigint "jj_quiz_id", null: false
    t.decimal "marks", precision: 8, scale: 2, default: "1.0", null: false
    t.string "option_a", null: false
    t.string "option_b", null: false
    t.string "option_c"
    t.string "option_d"
    t.integer "position", default: 1, null: false
    t.text "question_text", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["jj_quiz_id", "position"], name: "index_jj_quiz_questions_on_jj_quiz_id_and_position"
    t.index ["jj_quiz_id"], name: "index_jj_quiz_questions_on_jj_quiz_id"
    t.index ["status"], name: "index_jj_quiz_questions_on_status"
  end

  create_table "jj_quizzes", force: :cascade do |t|
    t.boolean "allow_retake", default: false, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "created_by_type"
    t.text "description"
    t.integer "duration_minutes", default: 30, null: false
    t.datetime "ends_at"
    t.decimal "passing_marks", precision: 8, scale: 2
    t.datetime "starts_at"
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_type", "created_by_id"], name: "index_jj_quizzes_on_created_by_type_and_created_by_id"
    t.index ["status"], name: "index_jj_quizzes_on_status"
  end

  create_table "lg_blocks", id: :bigint, default: nil, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "block_code"
    t.string "block_name"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "district_code"
    t.string "district_name"
    t.string "gp_code"
    t.string "gram_panchayat_name"
    t.string "source_slug", null: false
    t.string "state_code"
    t.string "state_name"
    t.string "status"
    t.string "sub_district_code"
    t.string "sub_district_name"
    t.datetime "updated_at", null: false
    t.string "village_code"
    t.string "village_name"
    t.index "lower(btrim((block_name)::text))", name: "index_lg_blocks_on_normalized_name"
    t.index "lower(btrim((district_name)::text))", name: "index_lg_blocks_on_normalized_district"
    t.index ["active", "source_slug"], name: "index_lg_blocks_on_active_and_source"
    t.index ["created_at"], name: "index_lg_blocks_on_created_at"
    t.index ["source_slug"], name: "index_lg_blocks_on_source_slug"
  end

  create_table "lg_districts", id: :bigint, default: nil, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "block_code"
    t.string "block_name"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "district_code"
    t.string "district_name"
    t.string "gp_code"
    t.string "gram_panchayat_name"
    t.string "source_slug", null: false
    t.string "state_code"
    t.string "state_name"
    t.string "status"
    t.string "sub_district_code"
    t.string "sub_district_name"
    t.datetime "updated_at", null: false
    t.string "village_code"
    t.string "village_name"
    t.index "lower(btrim((district_name)::text))", name: "index_lg_districts_on_normalized_name"
    t.index "lower(btrim((state_name)::text))", name: "index_lg_districts_on_normalized_state"
    t.index ["active", "source_slug"], name: "index_lg_districts_on_active_and_source"
    t.index ["created_at"], name: "index_lg_districts_on_created_at"
    t.index ["source_slug"], name: "index_lg_districts_on_source_slug"
  end

  create_table "lg_gram_panchayats", id: :bigint, default: nil, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "block_code"
    t.string "block_name"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "district_code"
    t.string "district_name"
    t.string "gp_code"
    t.string "gram_panchayat_name"
    t.string "source_slug", null: false
    t.string "state_code"
    t.string "state_name"
    t.string "status"
    t.string "sub_district_code"
    t.string "sub_district_name"
    t.datetime "updated_at", null: false
    t.string "village_code"
    t.string "village_name"
    t.index "lower(btrim((block_name)::text))", name: "index_lg_gps_on_normalized_block"
    t.index "lower(btrim((gram_panchayat_name)::text))", name: "index_lg_gps_on_normalized_name"
    t.index ["active", "source_slug"], name: "index_lg_gram_panchayats_on_active_and_source"
    t.index ["created_at"], name: "index_lg_gram_panchayats_on_created_at"
    t.index ["source_slug"], name: "index_lg_gram_panchayats_on_source_slug"
  end

  create_table "lg_states", id: :bigint, default: nil, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "block_code"
    t.string "block_name"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "district_code"
    t.string "district_name"
    t.string "gp_code"
    t.string "gram_panchayat_name"
    t.string "source_slug", null: false
    t.string "state_code"
    t.string "state_name"
    t.string "status"
    t.string "sub_district_code"
    t.string "sub_district_name"
    t.datetime "updated_at", null: false
    t.string "village_code"
    t.string "village_name"
    t.index "lower(btrim((state_name)::text))", name: "index_lg_states_on_normalized_name"
    t.index ["active", "source_slug"], name: "index_lg_states_on_active_and_source"
    t.index ["created_at"], name: "index_lg_states_on_created_at"
    t.index ["source_slug"], name: "index_lg_states_on_source_slug"
  end

  create_table "lg_villages", id: :bigint, default: nil, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "block_code"
    t.string "block_name"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "district_code"
    t.string "district_name"
    t.string "gp_code"
    t.string "gram_panchayat_name"
    t.string "source_slug", null: false
    t.string "state_code"
    t.string "state_name"
    t.string "status"
    t.string "sub_district_code"
    t.string "sub_district_name"
    t.datetime "updated_at", null: false
    t.string "village_code"
    t.string "village_name"
    t.index "lower(btrim((block_name)::text))", name: "index_lg_villages_on_normalized_block"
    t.index "lower(btrim((gram_panchayat_name)::text))", name: "index_lg_villages_on_normalized_gp"
    t.index "lower(btrim((village_name)::text))", name: "index_lg_villages_on_normalized_name"
    t.index ["active", "source_slug"], name: "index_lg_villages_on_active_and_source"
    t.index ["created_at"], name: "index_lg_villages_on_created_at"
    t.index ["source_slug"], name: "index_lg_villages_on_source_slug"
    t.index ["village_code"], name: "index_lg_villages_on_village_code"
  end

  create_table "module_access_controls", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.virtual "can_view", type: :text, as: "NULLIF(btrim((data ->> 'can_view'::text)), ''::text)", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "role_name", type: :text, as: "NULLIF(btrim((data ->> 'role_name'::text)), ''::text)", stored: true
    t.virtual "stakeholder", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder'::text)), ''::text)", stored: true
    t.virtual "stakeholder_role", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_role'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(can_view))", name: "index_module_access_controls_on_normalized_can_view"
    t.index "lower(btrim(role_name))", name: "index_module_access_controls_on_normalized_role_name"
    t.index "lower(btrim(stakeholder))", name: "index_module_access_controls_on_normalized_stakeholder"
    t.index "lower(btrim(stakeholder_role))", name: "index_module_access_controls_on_normalized_stakeholder_role"
    t.index ["active"], name: "index_module_access_controls_on_active"
    t.index ["created_at"], name: "index_module_access_controls_on_created_at"
    t.index ["role_name"], name: "index_module_access_controls_on_role_name"
    t.index ["stakeholder_role", "role_name"], name: "index_module_access_controls_on_stakeholder_role_and_role_name"
  end

  create_table "module_approvals", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.virtual "approval_level", type: :text, as: "NULLIF(btrim((data ->> 'approval_level'::text)), ''::text)", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "module_name", type: :text, as: "NULLIF(btrim((data ->> 'module_name'::text)), ''::text)", stored: true
    t.virtual "role_name", type: :text, as: "NULLIF(btrim((data ->> 'role_name'::text)), ''::text)", stored: true
    t.virtual "stakeholder_role", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_role'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(approval_level))", name: "index_module_approvals_on_normalized_approval_level"
    t.index "lower(btrim(module_name))", name: "index_module_approvals_on_normalized_module_name"
    t.index "lower(btrim(role_name))", name: "index_module_approvals_on_normalized_role_name"
    t.index "lower(btrim(stakeholder_role))", name: "index_module_approvals_on_normalized_stakeholder_role"
    t.index ["active"], name: "index_module_approvals_on_active"
    t.index ["created_at"], name: "index_module_approvals_on_created_at"
    t.index ["module_name", "approval_level"], name: "index_module_approvals_on_module_name_and_approval_level"
  end

  create_table "module_bills", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text]))))", stored: true
    t.virtual "bill_month", type: :text, as: "NULLIF(btrim((data ->> 'bill_month'::text)), ''::text)", stored: true
    t.virtual "bill_status", type: :text, as: "NULLIF(btrim((data ->> 'status'::text)), ''::text)", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "grand_total", type: :text, as: "NULLIF(btrim((data ->> 'grand_total'::text)), ''::text)", stored: true
    t.virtual "select_vrp", type: :text, as: "NULLIF(btrim((data ->> 'select_vrp'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "((data ->> 'bill_month'::text))", name: "index_module_bills_on_payload_month"
    t.index "((data ->> 'select_vrp'::text)), ((data ->> 'bill_month'::text))", name: "index_module_bills_on_payload_owner_month"
    t.index "lower(btrim(bill_month))", name: "index_module_bills_on_normalized_bill_month"
    t.index "lower(btrim(bill_status))", name: "index_module_bills_on_normalized_bill_status"
    t.index "lower(btrim(grand_total))", name: "index_module_bills_on_normalized_grand_total"
    t.index "lower(btrim(select_vrp))", name: "index_module_bills_on_normalized_select_vrp"
    t.index ["active"], name: "index_module_bills_on_active"
    t.index ["bill_month"], name: "index_module_bills_on_bill_month"
    t.index ["created_at"], name: "index_module_bills_on_created_at"
    t.index ["select_vrp", "bill_month"], name: "index_module_bills_on_select_vrp_and_bill_month"
  end

  create_table "module_jj_transfers", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "fcoc", type: :text, as: "NULLIF(btrim((data ->> 'fcoc'::text)), ''::text)", stored: true
    t.virtual "sidebar_menu", type: :text, as: "NULLIF(btrim((data ->> 'sidebar_menu'::text)), ''::text)", stored: true
    t.virtual "stakeholder_category", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.virtual "user_name", type: :text, as: "NULLIF(btrim((data ->> 'user_name'::text)), ''::text)", stored: true
    t.index "lower(btrim(fcoc))", name: "index_module_jj_transfers_on_normalized_fcoc"
    t.index "lower(btrim(sidebar_menu))", name: "index_module_jj_transfers_on_normalized_sidebar_menu"
    t.index "lower(btrim(stakeholder_category))", name: "index_module_jj_transfers_on_normalized_stakeholder_category"
    t.index "lower(btrim(user_name))", name: "index_module_jj_transfers_on_normalized_user_name"
    t.index ["active"], name: "index_module_jj_transfers_on_active"
    t.index ["created_at"], name: "index_module_jj_transfers_on_created_at"
    t.index ["fcoc"], name: "index_module_jj_transfers_on_fcoc"
    t.index ["user_name"], name: "index_module_jj_transfers_on_user_name"
  end

  create_table "module_main_activities", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "main_activity_name", type: :text, as: "NULLIF(btrim((data ->> 'main_activity_name'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(main_activity_name))", name: "index_module_main_activities_on_normalized_main_activity_name"
    t.index ["active"], name: "index_module_main_activities_on_active"
    t.index ["created_at"], name: "index_module_main_activities_on_created_at"
    t.index ["main_activity_name"], name: "index_module_main_activities_on_main_activity_name"
  end

  create_table "module_months", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "financial_year", type: :text, as: "NULLIF(btrim((data ->> 'financial_year'::text)), ''::text)", stored: true
    t.virtual "month_name", type: :text, as: "NULLIF(btrim((data ->> 'month_name'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(financial_year))", name: "index_module_months_on_normalized_financial_year"
    t.index "lower(btrim(month_name))", name: "index_module_months_on_normalized_month_name"
    t.index ["active"], name: "index_module_months_on_active"
    t.index ["created_at"], name: "index_module_months_on_created_at"
    t.index ["financial_year", "month_name"], name: "index_module_months_on_financial_year_and_month_name"
  end

  create_table "module_office_categories", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "office_level", type: :text, as: "NULLIF(btrim((data ->> 'office_level'::text)), ''::text)", stored: true
    t.virtual "office_name", type: :text, as: "NULLIF(btrim((data ->> 'office_name'::text)), ''::text)", stored: true
    t.virtual "parent_category", type: :text, as: "NULLIF(btrim((data ->> 'parent_category'::text)), ''::text)", stored: true
    t.virtual "stakeholder_category", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(office_level))", name: "index_module_office_categories_on_normalized_office_level"
    t.index "lower(btrim(office_name))", name: "index_module_office_categories_on_normalized_office_name"
    t.index "lower(btrim(parent_category))", name: "index_module_office_categories_on_normalized_parent_category"
    t.index "lower(btrim(stakeholder_category))", name: "index_module_office_categories_on_normalized_stakeholder_catego"
    t.index ["active"], name: "index_module_office_categories_on_active"
    t.index ["created_at"], name: "index_module_office_categories_on_created_at"
    t.index ["office_name"], name: "index_module_office_categories_on_office_name"
    t.index ["parent_category"], name: "index_module_office_categories_on_parent_category"
  end

  create_table "module_other_farmer_targets", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "fcoc_name", type: :text, as: "NULLIF(btrim((data ->> 'fcoc_name'::text)), ''::text)", stored: true
    t.virtual "jeevika_jankar_id", type: :text, as: "NULLIF(btrim((data ->> 'jeevika_jankar_id'::text)), ''::text)", stored: true
    t.virtual "month", type: :text, as: "NULLIF(btrim((data ->> 'month'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.virtual "target_mapping_id", type: :text, as: "NULLIF(btrim((data ->> 'target_mapping_id'::text)), ''::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim((data ->> 'month'::text)))", name: "index_module_other_farmer_targets_on_payload_month"
    t.index "lower(btrim(fcoc_name))", name: "index_module_other_farmer_targets_on_normalized_fcoc_name"
    t.index "lower(btrim(jeevika_jankar_id))", name: "index_module_other_farmer_targets_on_normalized_jeevika_jankar_"
    t.index "lower(btrim(month))", name: "index_module_other_farmer_targets_on_normalized_month"
    t.index "lower(btrim(target_mapping_id))", name: "index_module_other_farmer_targets_on_normalized_target_mapping_"
    t.index ["active"], name: "index_module_other_farmer_targets_on_active"
    t.index ["created_at"], name: "index_module_other_farmer_targets_on_created_at"
    t.index ["month"], name: "index_module_other_farmer_targets_on_month"
    t.index ["target_mapping_id"], name: "index_module_other_farmer_targets_on_target_mapping_id"
  end

  create_table "module_other_targets", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "fcoc_name", type: :text, as: "NULLIF(btrim((data ->> 'fcoc_name'::text)), ''::text)", stored: true
    t.virtual "ics_name", type: :text, as: "NULLIF(btrim((data ->> 'ics_name'::text)), ''::text)", stored: true
    t.virtual "jeevika_jankar_id", type: :text, as: "NULLIF(btrim((data ->> 'jeevika_jankar_id'::text)), ''::text)", stored: true
    t.virtual "month", type: :text, as: "NULLIF(btrim((data ->> 'month'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.virtual "target_mapping_id", type: :text, as: "NULLIF(btrim((data ->> 'target_mapping_id'::text)), ''::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim((data ->> 'month'::text)))", name: "index_module_other_targets_on_payload_month"
    t.index "lower(btrim(fcoc_name))", name: "index_module_other_targets_on_normalized_fcoc_name"
    t.index "lower(btrim(ics_name))", name: "index_module_other_targets_on_normalized_ics_name"
    t.index "lower(btrim(jeevika_jankar_id))", name: "index_module_other_targets_on_normalized_jeevika_jankar_id"
    t.index "lower(btrim(month))", name: "index_module_other_targets_on_normalized_month"
    t.index "lower(btrim(target_mapping_id))", name: "index_module_other_targets_on_normalized_target_mapping_id"
    t.index ["active"], name: "index_module_other_targets_on_active"
    t.index ["created_at"], name: "index_module_other_targets_on_created_at"
    t.index ["month"], name: "index_module_other_targets_on_month"
    t.index ["target_mapping_id"], name: "index_module_other_targets_on_target_mapping_id"
  end

  create_table "module_parent_offices", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "office_level", type: :text, as: "NULLIF(btrim((data ->> 'office_level'::text)), ''::text)", stored: true
    t.virtual "parent_office", type: :text, as: "NULLIF(btrim((data ->> 'parent_office'::text)), ''::text)", stored: true
    t.virtual "parent_office_name", type: :text, as: "NULLIF(btrim((data ->> 'parent_office_name'::text)), ''::text)", stored: true
    t.virtual "parent_office_type", type: :text, as: "NULLIF(btrim((data ->> 'parent_office_type'::text)), ''::text)", stored: true
    t.virtual "stakeholder_category", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(office_level))", name: "index_module_parent_offices_on_normalized_office_level"
    t.index "lower(btrim(parent_office))", name: "index_module_parent_offices_on_normalized_parent_office"
    t.index "lower(btrim(parent_office_name))", name: "index_module_parent_offices_on_normalized_parent_office_name"
    t.index "lower(btrim(parent_office_type))", name: "index_module_parent_offices_on_normalized_parent_office_type"
    t.index "lower(btrim(stakeholder_category))", name: "index_module_parent_offices_on_normalized_stakeholder_category"
    t.index ["active"], name: "index_module_parent_offices_on_active"
    t.index ["created_at"], name: "index_module_parent_offices_on_created_at"
    t.index ["parent_office_name"], name: "index_module_parent_offices_on_parent_office_name"
    t.index ["stakeholder_category", "office_level"], name: "idx_on_stakeholder_category_office_level_5bb4cc8ce0"
  end

  create_table "module_payment_details", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text]))))", stored: true
    t.virtual "bill_month", type: :text, as: "NULLIF(btrim((data ->> 'bill_month'::text)), ''::text)", stored: true
    t.virtual "bill_status", type: :text, as: "NULLIF(btrim((data ->> 'status'::text)), ''::text)", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "select_vrp", type: :text, as: "NULLIF(btrim((data ->> 'select_vrp'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(bill_month))", name: "index_module_payment_details_on_normalized_bill_month"
    t.index "lower(btrim(bill_status))", name: "index_module_payment_details_on_normalized_bill_status"
    t.index "lower(btrim(select_vrp))", name: "index_module_payment_details_on_normalized_select_vrp"
    t.index ["active"], name: "index_module_payment_details_on_active"
    t.index ["bill_month"], name: "index_module_payment_details_on_bill_month"
    t.index ["created_at"], name: "index_module_payment_details_on_created_at"
  end

  create_table "module_projects", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "project_name", type: :text, as: "NULLIF(btrim((data ->> 'project_name'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(project_name))", name: "index_module_projects_on_normalized_project_name"
    t.index ["active"], name: "index_module_projects_on_active"
    t.index ["created_at"], name: "index_module_projects_on_created_at"
    t.index ["project_name"], name: "index_module_projects_on_project_name"
  end

  create_table "module_record_read_versions", primary_key: "source_key", id: :string, force: :cascade do |t|
    t.bigint "revision", null: false
  end

  create_table "module_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "data", null: false
    t.string "module_slug", null: false
    t.datetime "updated_at", null: false
    t.index "(((data)::jsonb ->> 'bill_id'::text))", name: "index_jj_bill_history_on_bill_id", where: "((module_slug)::text = 'jeevika-jankar-bill-approval-history'::text)"
    t.index "(((data)::jsonb ->> 'mobile_no'::text))", name: "index_module_records_new_users_on_mobile_no", where: "((module_slug)::text = 'new-user'::text)"
    t.index "(((data)::jsonb ->> 'record_id'::text))", name: "index_training_edits_on_record_id", where: "((module_slug)::text = 'training-form-edit-request'::text)"
    t.index "(((data)::jsonb ->> 'record_id'::text)), id DESC", name: "index_training_edits_on_record_id_and_latest_id", where: "((module_slug)::text = 'training-form-edit-request'::text)"
    t.index "(((data)::jsonb ->> 'status'::text))", name: "index_training_edits_on_status", where: "((module_slug)::text = 'training-form-edit-request'::text)"
    t.index "(((data)::jsonb ->> 'status'::text)), id DESC", name: "index_training_edits_on_status_and_latest_id", where: "((module_slug)::text = 'training-form-edit-request'::text)"
    t.index "(((data)::jsonb ->> 'user_name'::text)), updated_at DESC", name: "index_module_records_new_users_on_user_name_and_updated_at", where: "((module_slug)::text = 'new-user'::text)"
    t.index "(((data)::jsonb ->> 'village_code'::text))", name: "index_module_records_village_code_lookup", where: "((module_slug)::text = ANY (ARRAY[('village-master'::character varying)::text, ('lg-directory-list'::character varying)::text]))"
    t.index "(((data)::jsonb ->> 'village_id'::text))", name: "index_module_records_village_id_lookup", where: "((module_slug)::text = ANY (ARRAY[('village-master'::character varying)::text, ('lg-directory-list'::character varying)::text]))"
    t.index "((data)::jsonb)", name: "index_module_records_on_json_data", using: :gin
    t.index "lower(((data)::jsonb ->> 'email'::text))", name: "index_module_records_new_users_on_lower_email", where: "((module_slug)::text = 'new-user'::text)"
    t.index "lower(((data)::jsonb ->> 'user_name'::text))", name: "index_module_records_new_users_on_lower_user_name", where: "((module_slug)::text = 'new-user'::text)"
    t.index "module_slug, (((data)::jsonb ->> 'bill_month'::text))", name: "index_jj_bills_on_module_slug_and_bill_month", where: "((module_slug)::text = 'jeevika-jankar-bill-process'::text)"
    t.index "module_slug, lower(btrim(((data)::jsonb ->> 'month'::text)))", name: "index_module_records_on_slug_normalized_month"
    t.index "module_slug, lower(btrim(((data)::jsonb ->> 'month'::text))), created_at DESC", name: "index_module_records_active_slug_month_created_at", where: "((COALESCE(lower(btrim(((data)::jsonb ->> 'deleted'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND (COALESCE(lower(btrim(((data)::jsonb ->> 'is_deleted'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND (COALESCE(lower(btrim(((data)::jsonb ->> 'discarded'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND ((COALESCE(btrim(((data)::jsonb ->> 'status'::text)), ''::text) = ''::text) OR (lower(btrim(((data)::jsonb ->> 'status'::text))) = 'active'::text)))"
    t.index ["module_slug", "created_at"], name: "index_module_records_on_active_catalogue", order: { created_at: :desc }, where: "((COALESCE(lower(btrim(((data)::jsonb ->> 'deleted'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND (COALESCE(lower(btrim(((data)::jsonb ->> 'is_deleted'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND (COALESCE(lower(btrim(((data)::jsonb ->> 'discarded'::text))), ''::text) <> ALL (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) AND ((COALESCE(btrim(((data)::jsonb ->> 'status'::text)), ''::text) = ''::text) OR (lower(btrim(((data)::jsonb ->> 'status'::text))) = 'active'::text)))"
    t.index ["module_slug", "created_at"], name: "index_module_records_on_slug_and_created_at", order: { created_at: :desc }
    t.index ["module_slug", "updated_at"], name: "index_module_records_on_slug_and_updated_at", order: { updated_at: :desc }
    t.index ["module_slug"], name: "index_module_records_on_module_slug"
    t.index ["updated_at"], name: "index_module_records_on_updated_at", order: :desc
  end

  create_table "module_roles", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "role_name", type: :text, as: "NULLIF(btrim((data ->> 'role_name'::text)), ''::text)", stored: true
    t.virtual "stakeholder_category", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)", stored: true
    t.virtual "stakeholder_role", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_role'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(role_name))", name: "index_module_roles_on_normalized_role_name"
    t.index "lower(btrim(stakeholder_category))", name: "index_module_roles_on_normalized_stakeholder_category"
    t.index "lower(btrim(stakeholder_role))", name: "index_module_roles_on_normalized_stakeholder_role"
    t.index ["active"], name: "index_module_roles_on_active"
    t.index ["created_at"], name: "index_module_roles_on_created_at"
    t.index ["role_name"], name: "index_module_roles_on_role_name"
    t.index ["stakeholder_category", "stakeholder_role"], name: "idx_on_stakeholder_category_stakeholder_role_5f7f62ad08"
  end

  create_table "module_stakeholder_roles", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "stakeholder_category", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)", stored: true
    t.virtual "stakeholder_role", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_role'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(stakeholder_category))", name: "index_module_stakeholder_roles_on_normalized_stakeholder_catego"
    t.index "lower(btrim(stakeholder_role))", name: "index_module_stakeholder_roles_on_normalized_stakeholder_role"
    t.index ["active"], name: "index_module_stakeholder_roles_on_active"
    t.index ["created_at"], name: "index_module_stakeholder_roles_on_created_at"
    t.index ["stakeholder_category", "stakeholder_role"], name: "idx_on_stakeholder_category_stakeholder_role_cd8b188480"
  end

  create_table "module_stakeholders", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "logo_upload", type: :text, as: "NULLIF(btrim((data ->> 'logo_upload'::text)), ''::text)", stored: true
    t.virtual "stakeholder_name", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_name_in_english'::text)), ''::text)", stored: true
    t.virtual "stakeholder_name_hindi", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_name_in_hindi'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(logo_upload))", name: "index_module_stakeholders_on_normalized_logo_upload"
    t.index "lower(btrim(stakeholder_name))", name: "index_module_stakeholders_on_normalized_stakeholder_name"
    t.index "lower(btrim(stakeholder_name_hindi))", name: "index_module_stakeholders_on_normalized_stakeholder_name_hindi"
    t.index ["active"], name: "index_module_stakeholders_on_active"
    t.index ["created_at"], name: "index_module_stakeholders_on_created_at"
    t.index ["stakeholder_name"], name: "index_module_stakeholders_on_stakeholder_name"
  end

  create_table "module_sub_activities", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "main_activity", type: :text, as: "NULLIF(btrim((data ->> 'main_activity'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.virtual "sub_activity_name", type: :text, as: "NULLIF(btrim((data ->> 'sub_activity_name'::text)), ''::text)", stored: true
    t.virtual "unit", type: :text, as: "NULLIF(btrim((data ->> 'unit'::text)), ''::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(main_activity))", name: "index_module_sub_activities_on_normalized_main_activity"
    t.index "lower(btrim(sub_activity_name))", name: "index_module_sub_activities_on_normalized_sub_activity_name"
    t.index "lower(btrim(unit))", name: "index_module_sub_activities_on_normalized_unit"
    t.index ["active"], name: "index_module_sub_activities_on_active"
    t.index ["created_at"], name: "index_module_sub_activities_on_created_at"
    t.index ["main_activity", "sub_activity_name"], name: "idx_on_main_activity_sub_activity_name_7a91dcb2a3"
  end

  create_table "module_sub_offices", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "office_level", type: :text, as: "NULLIF(btrim((data ->> 'office_level'::text)), ''::text)", stored: true
    t.virtual "office_name", type: :text, as: "NULLIF(btrim((data ->> 'office_name'::text)), ''::text)", stored: true
    t.virtual "parent_category", type: :text, as: "NULLIF(btrim((data ->> 'parent_category'::text)), ''::text)", stored: true
    t.virtual "stakeholder_category", type: :text, as: "NULLIF(btrim((data ->> 'stakeholder_category'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.virtual "sub_office_name", type: :text, as: "NULLIF(btrim((data ->> 'sub_office_name'::text)), ''::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(office_level))", name: "index_module_sub_offices_on_normalized_office_level"
    t.index "lower(btrim(office_name))", name: "index_module_sub_offices_on_normalized_office_name"
    t.index "lower(btrim(parent_category))", name: "index_module_sub_offices_on_normalized_parent_category"
    t.index "lower(btrim(stakeholder_category))", name: "index_module_sub_offices_on_normalized_stakeholder_category"
    t.index "lower(btrim(sub_office_name))", name: "index_module_sub_offices_on_normalized_sub_office_name"
    t.index ["active"], name: "index_module_sub_offices_on_active"
    t.index ["created_at"], name: "index_module_sub_offices_on_created_at"
    t.index ["office_name", "sub_office_name"], name: "index_module_sub_offices_on_office_name_and_sub_office_name"
    t.index ["parent_category"], name: "index_module_sub_offices_on_parent_category"
  end

  create_table "module_trainings", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.virtual "cluster_coordinator_name", type: :text, as: "NULLIF(btrim((data ->> 'cluster_coordinator_name'::text)), ''::text)", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "jeevika_jankar_id", type: :text, as: "NULLIF(btrim((data ->> 'jeevika_jankar_id'::text)), ''::text)", stored: true
    t.virtual "main_activity", type: :text, as: "NULLIF(btrim((data ->> 'main_activity'::text)), ''::text)", stored: true
    t.virtual "main_activity_type", type: :text, as: "NULLIF(btrim((data ->> 'main_activity_type'::text)), ''::text)", stored: true
    t.virtual "month", type: :text, as: "NULLIF(btrim((data ->> 'month'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.virtual "sub_activity", type: :text, as: "NULLIF(btrim((data ->> 'sub_activity'::text)), ''::text)", stored: true
    t.virtual "training_method", type: :text, as: "NULLIF(btrim((data ->> 'training_method'::text)), ''::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim((data ->> 'month'::text))), created_at DESC", name: "index_module_trainings_on_payload_month_and_created"
    t.index "lower(btrim(cluster_coordinator_name))", name: "index_module_trainings_on_normalized_cluster_coordinator_name"
    t.index "lower(btrim(jeevika_jankar_id))", name: "index_module_trainings_on_normalized_jeevika_jankar_id"
    t.index "lower(btrim(main_activity))", name: "index_module_trainings_on_normalized_main_activity"
    t.index "lower(btrim(main_activity_type))", name: "index_module_trainings_on_normalized_main_activity_type"
    t.index "lower(btrim(month))", name: "index_module_trainings_on_normalized_month"
    t.index "lower(btrim(sub_activity))", name: "index_module_trainings_on_normalized_sub_activity"
    t.index "lower(btrim(training_method))", name: "index_module_trainings_on_normalized_training_method"
    t.index ["active"], name: "index_module_trainings_on_active"
    t.index ["created_at"], name: "index_module_trainings_on_created_at"
    t.index ["jeevika_jankar_id", "month"], name: "index_module_trainings_on_jeevika_jankar_id_and_month"
    t.index ["main_activity_type"], name: "index_module_trainings_on_main_activity_type"
    t.index ["month", "training_method"], name: "index_module_trainings_on_month_and_training_method"
  end

  create_table "module_user_hierarchies", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "level_1_user", type: :text, as: "NULLIF(btrim((data ->> 'level_1_user'::text)), ''::text)", stored: true
    t.virtual "level_2_user", type: :text, as: "NULLIF(btrim((data ->> 'level_2_user'::text)), ''::text)", stored: true
    t.virtual "level_3_user", type: :text, as: "NULLIF(btrim((data ->> 'level_3_user'::text)), ''::text)", stored: true
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.index "lower(btrim(level_1_user))", name: "index_module_user_hierarchies_on_normalized_level_1_user"
    t.index "lower(btrim(level_2_user))", name: "index_module_user_hierarchies_on_normalized_level_2_user"
    t.index "lower(btrim(level_3_user))", name: "index_module_user_hierarchies_on_normalized_level_3_user"
    t.index ["active"], name: "index_module_user_hierarchies_on_active"
    t.index ["created_at"], name: "index_module_user_hierarchies_on_created_at"
    t.index ["level_1_user"], name: "index_module_user_hierarchies_on_level_1_user"
  end

  create_table "module_vrp_types", id: :bigint, default: nil, force: :cascade do |t|
    t.virtual "active", type: :boolean, as: "(NOT ((COALESCE(lower(btrim((data ->> 'deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'is_deleted'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR (COALESCE(lower(btrim((data ->> 'discarded'::text))), ''::text) = ANY (ARRAY['1'::text, 'true'::text, 'yes'::text, 'deleted'::text])) OR ((COALESCE(btrim((data ->> 'status'::text)), ''::text) <> ''::text) AND (lower(btrim((data ->> 'status'::text))) <> 'active'::text))))", stored: true
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.virtual "status", type: :text, as: "(data ->> 'status'::text)", stored: true
    t.datetime "updated_at", null: false
    t.virtual "vrp_type_name", type: :text, as: "NULLIF(btrim((data ->> 'vrp_type_name'::text)), ''::text)", stored: true
    t.index "lower(btrim(vrp_type_name))", name: "index_module_vrp_types_on_normalized_vrp_type_name"
    t.index ["active"], name: "index_module_vrp_types_on_active"
    t.index ["created_at"], name: "index_module_vrp_types_on_created_at"
  end

  create_table "target_mappings", force: :cascade do |t|
    t.string "activity_name", null: false
    t.text "afl_ids", default: "[]", null: false
    t.decimal "cc_target", precision: 18, scale: 4
    t.date "completion_date"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "created_by_type"
    t.integer "farmer_count", default: 0, null: false
    t.string "fco_id", null: false
    t.string "fco_name"
    t.decimal "ffs_target", precision: 18, scale: 4
    t.string "ics_id", null: false
    t.string "ics_name"
    t.decimal "input_demo_inm_target", precision: 18, scale: 4
    t.decimal "input_demo_pm_target", precision: 18, scale: 4
    t.string "main_activity_name"
    t.string "month_name", null: false
    t.decimal "opg_training_target", precision: 18, scale: 4
    t.string "target_entry_mode", default: "ics_wise", null: false
    t.decimal "target_quantity", precision: 18, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.string "village_id", null: false
    t.string "village_name"
    t.bigint "vrp_ics_mapping_id"
    t.bigint "vrp_id", null: false
    t.integer "week_1_target"
    t.integer "week_2_target"
    t.integer "week_3_target"
    t.integer "week_4_target"
    t.decimal "week_wise_opg_target", precision: 18, scale: 4
    t.index "lower(btrim((month_name)::text))", name: "index_target_mappings_on_normalized_month"
    t.index "vrp_id, lower(btrim((month_name)::text))", name: "index_target_mappings_on_owner_normalized_month"
    t.index ["created_by_type", "created_by_id", "updated_at"], name: "index_target_mappings_on_creator_and_updated_at", order: { updated_at: :desc }
    t.index ["created_by_type", "created_by_id"], name: "index_target_mappings_on_creator"
    t.index ["fco_id", "ics_id", "village_id", "main_activity_name", "activity_name"], name: "index_target_mappings_on_activity_scope"
    t.index ["target_entry_mode", "month_name"], name: "index_target_mappings_on_entry_mode_and_month"
    t.index ["updated_at"], name: "index_target_mappings_on_updated_at", order: :desc
    t.index ["village_id"], name: "index_target_mappings_on_village_id_for_agreements"
    t.index ["vrp_ics_mapping_id"], name: "index_target_mappings_on_vrp_ics_mapping_id"
    t.index ["vrp_id", "updated_at"], name: "index_target_mappings_on_vrp_and_updated_at", order: { updated_at: :desc }
    t.index ["vrp_id", "vrp_ics_mapping_id", "month_name", "activity_name"], name: "index_target_mappings_on_scope"
    t.index ["vrp_id"], name: "index_target_mappings_on_vrp_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "age"
    t.string "block"
    t.datetime "created_at", null: false
    t.string "district"
    t.string "email"
    t.string "emergency_no"
    t.string "first_name"
    t.text "full_address"
    t.string "gender"
    t.string "gram_panchayat"
    t.string "ics"
    t.string "last_name"
    t.string "mobile_no"
    t.string "office"
    t.string "office_category"
    t.string "office_name"
    t.string "parent_office"
    t.string "password"
    t.string "person_type"
    t.string "pincode"
    t.string "role"
    t.string "role_name"
    t.string "stakeholder"
    t.string "stakeholder_role"
    t.string "state"
    t.string "status", default: "Active", null: false
    t.string "sub_office_name"
    t.datetime "updated_at", null: false
    t.string "user_management_role"
    t.string "user_name", null: false
    t.string "user_type"
    t.string "village"
    t.index "lower((email)::text)", name: "index_users_on_lower_email"
    t.index "lower((user_name)::text)", name: "index_users_on_lower_user_name"
    t.index ["email"], name: "index_users_on_email"
    t.index ["mobile_no"], name: "index_users_on_mobile_no"
    t.index ["updated_at"], name: "index_users_on_updated_at_desc", order: :desc
    t.index ["user_name"], name: "index_users_on_user_name"
  end

  create_table "vrp_bank_masters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_deleted", default: false, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "vrp_ics_mappings", force: :cascade do |t|
    t.text "afl_ids", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "created_by_type"
    t.string "fco_id", null: false
    t.string "fco_name"
    t.string "ics_id", null: false
    t.string "ics_name"
    t.datetime "updated_at", null: false
    t.string "village_id", null: false
    t.string "village_name"
    t.bigint "vrp_id", null: false
    t.index ["created_by_type", "created_by_id"], name: "index_vrp_ics_mappings_on_creator"
    t.index ["village_id"], name: "index_vrp_ics_mappings_on_village_id_for_agreements"
    t.index ["vrp_id", "fco_id", "ics_id", "village_id"], name: "index_vrp_ics_mappings_on_mapping_scope", unique: true
    t.index ["vrp_id"], name: "index_vrp_ics_mappings_on_vrp_id"
  end

  create_table "vrp_profiles", force: :cascade do |t|
    t.string "block_id", null: false
    t.datetime "created_at", null: false
    t.string "district_id", null: false
    t.string "gram_panchayat_id", null: false
    t.string "state_id", null: false
    t.datetime "updated_at", null: false
    t.string "village_id", null: false
    t.integer "vrp_id", null: false
    t.index ["vrp_id"], name: "index_vrp_profiles_on_vrp_id"
  end

  create_table "vrp_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_deleted", default: false, null: false
    t.string "type_name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "vrps", force: :cascade do |t|
    t.string "aadhar_no", null: false
    t.string "account_no", null: false
    t.text "address", null: false
    t.datetime "agreement_accepted_at"
    t.text "agreement_signature_data"
    t.string "bank_name"
    t.string "branch", null: false
    t.string "cluster_incharge"
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.string "created_by_type"
    t.date "date_of_birth", null: false
    t.date "date_of_joining", null: false
    t.string "email", null: false
    t.string "emergency_no"
    t.integer "experience_in_years", null: false
    t.string "father_husband_name", null: false
    t.string "fcoc"
    t.integer "gender", null: false
    t.text "gram_panchayat_ids"
    t.text "ics_master_ids"
    t.string "ifsc_code", null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_deleted", default: false, null: false
    t.string "mobile_no", null: false
    t.string "name", null: false
    t.integer "office_detail_id", null: false
    t.string "password"
    t.string "person_type"
    t.text "project_master_ids"
    t.string "role"
    t.string "stakeholder"
    t.string "stakeholder_role"
    t.integer "status", default: 25, null: false
    t.string "to_name"
    t.integer "to_office_detail_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "user_management_role"
    t.string "user_name"
    t.text "village_ids"
    t.integer "vrp_bank_master_id"
    t.text "vrp_type_ids"
    t.index "lower((email)::text)", name: "index_vrps_on_lower_email"
    t.index "lower((user_name)::text)", name: "index_vrps_on_lower_user_name"
    t.index ["aadhar_no"], name: "index_vrps_on_aadhar_no"
    t.index ["agreement_accepted_at"], name: "index_vrps_on_agreement_accepted_at"
    t.index ["cluster_incharge"], name: "index_vrps_on_cluster_incharge"
    t.index ["created_by_id"], name: "index_vrps_on_created_by_id"
    t.index ["created_by_type", "created_by_id"], name: "index_vrps_on_created_by_type_and_created_by_id"
    t.index ["email"], name: "index_vrps_on_email"
    t.index ["fcoc"], name: "index_vrps_on_fcoc"
    t.index ["mobile_no"], name: "index_vrps_on_mobile_no"
    t.index ["status"], name: "index_vrps_on_status"
    t.index ["to_name"], name: "index_vrps_on_to_name"
    t.index ["updated_at"], name: "index_vrps_on_updated_at", order: :desc
    t.index ["user_id"], name: "index_vrps_on_user_id"
    t.index ["user_name"], name: "index_vrps_on_user_name"
    t.index ["vrp_bank_master_id"], name: "index_vrps_on_vrp_bank_master_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "farmer_app_login_events", "farmer_app_logins"
  add_foreign_key "farmer_devices", "farmer_app_logins"
  add_foreign_key "jj_quiz_answers", "jj_quiz_attempts"
  add_foreign_key "jj_quiz_answers", "jj_quiz_questions"
  add_foreign_key "jj_quiz_attempts", "jj_quizzes"
  add_foreign_key "jj_quiz_attempts", "vrps"
  add_foreign_key "jj_quiz_questions", "jj_quizzes"
  add_foreign_key "target_mappings", "vrp_ics_mappings"
  add_foreign_key "target_mappings", "vrps"
  add_foreign_key "vrp_ics_mappings", "vrps"
  add_foreign_key "vrp_profiles", "vrps"
  add_foreign_key "vrps", "vrp_bank_masters"
end
