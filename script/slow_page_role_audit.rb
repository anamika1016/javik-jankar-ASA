# Run with RAILS_ENV=test bundle exec rails runner script/slow_page_role_audit.rb.
# Reads use synthetic local data, which is rolled back. External HTTP is disabled.
require "net/http"
abort "Use an isolated test database" unless Rails.env.test?
Net::HTTP.singleton_class.prepend(Module.new do
  def start(*)
    raise SocketError, "External HTTP disabled for role performance audit"
  end
end)

report = { environment: Rails.env, external_http: false, requests: [], api_inventory: [] }
Rails.application.routes.routes.each do |route|
  path = route.path.spec.to_s.delete_suffix("(.:format)")
  next unless path.start_with?("/api/")
  report[:api_inventory] << { method: route.verb, path: path }
end

def audit_request(session, report, role, path, params: {}, headers: {})
  queries = 0
  db_ms = 0.0
  callback = lambda do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    next if %w[SCHEMA TRANSACTION].include?(event.payload[:name]) || event.payload[:cached]
    queries += 1
    db_ms += event.duration
  end
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  allocated = GC.stat(:total_allocated_objects)
  ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
    session.get(path, params: params, headers: headers)
  end
  report[:requests] << { role: role, path: path, status: session.response.status,
    ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
    db_ms: db_ms.round(2), queries: queries, allocations: GC.stat(:total_allocated_objects) - allocated,
    bytes: session.response.body.bytesize }
rescue StandardError => error
  report[:requests] << { role: role, path: path, error: "#{error.class}: #{error.message.lines.first.to_s.strip}" }
end

