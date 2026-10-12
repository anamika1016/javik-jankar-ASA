# Read-only production check. Optional: MONTH=September FCO=Bhawanipatna USER_ID=123
require "action_dispatch/testing/test_request"
controller = DashboardReportsController.new
controller.request = ActionDispatch::TestRequest.create
month = ENV.fetch("MONTH", DashboardDefaults.month)
controller.params = ActionController::Parameters.new(month: month, fcoc: ENV["FCO"])
user = User.find(ENV["USER_ID"]) if ENV["USER_ID"].present?
payload = if user
  { "id" => user.id, "record_type" => "User", "user_type" => user.user_type,
    "role" => user.role, "name" => user.full_name, "username" => user.user_name,
    "office_name" => user.office_name, "office" => user.office }
else
  { "record_type" => "User", "user_type" => "Admin", "role" => "Admin" }
end
controller.instance_variable_set(:@current_app_user, payload)
selected_month = month.blank? || month.casecmp("all").zero? ? nil : month
rows = controller.send(:farmer_training_attendance_counts_by_fco, month_name: selected_month, fcoc_name: ENV["FCO"])
mapped, = controller.send(:farmer_training_mapped_farmer_count_and_popups, month_name: selected_month, fcoc_name: ENV["FCO"])
records = ModuleRecord.where(module_slug: "training-form")
records = records.where("LOWER(TRIM(data::jsonb ->> 'month')) = ?", selected_month.downcase) if selected_month
puts({ month: selected_month || "All Months", role: payload["role"],
  fco_ids: controller.send(:training_fcoc_ids_from_param, ENV["FCO"]), mapped: mapped,
  farmer_population: rows.sum { |row| row["total_farmer_count"].to_i },
  pending: rows.sum { |row| row["red_farmer_count"].to_i },
  only_one_training: rows.sum { |row| row["yellow_count"].to_i },
  repeat_training: rows.sum { |row| row["green_count"].to_i },
  training_rows: records.count,
  visible_farmer_rows: controller.send(:dashboard_visible_farmer_scope).count,
  visible_farmers_missing_fco_id: controller.send(:dashboard_visible_farmer_scope)
    .where("NULLIF(BTRIM(fco_id), '') IS NULL").count,
  farmer_id_field_types: records.group(Arel.sql("COALESCE(jsonb_typeof(data::jsonb -> 'selected_farmer_ids'), 'missing')")).count
}.to_json)
