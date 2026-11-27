class IndexDedicatedModulePayloadLookups < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # The writable compatibility view exposes payload_text as data. Index that
  # exact expression for histories/auth; the JSONB read-view indexes remain too.
  INDEXES = {
    "training-form-edit-request" => {
      "index_entry_edits_on_record_and_latest" => "(payload_text::jsonb ->> 'record_id'), id DESC",
      "index_entry_edits_on_status_and_latest" => "(payload_text::jsonb ->> 'status'), id DESC"
    },
    "jeevika-jankar-bill-approval-history" => {
      "index_entry_bill_history_on_bill_and_order" => "(payload_text::jsonb ->> 'bill_id'), created_at, id"
    },
    "vrp-approval-history" => {
      "index_entry_vrp_history_on_owner_and_order" => "(payload_text::jsonb ->> 'vrp_id'), created_at, id"
    },
    "new-user" => {
      "index_entry_users_on_lower_username" => "LOWER(payload_text::jsonb ->> 'user_name')",
      "index_entry_users_on_normalized_username" => "LOWER(BTRIM(COALESCE(payload_text::jsonb ->> 'user_name', '')))",
      "index_entry_users_on_lower_email" => "LOWER(payload_text::jsonb ->> 'email')",
      "index_entry_users_on_normalized_email" => "LOWER(BTRIM(payload_text::jsonb ->> 'email'))",
      "index_entry_users_on_mobile" => "(payload_text::jsonb ->> 'mobile_no')",
      "index_entry_users_on_username_and_updated" => "(payload_text::jsonb ->> 'user_name'), updated_at DESC"
    }
  }.freeze

  def up
    INDEXES.each do |slug, indexes|
      table = select_value("SELECT table_name FROM module_entry_sources WHERE slug = #{connection.quote(slug)}")
      raise "Missing dedicated source #{slug}" unless table
      indexes.each do |name, expression|
        add_index table, expression, name: name, algorithm: :concurrently, if_not_exists: true
      end
    end
  end

  def down
    INDEXES.each do |slug, indexes|
      table = select_value("SELECT table_name FROM module_entry_sources WHERE slug = #{connection.quote(slug)}")
      indexes.each_key { |name| remove_index table, name: name, algorithm: :concurrently, if_exists: true } if table
    end
  end
end
