# Full HTTP render audit. Run only against an isolated test DB; fixtures roll back.
require "json"
require "digest"
require "net/http"
require "tmpdir"
require "open3"
require "active_support/testing/time_helpers"
raise "Use test environment" unless Rails.env.test?
raise "Use isolated performance database" unless ActiveRecord::Base.connection.current_database.start_with?("jj_feature_removal_test_", "jj_performance_test_")

if ENV["RESCAN_BASELINE_REF"].present?
  baseline = ENV.fetch("RESCAN_BASELINE_REF")
  source, status = Open3.capture2("git", "show", "#{baseline}:app/controllers/modules_controller.rb")
  raise "Cannot load baseline" unless status.success?
  baseline_root = Dir.mktmpdir("jj-rescan-baseline-")
  source_file = File.join(baseline_root, "modules_controller.rb")
  File.write(source_file, source)
  load source_file
  require "fileutils"
  FileUtils.mkdir_p(File.join(baseline_root, "modules"))
  view, status = Open3.capture2("git", "show", "#{baseline}:app/views/modules/show.html.erb")
  raise "Cannot load baseline view" unless status.success?
  File.write(File.join(baseline_root, "modules/show.html.erb"), view)
  ModulesController.prepend_view_path(baseline_root)
end

if ENV["RESCAN_SCOPED_BILL_TOTALS"] == "1"
  # Exercise the mapped-owner branch for the same synthetic viewer in both
  # baseline/current runs. This never changes application authorization rules.
  ModulesController.prepend(Module.new do
    def module_mapped_vrp_scope_active?; true; end
    def module_cluster_visible_vrp_ids; (9_000_000...9_000_010).to_a; end
  end)
end

Net::HTTP.singleton_class.prepend(Module.new do
  def start(*)
    raise SocketError, "External HTTP disabled for isolated render audit"
  end
end)
Rails.cache = ActiveSupport::Cache::MemoryStore.new
report = { mode: ENV["RESCAN_BASELINE_REF"] || "working tree", database: ActiveRecord::Base.connection.current_database,
  note: "Sequential synthetic cold/warm HTTP renders; external HTTP disabled; not production latency", pages: [] }

