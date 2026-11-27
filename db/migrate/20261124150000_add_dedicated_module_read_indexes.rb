class AddDedicatedModuleReadIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Generated columns trim their values. Existing filters deliberately inspect
  # the original payload (including whitespace), so index those exact JSONB
  # expressions rather than changing filter semantics to fit a different index.
  INDEXES = {
    module_trainings: {
      "index_module_trainings_on_payload_month_and_created" => "LOWER(BTRIM(data ->> 'month')), created_at DESC"
    },
    module_bills: {
      "index_module_bills_on_payload_month" => "(data ->> 'bill_month')",
      "index_module_bills_on_payload_owner_month" => "(data ->> 'select_vrp'), (data ->> 'bill_month')"
    },
    module_other_targets: {
      "index_module_other_targets_on_payload_month" => "LOWER(BTRIM(data ->> 'month'))"
    },
    module_other_farmer_targets: {
      "index_module_other_farmer_targets_on_payload_month" => "LOWER(BTRIM(data ->> 'month'))"
    }
  }.freeze

  def up
    INDEXES.each do |table, indexes|
      indexes.each do |name, expression|
        add_index table, expression, name: name, algorithm: :concurrently, if_not_exists: true
      end
    end
  end

  def down
    INDEXES.each do |table, indexes|
      indexes.each_key do |name|
        remove_index table, name: name, algorithm: :concurrently, if_exists: true
      end
    end
  end
end
