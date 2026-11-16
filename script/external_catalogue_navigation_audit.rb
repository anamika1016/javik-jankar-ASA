# Rollback-only HTTP audit with simulated upstream delay, no actual HTTP.
abort "Use isolated test DB" unless Rails.env.test? && ActiveRecord::Base.connection.current_database.start_with?("jj_performance_test_")
require "net/http"
Net::HTTP.prepend(Module.new do
  private
  def connect
    raise SocketError, "External HTTP disabled for synthetic audit"
  end
end)
cases = [
  { name: :jj_users, type: TargetMappingsController, reader: :fetch_external_vrp_users,
    data: [{ id: "1", name: "Audit JJ", mobile_no: "9000000001", label: "Audit JJ (9000000001)" }],
    page: "/jj-mapped-farmers", fallback: { load_users: "1" }, frame_url: "/target_mappings/jj_user_options", frame: "jj_api_user_picker" },
  { name: :offices, type: ModulesController, reader: :office_list_api_items,
    data: [{ "id" => "41", "name" => "Audit Office", "territory_zones" => [] }],
    page: "/modules/office-list", fallback: { load_offices: "1" }, frame_url: "/modules/office-list", frame: "office_list_content" }
]
originals = cases.map { |item| [item[:type], item[:reader], item[:type].instance_method(item[:reader])] }
measure = lambda do |&block|
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  block.call
  ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
end
report = { note: "Synthetic 250ms upstream delay; page and frame measured separately; not production timing", cases: [] }
begin
  ActiveRecord::Base.transaction do
    viewer = User.create!(user_name: "navigation_audit_admin", password: "audit-secret", first_name: "Audit", user_type: "admin", status: "Active")
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post("/login", params: { login: viewer.user_name, password: "audit-secret" })
    cases.each do |item|
      calls = 0
      item[:type].send(:define_method, item[:reader]) { calls += 1; sleep 0.25; item[:data] }
      item[:type].send(:private, item[:reader])
      extract = lambda do |body|
        doc = Nokogiri::HTML(body)
        if item[:name] == :jj_users
          doc.css('select[name="mobile_no"] option').map { |option| [option["value"], option.text.squish] }
        else
          doc.css('#office_detail_list th, #office_detail_list td').map { |cell| cell.text.squish }
        end
      end
      # Compile both paths before timing.
      session.get(item[:page], params: item[:fallback])
      session.get(item[:frame_url], headers: { "Turbo-Frame" => item[:frame] })
      before_ms = measure.call { session.get(item[:page], params: item[:fallback]) }
      raise "Reference failed" unless session.response.status == 200
      expected = extract.call(session.response.body)
      calls_before = calls
      after_ms = measure.call { session.get(item[:page]) }
      raise "Page waited for remote catalogue" unless calls == calls_before && session.response.status == 200
      raise "Missing independent frame" unless Nokogiri::HTML(session.response.body).at_css("turbo-frame##{item[:frame]}[src]")
      frame_ms = measure.call { session.get(item[:frame_url], headers: { "Turbo-Frame" => item[:frame] }) }
      raise "Loaded data changed" unless extract.call(session.response.body) == expected && session.response.status == 200
      report[:cases] << { name: item[:name], synchronous_page_ms: before_ms, initial_page_ms: after_ms,
        deferred_content_ms: frame_ms, initial_page_remote_calls: 0, loaded_data_equal: true }
    end
    raise ActiveRecord::Rollback
  end
ensure
  originals.each do |type, name, method|
    type.send(:define_method, name, method)
    type.send(:private, name)
  end
end
puts JSON.pretty_generate(report)