Object.new.extend(ActiveSupport::Testing::TimeHelpers).travel_to(Time.zone.parse("2026-10-26 12:00:00")) do
  ActiveRecord::Base.transaction do
    raise "Synthetic IDs already in use" if User.exists?(id: 9_000_001) || ModuleRecord.exists?(id: 9_000_001)
    admin = User.create!(id: 9_000_001, user_name: "rescan_admin", password: "rescan-secret", first_name: "Audit", user_type: "admin", status: "Active")
    module_number = 9_000_000
    add_module = lambda do |slug, data|
      module_number += 1
      ModuleRecord.create!(id: module_number, module_slug: slug, data: data,
        created_at: Time.current - (module_number - 9_000_000).seconds,
        updated_at: Time.current - (module_number - 9_000_000).seconds)
    end
    %w[October September].each { |month| add_module.call("month-master", { "month_name" => month, "financial_year" => "2026-2027" }) }
    { "Training" => "Training", "Visit" => "Other", "Inputs" => "Other with Farmer" }.each do |activity, type|
      add_module.call("add-activity-group", { "main_activity_name" => activity, "main_activity_type" => type })
      add_module.call("add-vrp-activity", { "main_activity" => activity, "sub_activity_name" => "Work #{activity}" })
    end
    add_module.call("state-master", { "state_name" => "State", "state_code" => "01" })
    add_module.call("district-master", { "state" => "State", "district_name" => "District", "district_code" => "02" })
    add_module.call("block-master", { "state" => "State", "district" => "District", "block_name" => "Block", "block_code" => "03" })
    200.times do |number|
      add_module.call("gram-panchayat-master", { "state" => "State", "district" => "District", "block" => "Block", "gram_panchayat_name" => "Gram #{number}", "gp_code" => number.to_s })
      add_module.call("village-master", { "state" => "State", "district" => "District", "block" => "Block", "gram_panchayat" => "Gram #{number}", "gp_code" => number.to_s, "village_name" => "Village #{number}", "village_code" => "v#{number}" })
    end
    20.times do |number|
      owner = Vrp.new(id: 9_000_000 + number, name: "Audit JJ #{number}", user_name: "audit_jj_#{number}",
        aadhar_no: "123456789012", account_no: "123", address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1),
        date_of_joining: Date.current, email: "audit#{number}@example.test", experience_in_years: 0, father_husband_name: "Test",
        gender: number.even? ? 1 : 2, ifsc_code: "TEST0123456", mobile_no: "90000#{number.to_s.rjust(5, '0')}", office_detail_id: 0,
        to_office_detail_id: 0, fcoc: "FCO-C Bhawanipatna", cluster_incharge: "Audit CC", status: 55,
        agreement_signature_data: "signature" * 1000, created_at: Time.current - number.seconds, updated_at: Time.current - number.seconds)
      owner.save!(validate: false)
      farmers = 10.times.map do |index|
        Afl.create!(id: 9_000_000 + number * 10 + index, farmer_name: "Audit Farmer #{number}-#{index}", tracenet_no: "TRACE-#{number}-#{index}",
          fco_id: "995", fco: "Bhawanipatna", ics_id: "ics", ics_name: "Block", village_id: "v#{number}", village_name: "Village #{number}")
      end
      %w[Training Visit Inputs].each_with_index do |activity, index|
        target = TargetMapping.create!(id: 9_000_000 + number * 3 + index, vrp: owner, fco_id: "995", fco_name: "Bhawanipatna", ics_id: "ics", ics_name: "Block",
          village_id: "v#{number}", village_name: "Village #{number}", month_name: "October", main_activity_name: activity,
          activity_name: "Work #{activity}", target_quantity: 10, afl_ids: farmers.map(&:id),
          created_at: Time.current - (number * 3 + index).seconds, updated_at: Time.current - (number * 3 + index).seconds)
        if ENV["RESCAN_EXPORTS"] == "1" && activity == "Visit"
          add_module.call("other-target", { "jeevika_jankar_id" => owner.id.to_s, "jeevika_jankar_name" => owner.name,
            "month" => "October", "target_mapping_id" => target.id.to_s, "contact_number" => owner.mobile_no,
            "ics" => "Block", "village" => "Village #{number}", "training_topic" => "Visit", "training_subject" => "Work Visit",
            "target" => "10", "achievement" => "3", "completion_date" => "2026-10-10" })
        end
        if activity == "Training"
          training = add_module.call("training-form", { "jeevika_jankar_id" => owner.id.to_s, "trainer_name" => owner.name, "month" => "October",
            "main_activity" => activity, "main_activity_type" => "Training", "sub_activity" => "Work Training", "target_mapping_id" => target.id.to_s,
            "selected_farmer_ids" => farmers.first(5).map { |farmer| farmer.id.to_s }, "training_method" => "FFS", "training_date" => "2026-10-10" })
          if ENV["RESCAN_BLOCKED_REVISIONS"] == "1" && number.even?
            add_module.call(TrainingEditApproval::SLUG, { "record_id" => training.id.to_s, "status" => "Pending" })
          end
        end
      end
      observations = ModulesController::JEEVIKA_JANKAR_OBSERVATION_PARAMETERS.to_h { |parameter| [parameter[:key], "good"] }
      bill = add_module.call("jeevika-jankar-bill-process", { "select_vrp" => owner.id.to_s, "select_vrp_name" => owner.name,
        "bill_month" => "October", "financial_year" => "2026-2027", "status" => "Final Approved", "grand_total" => "5000.00",
        "observations" => observations, "bill_items" => [{ "main_activity" => "Training", "activity" => "Work Training", "assigned_count" => 10,
          "achievement_count" => 5, "farmer_details" => farmers.map { |farmer| { "id" => farmer.id.to_s, "name" => farmer.farmer_name, "evidence" => "x" * 1024 } } }] })
      if ENV["RESCAN_PAYMENTS"] == "1"
        add_module.call("jeevika-jankar-bill-approval-history", { "bill_id" => bill.id.to_s, "action" => "Approved",
          "action_at" => "2026-10-20T10:00:00Z", "approval_level" => "Final Approval", "approver" => "Audit Approver" })
        if number.even?
          add_module.call(ModulesController::JEEVIKA_JANKAR_PAYMENT_DETAIL_SLUG, { "selected_bill_ids" => [bill.id.to_s],
            "approval_date" => "2026-10-20", "transaction_date" => "2026-10-21", "transaction_id" => "AUDIT-#{number}",
            "payment_items" => [{ "bill_id" => bill.id.to_s, "jeevika_jankar_id" => owner.id.to_s, "jeevika_jankar_name" => owner.name,
              "bill_month" => "October", "financial_year" => "2026-2027", "amount" => "5000.00", "approval_date" => "2026-10-20" }] })
        end
      end
    end
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post("/login", params: { login: admin.user_name, password: "rescan-secret" })
    raise "Audit login failed" unless session.response.redirect? && session.response.location.end_with?("/dashboard")
    paths = %w[jeevika-jankar-payment-list training-form jeevika-jankar-observation-list jeevika-jankar-payment-list-detail other-target
      other-target-with-farmer gram-panchayat-master jeevika-jankar-bill-list jeevika-jankar-bill-process other-target-list
      other-target-with-farmer-list access-control-list approval-master user-hierarchy-mapping training-form-list].map { |slug| "/modules/#{slug}" }
    paths += %w[/dashboard /target_mappings/list /vrps/new /vrps/approvals /modules/jeevika-jankar-completed-payment-list]
    if ENV["RESCAN_EXPORTS"] == "1"
      paths = %w[training-form-list other-target-list jeevika-jankar-bill-list].map { |slug| "/modules/#{slug}/export.xlsx" }
    end
    requested_paths = ENV["RESCAN_PATHS"].to_s.split(",").reject(&:empty?)
    paths &= requested_paths if requested_paths.any?
    passes = Integer(ENV.fetch("RESCAN_PASSES", "2"))
    raise "Choose 2 to 5 passes" unless (2..5).cover?(passes)
    passes.times do |pass|
      paths.each do |path|
        queries = 0
        instantiated = 0
        sql_ms = 0.0
        sql = ->(*args) do
          event = ActiveSupport::Notifications::Event.new(*args)
          next if %w[SCHEMA TRANSACTION].include?(event.payload[:name]) || event.payload[:cached]
          queries += 1
          sql_ms += event.duration
        end
        records = ->(*args) { instantiated += args.last[:record_count] }
        allocated = GC.stat(:total_allocated_objects)
        gc_time = GC.stat(:time)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
          ActiveSupport::Notifications.subscribed(records, "instantiation.active_record") { session.get(path) }
        end
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
        request_allocations = GC.stat(:total_allocated_objects) - allocated
        request_gc_ms = GC.stat(:time) - gc_time
        xlsx = session.response.media_type == XlsxExporter::MIME_TYPE
        export_sha = nil
        export_rows = nil
        if xlsx
          Zip::File.open_buffer(session.response.body) do |zip|
            content = %w[xl/workbook.xml xl/worksheets/sheet1.xml].map { |name| zip.read(name) }
            export_sha = Digest::SHA256.hexdigest(content.join("\n"))
            export_rows = Nokogiri::XML(content.last).remove_namespaces!.css("row").size
          end
        end
        document = Nokogiri::HTML(xlsx ? "" : session.response.body)
        # Only visible labels/text are hashed: scripts and JSON are independently tested.
        document.css("script, style").remove
        visible_text = document.at_css("body")&.text.to_s.gsub(/\s+/, " ").strip
        controls = document.css("input, select, textarea, button").reject { |node| node["name"] == "authenticity_token" }.map do |node|
          [node.name, node["name"], node["type"], node["value"], node["checked"], node["disabled"], node["multiple"],
           node.name == "textarea" ? node.text : nil,
           node.css("option").map { |option| [option["value"], option.text, option["selected"]] }]
        end
        browser_data = document.css("*").filter_map do |node|
          data = node.attribute_nodes.select { |attribute| attribute.name.start_with?("data-") }.map { |attribute| [attribute.name, attribute.value] }
          [node.name, node["id"], data] unless data.empty?
        end
        report[:pages] << { path: path, pass: pass, status: session.response.status, milliseconds: elapsed.round(2),
          queries: queries, database_ms: sql_ms.round(2), instantiated: instantiated,
          allocations: request_allocations, gc_ms: request_gc_ms, bytes: session.response.body.bytesize,
          visible_sha256: Digest::SHA256.hexdigest(visible_text),
          controls_sha256: Digest::SHA256.hexdigest(controls.to_json),
          browser_data_sha256: Digest::SHA256.hexdigest(browser_data.to_json),
          export_sha256: export_sha, export_rows: export_rows }
        report[:pages].last[:visible_text] = visible_text if ENV["RESCAN_DETAIL"] == "1"
      end
    end
    raise ActiveRecord::Rollback
  end
end
puts JSON.pretty_generate(report)
raise "Some pages did not return 200" unless report[:pages].all? { |page| page[:status] == 200 }
