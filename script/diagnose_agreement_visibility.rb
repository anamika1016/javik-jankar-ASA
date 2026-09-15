# Read-only: bundle exec rails runner script/diagnose_agreement_visibility.rb
names = ARGV.presence || ["Binit Kumar", "Vikas Meena"]
normalize = ->(value) { value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish }
users = User.all.to_a + ModuleRecord.where(module_slug: "new-user").to_a
names.each do |name|
  matches = users.select do |user|
    data = user.respond_to?(:data) ? user.data : {}
    full_name = user.respond_to?(:full_name) ? user.full_name : [data["first_name"], data["last_name"]].compact.join(" ")
    normalize.call(full_name) == normalize.call(name)
  end
  puts({ requested_user: name, matching_accounts: matches.size }.to_json)
  matches.each do |user|
    controller = VrpAgreementsController.new
    controller.request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/vrp-agreements"))
    payload = controller.send(:app_user_session_payload, user).stringify_keys
    controller.instance_variable_set(:@current_app_user, payload)
    visible = controller.send(:agreement_visible_vrps)
    puts({ user: payload.slice("id", "record_type", "name", "role", "role_name", "office_name", "parent_office", "sub_office_name"),
      visible_jjs: visible.count,
      accepted_jjs: visible.where.not(agreement_accepted_at: nil).count,
      signed_jjs: visible.where.not(agreement_accepted_at: nil).where.not(agreement_signature_data: [nil, ""]).count,
      visible_mapping_groups: visible.group(:fcoc, :cluster_incharge).count,
      signed_mapping_groups: Vrp.where.not(agreement_accepted_at: nil).where.not(agreement_signature_data: [nil, ""]).group(:fcoc, :cluster_incharge).count
    }.to_json)
  end
end