ActiveRecord::Base.transaction do
  admin = User.create!(user_name: "role_audit_admin", password: "audit-secret", first_name: "Audit",
    user_type: "admin", status: "Active", role: "Admin")
  staff = User.create!(user_name: "role_audit_staff", password: "audit-secret", first_name: "Audit Staff",
    user_type: "User", status: "Active", role: "Agronomist", office_name: "FCO-Role Audit")
  type = VrpType.create!(type_name: "Role Audit JJ")
  vrp = Vrp.new(name: "Role Audit JJ", user_name: "role_audit_jj", password: "audit-secret",
    father_husband_name: "Audit", gender: 1, date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
    aadhar_no: "123456789012", account_no: "123", bank_name: "Audit", branch: "Audit", ifsc_code: "TEST0123456",
    address: "Audit", mobile_no: "9876543210", email: "role-audit@example.test", experience_in_years: 1,
    office_detail_id: 0, to_office_detail_id: 0, fcoc: "FCO-Role Audit", vrp_type_ids: [type.id],
    village_ids: ["audit-village"], gram_panchayat_ids: ["audit-gp"], status: 55,
    agreement_accepted_at: Time.current, agreement_signature_data: "data:image/png;base64," + "x" * 100_000)
  vrp.save!(validate: false)
  labels = ["Training Form", "Training Form List", "Other Target", "Other Target List",
    "Other Target with Farmer", "Other Target with Farmer List", "Dashboard", "Bill Process", "Bill List",
    "Payment List", "Completed Payment List"]
  ModuleRecord.create!(module_slug: "access-control", data: { "sub_module_names" => labels,
    "jeevika_jankar_type" => type.type_name, "can_view" => "Yes", "status" => "Active" })
  farmers = 30.times.map do |i|
    Afl.create!(farmer_name: "Role Audit Farmer #{i}", fco_id: "audit", fco: "Role Audit",
      ics_id: "audit-ics", ics_name: "Audit ICS", village_id: "audit-village", village_name: "Audit Village")
  end
  targets = 30.times.map do |i|
    TargetMapping.create!(vrp: vrp, fco_id: "audit", fco_name: "Role Audit", ics_id: "audit-ics",
      ics_name: "Audit ICS", village_id: "audit-village", village_name: "Audit Village",
      month_name: "October", main_activity_name: "Farmers' Training", activity_name: "Topic #{i}",
      target_quantity: 1, farmer_count: 1, afl_ids: [farmers[i].id], completion_date: Date.new(2026, 10, 31))
  end
  training_records = targets.first(15).each_with_index.map do |target, i|
    ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October", "status" => "Active",
      "target_mapping_id" => target.id.to_s, "selected_farmer_ids" => [farmers[i].id.to_s],
      "main_activity" => target.main_activity_name, "sub_activity" => target.activity_name,
      "training_date" => "2026-10-02", "vrp_id" => vrp.id.to_s,
      "created_by_type" => "Vrp", "created_by_id" => vrp.id.to_s })
  end
  detail_data = { "target_mapping_id" => targets.first.id.to_s, "month" => "October", "status" => "Active",
    "jeevika_jankar_id" => vrp.id.to_s, "jeevika_jankar_name" => vrp.name,
    "ics" => "Audit ICS", "village" => "Audit Village", "main_activity" => "Farmers' Training",
    "sub_activity" => "Topic 0", "achievement" => "1", "selected_farmer_ids" => [farmers.first.id.to_s],
    "created_by_type" => "Vrp", "created_by_id" => vrp.id.to_s }
  detail_ids = %w[seed-distribution-target papl360-target other-target other-target-with-farmer add-farmer-form]
    .to_h { |slug| [slug, ModuleRecord.create!(module_slug: slug, data: detail_data).id] }
  bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
    "select_vrp" => vrp.id.to_s, "select_vrp_name" => vrp.name, "bill_month" => "October",
    "financial_year" => "2026-27", "status" => "Final Approved", "grand_total" => "5000.00",
    "bill_items" => [{ "target_mapping_id" => targets.first.id.to_s, "vrp_id" => vrp.id.to_s,
      "main_activity" => "Farmers' Training", "activity" => "Topic 0", "assigned_count" => 1,
      "achievement_count" => 1, "total_amount" => "5000.00" }],
    "created_by_type" => "Vrp", "created_by_id" => vrp.id.to_s })
  pages = %w[/dashboard /target_mappings /modules/training-form /modules/training-form-list
    /modules/other-target /modules/other-target-list /modules/other-target-with-farmer
    /modules/other-target-with-farmer-list /modules/lg-directory-list /modules/jeevika-jankar-bill-process
    /modules/jeevika-jankar-bill-list /modules/jeevika-jankar-payment-list
    /modules/jeevika-jankar-completed-payment-list]
  static_api_paths = report[:api_inventory].select { |route| route[:method] == "GET" && !route[:path].include?(":") }
    .map { |route| route[:path] }.uniq
  dynamic_api_paths = report[:api_inventory].select { |route| route[:method] == "GET" && route[:path].include?(":id") }.map do |route|
    path = route[:path]
    id = case path
    when %r{/jeevika-jankar-bills/} then bill.id
    when %r{/jeevika-jankars/} then vrp.id
    when %r{/(training-forms|training-form-list|farmer-trainings)/} then training_records.first.id
    when %r{/seed-distribution-targets/} then detail_ids.fetch("seed-distribution-target")
    when %r{/papl360-targets/} then detail_ids.fetch("papl360-target")
    when %r{/(other-targets|other-target-list|other-forms)/} then detail_ids.fetch("other-target")
    when %r{/(other-target-with-farmers|other-target-with-farmer-list)/} then detail_ids.fetch("other-target-with-farmer")
    when %r{/add-farmer-forms/} then detail_ids.fetch("add-farmer-form")
    else raise "Add an appropriate fixture for #{path}"
    end
    path.sub(":id", id.to_s)
  end
  { admin: admin, staff: staff, jj: vrp }.each do |role, user|
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post("/login", params: { login: user.user_name, password: "audit-secret" })
    raise "#{role} login failed" unless session.response.redirect? && session.response.location.end_with?("/dashboard")
    pages.each { |path| audit_request(session, report, role, path, params: { training_month: "October" }) }
    if role == :jj
      %w[assigned_farmers assigned_target mapped_villages pending_target achieved_target main_activities sub_activities].each do |key|
        audit_request(session, report, role, "/dashboard/vrp-list/#{key}", params: { training_month: "October" })
      end
    end
    headers = { "Authorization" => "Bearer #{ApiAuthToken.encode(user)}", "Accept" => "application/json" }
    (static_api_paths + dynamic_api_paths).each do |path|
      audit_request(session, report, role, path, headers: headers,
        params: { month: "October", target_mapping_id: targets.first.id, target_mapping_ids: targets.first.id.to_s })
    end
  end
  report[:fixtures] = { jjs: 1, targets: 30, farmers: 30, training_records: 15,
    activity_records: 5, bills: 1, signature_bytes: 100_022 }
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate(report)
