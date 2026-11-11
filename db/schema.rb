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

ActiveRecord::Schema[8.1].define(version: 2026_11_11_140000) do
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
    t.index "(((data)::jsonb ->> 'village_code'::text))", name: "index_module_records_village_code_lookup", where: "((module_slug)::text = ANY ((ARRAY['village-master'::character varying, 'lg-directory-list'::character varying])::text[]))"
    t.index "(((data)::jsonb ->> 'village_id'::text))", name: "index_module_records_village_id_lookup", where: "((module_slug)::text = ANY ((ARRAY['village-master'::character varying, 'lg-directory-list'::character varying])::text[]))"
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
    t.integer "block_id", null: false
    t.datetime "created_at", null: false
    t.integer "district_id", null: false
    t.integer "gram_panchayat_id", null: false
    t.integer "state_id", null: false
    t.datetime "updated_at", null: false
    t.integer "village_id", null: false
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
