require "test_helper"

class VrpDashboardTest < ActionDispatch::IntegrationTest
  test "dashboard counts the same farmer once for each completed training activity" do
    vrp = create_vrp(user_name: "multi_activity_vrp", password: "secret", agreement_accepted_at: Time.current)
    farmer = create_afl(farmer_name: "Multi Activity Farmer", mobile_no: "9000000070")
    mapping = VrpIcsMapping.create!(
      vrp: vrp,
      fco_id: "FCO-MULTI",
      ics_id: "ICS-MULTI",
      village_id: "V-MULTI",
      village_name: "Multi Village",
      afl_ids: [farmer.id],
      created_by_type: "User",
      created_by_id: 1
    )
    ["Organic Introduction", "Soil Preparation"].each do |activity|
      TargetMapping.create!(
        vrp: vrp,
        vrp_ics_mapping: mapping,
        fco_id: mapping.fco_id,
        ics_id: mapping.ics_id,
        village_id: mapping.village_id,
        village_name: mapping.village_name,
        farmer_count: 1,
        afl_ids: [farmer.id],
        month_name: "July",
        completion_date: Date.new(2026, 7, 31),
        main_activity_name: "Farmers' Training",
        activity_name: activity,
        target_quantity: 1,
        created_by_type: "User",
        created_by_id: 1
      )
      ModuleRecord.create!(
        module_slug: "training-form",
        data: {
          "month" => "July",
          "main_activity" => "Farmers' Training",
          "sub_activity" => activity,
          "ics" => mapping.ics_id,
          "village" => mapping.village_name,
          "selected_farmer_ids" => [farmer.id.to_s],
          "vrp_id" => vrp.id.to_s
        }
      )
    end

    post login_path, params: { login: vrp.user_name, password: "secret" }
    get dashboard_path, params: { training_month: "July" }

    assert_response :success
    assert_select ".assigned-target strong", text: "2"
    assert_select ".achieved-target strong", text: "2"
    assert_select ".pending-target strong", text: "0"
    assert_select "#vrp_target_progress_table .grid-status", text: "100%", count: 2
  end

  test "dashboard counts training submitted after the target completion date" do
    vrp = create_vrp(user_name: "late_completion_vrp", password: "secret", agreement_accepted_at: Time.current)
    farmers = 2.times.map do |index|
      create_afl(farmer_name: "Late Completion Farmer #{index + 1}", mobile_no: "900000009#{index}")
    end
    mapping = VrpIcsMapping.create!(
      vrp: vrp,
      fco_id: "FCO-LATE",
      ics_id: "ICS-LATE",
      village_id: "V-LATE",
      village_name: "Late Village",
      afl_ids: farmers.map(&:id),
      created_by_type: "User",
      created_by_id: 1
    )
    target = TargetMapping.create!(
      vrp: vrp,
      vrp_ics_mapping: mapping,
      fco_id: mapping.fco_id,
      ics_id: mapping.ics_id,
      village_id: mapping.village_id,
      village_name: mapping.village_name,
      farmer_count: farmers.size,
      afl_ids: farmers.map(&:id),
      month_name: "July",
      completion_date: Date.new(2026, 7, 20),
      main_activity_name: "Farmers' Training",
      activity_name: "1. Organic Introduction (M1), 2. Soil Preparation (M3)",
      target_quantity: farmers.size,
      created_by_type: "User",
      created_by_id: 1
    )
    ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "July",
        "training_date" => "2026-07-25",
        "main_activity" => target.main_activity_name,
        "sub_activity" => "Organic Introduction (M1)",
        "ics" => mapping.ics_id,
        "village" => mapping.village_name,
        "selected_farmer_ids" => farmers.map { |farmer| farmer.id.to_s },
        "vrp_id" => vrp.id.to_s
      }
    )

    post login_path, params: { login: vrp.user_name, password: "secret" }
    get dashboard_path, params: { training_month: "July" }

    assert_response :success
    assert_select ".achieved-target strong", text: "2"
    assert_select ".pending-target strong", text: "0"

    get vrp_dashboard_list_path("pending_target"), params: { training_month: "July" }
    assert_response :success
    assert_includes response.body, "Total: 0"

    get vrp_dashboard_list_path("target_farmers"), params: { target_id: target.id, farmer_scope: "pending" }
    assert_response :success
    assert_includes response.body, "Total: 0"
    assert_includes response.body, "No records found for this list."
  end

  test "dashboard derives achieved and pending values from training submissions without activity master configuration" do
    vrp = create_vrp(user_name: "dynamic_progress_vrp", password: "secret", agreement_accepted_at: Time.current)
    farmers = 3.times.map do |index|
      create_afl(farmer_name: "Progress Farmer #{index + 1}", mobile_no: "900000001#{index}")
    end
    mapping = VrpIcsMapping.create!(
      vrp: vrp,
      fco_id: "FCO-DYNAMIC",
      ics_id: "ICS-DYNAMIC",
      village_id: "V-DYNAMIC",
      village_name: "Dynamic Village",
      afl_ids: farmers.map(&:id),
      created_by_type: "User",
      created_by_id: 1
    )
    TargetMapping.create!(
      vrp: vrp,
      vrp_ics_mapping: mapping,
      fco_id: mapping.fco_id,
      ics_id: mapping.ics_id,
      village_id: mapping.village_id,
      village_name: mapping.village_name,
      farmer_count: farmers.size,
      afl_ids: farmers.map(&:id),
      month_name: "July",
      completion_date: Date.new(2026, 7, 31),
      main_activity_name: "Unconfigured Training",
      activity_name: "Dynamic Training",
      target_quantity: 3,
      created_by_type: "User",
      created_by_id: 1
    )
    ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "July",
        "training_date" => "2026-07-20",
        "main_activity" => "Unconfigured Training",
        "sub_activity" => "Dynamic Training",
        "selected_farmer_ids" => farmers.first(2).map { |farmer| farmer.id.to_s },
        "vrp_id" => vrp.id.to_s
      }
    )

    post login_path, params: { login: "dynamic_progress_vrp", password: "secret" }
    get dashboard_path, params: { training_month: "July" }

    assert_response :success
    assert_select ".achieved-target strong", text: "2"
    assert_select ".pending-target strong", text: "1"
    assert_select "#vrp_target_progress_table tbody tr" do
      assert_select "td", text: "2"
      assert_select "td", text: "1"
      assert_select ".grid-status", text: "67%"
    end
  end

  test "vrp sees own dashboard data and read only targets" do
    vrp = create_vrp(
      user_name: "dashboard_vrp",
      password: "secret",
      agreement_accepted_at: Time.current
    )
    repeat_previous = create_afl(
      farmer_name: "Repeat Farmer",
      father_name: "Repeat Father",
      mobile_no: "9000000001",
      tracenet_no: "TR_REPEAT",
      purchase_date: Date.new(2026, 5, 12)
    )
    repeat_current = create_afl(
      farmer_name: "Repeat Farmer",
      father_name: "Repeat Father",
      mobile_no: "9000000001",
      tracenet_no: "TR_REPEAT",
      purchase_date: Date.new(2026, 6, 11)
    )
    new_current = create_afl(
      farmer_name: "New Farmer",
      father_name: "New Father",
      mobile_no: "9000000002",
      tracenet_no: "TR_NEW",
      purchase_date: Date.new(2026, 6, 15)
    )
    pending_farmer = create_afl(
      farmer_name: "Pending Farmer",
      father_name: "Pending Father",
      mobile_no: "9000000003",
      tracenet_no: "TR_PENDING",
      purchase_date: Date.new(2026, 5, 9)
    )
    mapping = VrpIcsMapping.create!(
      vrp: vrp,
      fco_id: "FCO1",
      fco_name: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      afl_ids: [repeat_previous.id, repeat_current.id, new_current.id, pending_farmer.id],
      created_by_type: "User",
      created_by_id: 1
    )
    TargetMapping.create!(
      vrp: vrp,
      vrp_ics_mapping: mapping,
      fco_id: mapping.fco_id,
      fco_name: mapping.fco_name,
      ics_id: mapping.ics_id,
      ics_name: mapping.ics_name,
      village_id: mapping.village_id,
      village_name: mapping.village_name,
      farmer_count: 4,
      month_name: "June",
      completion_date: Date.new(2026, 6, 30),
      main_activity_name: "Farmer Visit",
      activity_name: "Farm Visit",
      target_quantity: 10,
      created_by_type: "User",
      created_by_id: 1
    )
    ModuleRecord.create!(
      module_slug: "vrp-bill-add",
      data: {
        "select_vrp" => "#{vrp.name} - #{vrp.mobile_no}",
        "select_bill_month" => "June",
        "select_activity_group" => ["Farmer Visit"],
        "bill_items" => [
          {
            "activity" => "Farm Visit",
            "no_of_unit" => "4",
            "rate" => "0",
            "total_amount" => "0"
          }
        ],
        "grand_units" => "4"
      }
    )
    ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "June",
        "training_date" => "2026-06-05",
        "main_activity" => "Farmer Visit",
        "sub_activity" => "Farm Visit",
        "training_topic" => "Farmer Visit",
        "training_subject" => "Farm Visit",
        "selected_farmer_ids" => [repeat_previous.id.to_s, repeat_current.id.to_s]
      }
    )
    ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "June",
        "training_date" => "2026-06-12",
        "main_activity" => "Farmer Visit",
        "sub_activity" => "Farm Visit",
        "training_topic" => "Farmer Visit",
        "training_subject" => "Farm Visit",
        "selected_farmer_ids" => [repeat_previous.id.to_s, new_current.id.to_s]
      }
    )
    ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "June",
        "training_date" => "2026-06-20",
        "main_activity" => "Farmer Visit",
        "sub_activity" => "Farm Visit",
        "training_topic" => "Farmer Visit",
        "training_subject" => "Farm Visit",
        "selected_farmer_ids" => [repeat_previous.id.to_s, repeat_current.id.to_s]
      }
    )
    ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "June",
        "training_date" => "2026-06-22",
        "main_activity" => "Other Activity",
        "sub_activity" => "Other Sub Activity",
        "training_topic" => "Other Activity",
        "training_subject" => "Other Sub Activity",
        "selected_farmer_ids" => [pending_farmer.id.to_s]
      }
    )

    post login_path, params: { login: "dashboard_vrp", password: "secret" }
    follow_redirect!

    assert_response :success
    assert_includes response.body, "Mapped Farmers"
    assert_includes response.body, "Mapped Villages"
    assert_includes response.body, "Main Activities"
    assert_includes response.body, "Sub Activities"
    assert_includes response.body, "Assigned Target"
    assert_includes response.body, "Completed"
    assert_includes response.body, "Farmer Month Follow-up"
    assert_includes response.body, "Farmer Training Dashboard"
    assert_includes response.body, "Select Month"
    assert_includes response.body, "Select Sub Activity"
    refute_includes response.body, "Select Month and Sub Activity to load training data."
    refute_includes response.body, "Farmer Training Participation Status"
    refute_includes response.body, "Sessions"
    refute_includes response.body, "Photos"
    refute_includes response.body, "Registers"
    refute_includes response.body, "Male"
    refute_includes response.body, "Female"
    refute_includes response.body, "Dates"
    refute_includes response.body, "Cumulative"
    assert_includes response.body, "Repeat Farmers"
    assert_includes response.body, "New Farmers"
    assert_includes response.body, "Pending Target Farmers"
    assert_includes response.body, "Repeat Farmer"
    assert_includes response.body, "New Farmer"
    assert_includes response.body, "Pending Farmer"
    assert_includes response.body, "Farmer Visit"
    assert_includes response.body, "40%"
    assert_equal 1, response.body.scan("VRP Dashboard").size
    assert_includes response.body, "VRP Targets"

    get farmer_participation_report_path

    assert_response :success
    assert_includes response.body, "Farmer Participation Report"
    refute_includes response.body, "Participation List"

    get farmer_participation_report_path, params: { farmer_id: repeat_previous.id }

    assert_response :success
    assert_includes response.body, "Repeat Farmer"
    assert_includes response.body, "Farm Visit"

    get dashboard_path, params: { training_month: "June", training_sub_activity: "Farm Visit" }

    assert_response :success
    assert_includes response.body, "June"
    assert_includes response.body, "Farm Visit"
    assert_match(/<span class="training-status-pill green">1<\/span>/, response.body)
    assert_match(/<span class="training-status-pill yellow">2<\/span>/, response.body)
    assert_match(/<span class="training-status-pill red">1<\/span>/, response.body)
    assert_includes response.body, "Completed Farmers"
    assert_includes response.body, "Pending Farmers"
    refute_includes response.body, "Select Month and Sub Activity to load training data."

    get dashboard_path(format: :xlsx), params: { training_month: "June", training_sub_activity: "Farm Visit" }

    assert_response :success
    assert_equal XlsxExporter::MIME_TYPE, response.media_type
    assert response.body.start_with?("PK"), "expected an XLSX zip archive"

    get target_mappings_path

    assert_response :success
    assert_includes response.body, "VRP Targets"
    assert_includes response.body, "Village One"
    assert_includes response.body, "Completion Date"
    assert_includes response.body, "30-06-2026"
    assert_includes response.body, "Farm Visit"
    refute_includes response.body, "Save Target"
    refute_includes response.body, "Delete this target mapping?"
  end

  test "admin sees vrp menu and can select it in access control" do
    accepted_vrp = create_vrp(
      name: "Accepted VRP",
      user_name: "accepted_for_admin",
      mobile_no: "9876543211",
      email: "accepted@example.com",
      aadhar_no: "123456789013",
      agreement_accepted_at: Time.current
    )
    mapping = VrpIcsMapping.create!(
      vrp: accepted_vrp,
      fco_id: "FCO2",
      fco_name: "FCO Two",
      ics_id: "ICS2",
      ics_name: "ICS Two",
      village_id: "V2",
      village_name: "Admin Village",
      afl_ids: ["1"],
      created_by_type: "User",
      created_by_id: 1
    )
    TargetMapping.create!(
      vrp: accepted_vrp,
      vrp_ics_mapping: mapping,
      fco_id: mapping.fco_id,
      fco_name: mapping.fco_name,
      ics_id: mapping.ics_id,
      ics_name: mapping.ics_name,
      village_id: mapping.village_id,
      village_name: mapping.village_name,
      farmer_count: 1,
      month_name: "July",
      completion_date: Date.new(2026, 7, 31),
      main_activity_name: "Admin Activity",
      activity_name: "Admin Sub Activity",
      target_quantity: 7,
      created_by_type: "User",
      created_by_id: 1
    )
    User.create!(
      user_name: "admin",
      password: "secret",
      first_name: "Admin",
      user_type: "admin",
      status: "Active"
    )
    ModuleRecord.create!(
      module_slug: "approval-master",
      data: {
        "module_name" => "Jeevika Jankar Registration",
        "stakeholder_name" => "PAPL",
        "approval_level" => "Approval 1",
        "approver_approved_by" => "Anamika Vishwakarma (Aggronomist)",
        "status" => "Active",
        "user_name" => "Anamika Vishwakarma"
      }
    )
    ModuleRecord.create!(
      module_slug: "approval-master",
      data: {
        "module_name" => "Jeevika Jankar Registration",
        "stakeholder_name" => "PAPL",
        "approval_level" => "Approval 2",
        "approver_approved_by" => "rohit sharma sharma (IT Excicutive)",
        "status" => "Active",
        "user_name" => "rohit sharma sharma"
      }
    )
    ModuleRecord.create!(
      module_slug: "approval-master",
      data: {
        "module_name" => "Jeevika Jankar Registration",
        "stakeholder_name" => "PAPL",
        "approval_level" => "Approval 3",
        "approver_approved_by" => "third approver",
        "status" => "Active",
        "user_name" => "Anamika Vishwakarma"
      }
    )
    ModuleRecord.create!(
      module_slug: "approval-master",
      data: {
        "module_name" => "Jeevika Jankar Registration",
        "stakeholder_name" => "PAPL",
        "approval_level" => "Approval 4",
        "approver_approved_by" => "fourth approver",
        "status" => "Active",
        "user_name" => "Anamika Vishwakarma"
      }
    )

    post login_path, params: { login: "admin", password: "secret" }
    follow_redirect!

    assert_response :success
    assert_includes response.body, "VRP Targets"
    assert_includes response.body, "Accepted VRP"
    assert_includes response.body, "Admin Village"
    assert_includes response.body, "Admin Sub Activity"
    assert_includes response.body, "VRP Declaration Accepted"
    assert_includes response.body, "VRP Target Assigned"

    get module_path("approval-list")

    assert_response :success
    assert_includes response.body, "Stakeholder Category"
    assert_includes response.body, "Approval Levels"
    assert_includes response.body, "First Approval"
    assert_includes response.body, "Second Approval"
    assert_includes response.body, "Third Approval"
    assert_includes response.body, "Fourth Approval"
    refute_includes response.body, "Approval 1"

    approval_record = ModuleRecord.where(module_slug: "approval-master").first
    get edit_module_record_path("approval-master", approval_record)

    assert_response :success
    assert_includes response.body, "First Approval"
    assert_includes response.body, "Second Approval"
    assert_includes response.body, "Third Approval"
    assert_includes response.body, "Fourth Approval"
    refute_includes response.body, "Approval step 0"

    get module_path("access-control")

    assert_response :success
    assert_includes response.body, "VRP Targets"
    refute_includes response.body, "VRP Dashboard"
  end

  test "jeevika jankar approval starts with first approver from creator channel" do
    creator = User.create!(
      user_name: "akashdeep_nath",
      password: "secret",
      first_name: "Akashdeep",
      last_name: "Nath",
      stakeholder: "ASA",
      role: "PMC-Oprection",
      user_type: "user",
      status: "Active"
    )
    User.create!(
      user_name: "soumen_day",
      password: "secret",
      first_name: "Soumen",
      last_name: "Day",
      stakeholder: "ASA",
      role: "PMC-Oprection",
      user_type: "user",
      status: "Active"
    )
    User.create!(
      user_name: "anurag_patel",
      password: "secret",
      first_name: "Anurag",
      last_name: "Patel",
      stakeholder: "ASA",
      role: "PMC-Oprection",
      user_type: "user",
      status: "Active"
    )
    vrp = create_vrp(
      name: "Anjali Kumari",
      user_name: "to_barhait_jj1",
      mobile_no: "9876543999",
      email: "anjali-kumari@example.com",
      created_by_id: creator.id,
      created_by_type: "User",
      stakeholder: "ASA",
      status: 10
    )

    [
      ["Akashdeep Nath", "First Approval", "Soumen Day (PMC-Oprection)"],
      ["Akashdeep Nath", "Second Approval", "Anurag Patel (PMC-Oprection)"],
      ["Pritesh Jain", "First Approval", "Anurag Patel (PMC-Oprection)"]
    ].each do |user_name, level, approver|
      ModuleRecord.create!(
        module_slug: "approval-master",
        data: {
          "module_name" => "Jeevika Jankar Registration",
          "stakeholder_name" => "ASA",
          "user_name" => user_name,
          "approval_level" => level,
          "approver_approved_by" => approver,
          "status" => "Active"
        }
      )
    end

    post login_path, params: { login: "akashdeep_nath", password: "secret" }
    patch send_for_approval_vrp_path(vrp)

    assert_redirected_to vrps_path
    sent_history = ModuleRecord.where(module_slug: "vrp-approval-history").order(:created_at).last
    assert_equal vrp.id.to_s, sent_history.data["vrp_id"]
    assert_equal "Pending at Soumen Day (PMC-Oprection)", sent_history.data["status"]

    get vrps_path

    assert_response :success
    assert_select "[data-vrp-status-cell]", text: /Pending at Soumen Day \(PMC-Oprection\)/
    assert_no_match(/Pending at Anurag Patel \(PMC-Oprection\)/, response.body)

    get vrp_path(vrp)

    assert_response :success
    assert_select ".approval-progress-card.current", text: /Pending at: Soumen Day \(PMC-Oprection\)/
    assert_no_match(/Pending at: Anurag Patel \(PMC-Oprection\).*Current step/m, response.body)
  end

  test "vrp training form shows only target assigned farmers" do
    vrp = create_vrp(
      name: "Training VRP",
      user_name: "training_vrp",
      mobile_no: "9876543888",
      email: "training-vrp@example.com",
      aadhar_no: "123456789088",
      agreement_accepted_at: Time.current
    )
    farmers = 3.times.map do |index|
      create_afl(
        farmer_name: "Training Farmer #{index + 1}",
        tracenet_no: "TR_TRAINING_#{index + 1}",
        mobile_no: "900000020#{index}"
      )
    end
    mapping = VrpIcsMapping.create!(
      vrp: vrp,
      fco_id: "FCO1",
      fco_name: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      afl_ids: farmers.map(&:id),
      created_by_type: "User",
      created_by_id: 1
    )
    TargetMapping.create!(
      vrp: vrp,
      vrp_ics_mapping: mapping,
      fco_id: mapping.fco_id,
      fco_name: mapping.fco_name,
      ics_id: mapping.ics_id,
      ics_name: mapping.ics_name,
      village_id: mapping.village_id,
      village_name: mapping.village_name,
      farmer_count: 2,
      month_name: "July",
      completion_date: Date.new(2026, 7, 31),
      main_activity_name: "Farmer Visit",
      activity_name: "Farm Visit",
      target_quantity: 2,
      afl_ids: farmers.first(2).map(&:id),
      created_by_type: "User",
      created_by_id: 1
    )

    post login_path, params: { login: "training_vrp", password: "secret" }
    follow_redirect!
    get module_path("training-form")

    assert_response :success
    assert_includes response.body, "Farmer Training Form"
    assert_includes response.body, "Target Farmers"
    assert_includes response.body, "Save Farmers"
    assert_includes response.body, "Search target farmers"
    assert_includes response.body, "No target farmers matched your search."
    assert_includes response.body, "Training Farmer 1"
    assert_includes response.body, "Training Farmer 2"
    refute_includes response.body, "Training Farmer 3"
  end

  test "mapped village dashboard count uses mapping rows and allows delete" do
    vrp = create_vrp(
      user_name: "mapped_village_vrp",
      password: "secret",
      village_ids: ["V1", "V2", "V3"],
      agreement_accepted_at: Time.current
    )
    mappings = 3.times.map do |index|
      VrpIcsMapping.create!(
        vrp: vrp,
        fco_id: "FCO#{index + 1}",
        fco_name: "FCO #{index + 1}",
        ics_id: "ICS#{index + 1}",
        ics_name: "ICS #{index + 1}",
        village_id: "V#{index + 1}",
        village_name: "Shared Village",
        afl_ids: ["#{index + 1}"],
        created_by_type: "User",
        created_by_id: 1
      )
    end
    mappings.each_with_index do |mapping, index|
      TargetMapping.create!(
        vrp: vrp,
        fco_id: mapping.fco_id,
        fco_name: mapping.fco_name,
        ics_id: mapping.ics_id,
        ics_name: mapping.ics_name,
        village_id: mapping.village_id,
        village_name: mapping.village_name,
        farmer_count: 1,
        month_name: "July",
        completion_date: Date.new(2026, 7, 31),
        main_activity_name: "Farmer Visit",
        activity_name: "Farm Visit #{index + 1}",
        target_quantity: 1,
        afl_ids: ["#{index + 1}"],
        created_by_type: "User",
        created_by_id: 1
      )
    end

    post login_path, params: { login: "mapped_village_vrp", password: "secret" }
    follow_redirect!

    assert_response :success
    assert_match(/Mapped Villages.*?<strong>3<\/strong>/m, response.body)
    assert_equal 3, response.body.scan("Delete this mapped village?").size

    get vrp_dashboard_list_path("mapped_villages")

    assert_response :success
    assert_includes response.body, "Total: 3 | Rows: 3"
    assert_equal 3, response.body.scan("Delete this mapped village?").size

    target = TargetMapping.find_by!(vrp: vrp, village_id: mappings.second.village_id)
    assert_difference("TargetMapping.count", -1) do
      delete destroy_vrp_mapped_village_path(target)
    end

    assert_redirected_to vrp_dashboard_list_path("mapped_villages")

    get vrp_dashboard_list_path("mapped_villages")

    assert_response :success
    assert_includes response.body, "Total: 2 | Rows: 2"
  end

  test "mapped village dashboard is zero when target mappings are deleted" do
    vrp = create_vrp(
      user_name: "empty_target_vrp",
      password: "secret",
      village_ids: ["V1", "V2"],
      agreement_accepted_at: Time.current
    )
    2.times do |index|
      VrpIcsMapping.create!(
        vrp: vrp,
        fco_id: "FCO#{index + 1}",
        fco_name: "FCO #{index + 1}",
        ics_id: "ICS#{index + 1}",
        ics_name: "ICS #{index + 1}",
        village_id: "V#{index + 1}",
        village_name: "Village #{index + 1}",
        afl_ids: ["#{index + 1}"],
        created_by_type: "User",
        created_by_id: 1
      )
    end

    post login_path, params: { login: "empty_target_vrp", password: "secret" }
    follow_redirect!

    assert_response :success
    assert_match(/Mapped Villages.*?<strong>0<\/strong>/m, response.body)

    get vrp_dashboard_list_path("mapped_villages")

    assert_response :success
    assert_includes response.body, "Total: 0 | Rows: 0"
  end

  test "target mapping location dropdowns fall back to saved target rows" do
    vrp = create_vrp(
      name: "Location Target VRP",
      user_name: "location_target_vrp",
      mobile_no: "9876543777",
      email: "location-target-vrp@example.com",
      aadhar_no: "123456789077"
    )
    TargetMapping.create!(
      vrp: vrp,
      fco_id: "FCO-TM",
      fco_name: "Target FCO",
      ics_id: "ICS-TM",
      ics_name: "Target ICS",
      village_id: "V-TM",
      village_name: "Target Village",
      farmer_count: 10,
      month_name: "July",
      completion_date: Date.new(2026, 7, 31),
      main_activity_name: "Farmer Visit",
      activity_name: "Farm Visit",
      target_quantity: 10,
      created_by_type: "User",
      created_by_id: 1
    )
    User.create!(
      user_name: "location_target_admin",
      password: "secret",
      first_name: "Location Target Admin",
      user_type: "admin",
      status: "Active"
    )

    post login_path, params: { login: "location_target_admin", password: "secret" }
    follow_redirect!

    get vrp_mappings_target_mappings_path, params: { vrp_id: vrp.id }

    assert_response :success
    data = JSON.parse(response.body)
    assert_includes data.fetch("fco_options").map { |option| option["value"] }, "FCO-TM||Target FCO"

    get vrp_mappings_target_mappings_path, params: { vrp_id: vrp.id, fco_id: "FCO-TM||Target FCO" }

    assert_response :success
    data = JSON.parse(response.body)
    assert_includes data.fetch("ics_options").map { |option| option["value"] }, "ICS-TM||Target ICS"

    get vrp_mappings_target_mappings_path, params: { vrp_id: vrp.id, fco_id: "FCO-TM||Target FCO", ics_id: "ICS-TM||Target ICS" }

    assert_response :success
    data = JSON.parse(response.body)
    assert_includes data.fetch("village_options").map { |option| option["value"] }, "V-TM||Target Village"
  end

  test "partial target requires selected farmers and blocks same month reassignment" do
    vrp = create_vrp(
      name: "Target VRP",
      user_name: "target_vrp",
      mobile_no: "9876543999",
      email: "target-vrp@example.com",
      aadhar_no: "123456789099"
    )
    farmers = 3.times.map do |index|
      create_afl(
        farmer_name: "Target Farmer #{index + 1}",
        tracenet_no: "TR_TARGET_#{index + 1}",
        mobile_no: "900000010#{index}"
      )
    end
    mapping = VrpIcsMapping.create!(
      vrp: vrp,
      fco_id: "FCO1",
      fco_name: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      afl_ids: farmers.map(&:id),
      created_by_type: "User",
      created_by_id: 1
    )
    User.create!(
      user_name: "target_admin",
      password: "secret",
      first_name: "Target Admin",
      user_type: "admin",
      status: "Active"
    )

    post login_path, params: { login: "target_admin", password: "secret" }
    follow_redirect!

    assert_difference("TargetMapping.count", 1) do
      post target_mappings_path, params: {
        target_mapping: target_params(vrp, mapping, "July", 2, farmers.first(2).map(&:id))
      }
    end

    target = TargetMapping.order(:id).last
    assert_equal 2, target.farmer_count
    assert_equal farmers.first(2).map { |farmer| farmer.id.to_s }, target.afl_ids

    manual_target_params = target_params(vrp, mapping, "September", 0, [], "Farm Visit", "Farmer Visit")
    manual_target_params.delete(:target_quantity)
    manual_target_params.delete(:afl_ids)
    manual_target_params[:new_farmer_target_quantity] = "7"
    assert_difference("TargetMapping.count", 1) do
      post target_mappings_path, params: { target_mapping: manual_target_params }
    end

    manual_target = TargetMapping.order(:id).last
    assert_equal 0, manual_target.farmer_count
    assert_equal [], manual_target.afl_ids
    assert_equal 7, manual_target.target_quantity.to_i

    get vrp_mappings_target_mappings_path, params: {
      vrp_id: vrp.id,
      fco_id: mapping.fco_id,
      ics_id: mapping.ics_id,
      village_id: mapping.village_id,
      month_name: "July",
      main_activity_name: "Farmer Visit",
      activity_name: "Farm Visit"
    }

    farmer_rows = JSON.parse(response.body).fetch("farmers")
    assigned_rows = farmer_rows.select { |farmer| farmer["assigned_to_other"] }
    available_rows = farmer_rows.reject { |farmer| farmer["assigned_to_other"] }
    assert_equal farmers.first(2).map { |farmer| farmer.id.to_s }.sort, assigned_rows.map { |farmer| farmer["id"] }.sort
    assert_equal [farmers.last.id.to_s], available_rows.map { |farmer| farmer["id"] }

    get vrp_mappings_target_mappings_path, params: {
      vrp_id: vrp.id,
      fco_id: mapping.fco_id,
      ics_id: mapping.ics_id,
      village_id: mapping.village_id,
      month_name: "August",
      main_activity_name: "Farmer Visit",
      activity_name: "Farm Visit"
    }
    august_rows = JSON.parse(response.body).fetch("farmers")
    assert_empty august_rows.select { |farmer| farmer["assigned_to_other"] }

    other_vrp = create_vrp(
      user_name: "second_target_vrp",
      password: "secret",
      agreement_accepted_at: Time.current
    )
    other_mapping = VrpIcsMapping.create!(
      vrp: other_vrp,
      fco_id: mapping.fco_id,
      fco_name: mapping.fco_name,
      ics_id: mapping.ics_id,
      ics_name: mapping.ics_name,
      village_id: mapping.village_id,
      village_name: mapping.village_name,
      afl_ids: farmers.map(&:id),
      created_by_type: "User",
      created_by_id: 1
    )

    assert_no_difference("TargetMapping.count") do
      post target_mappings_path, params: {
        target_mapping: target_params(other_vrp, other_mapping, "July", 2, farmers.first(2).map(&:id))
      }
    end

    get vrp_mappings_target_mappings_path, params: {
      vrp_id: other_vrp.id,
      fco_id: other_mapping.fco_id,
      ics_id: other_mapping.ics_id,
      village_id: other_mapping.village_id,
      month_name: "July",
      main_activity_name: "Farmer Visit",
      activity_name: "Farm Visit"
    }

    cross_vrp_rows = JSON.parse(response.body).fetch("farmers")
    assert_equal farmers.first(2).map { |farmer| farmer.id.to_s }.sort,
      cross_vrp_rows.select { |farmer| farmer["assigned_to_other"] }.map { |farmer| farmer["id"] }.sort

    assert_difference("TargetMapping.count", 1) do
      post target_mappings_path, params: {
        target_mapping: target_params(vrp, mapping, "August", 1, [farmers.first.id])
      }
    end

    assert_difference("TargetMapping.count", 1) do
      post target_mappings_path, params: {
        target_mapping: target_params(vrp, mapping, "July", 1, [farmers.first.id], "Farmer Training")
      }
    end

    assert_difference("TargetMapping.count", 1) do
      post target_mappings_path, params: {
        target_mapping: target_params(vrp, mapping, "July", 1, [farmers.first.id], "Farm Visit", "Farmer Awareness")
      }
    end

    assert_difference("TargetMapping.count", 1) do
      post target_mappings_path, params: {
        target_mapping: target_params(vrp, mapping, "July", 1, [farmers.last.id])
      }
    end
  end

  test "target mapping loads fco and farmers when afl fco id is blank" do
    vrp = create_vrp(
      name: "Blank FCO Target VRP",
      user_name: "blank_fco_target_vrp",
      mobile_no: "9876543888",
      email: "blank-fco-target@example.com",
      aadhar_no: "123456789088"
    )
    farmers = 2.times.map do |index|
      create_afl(
        fco_id: "",
        fco: "Bhabra",
        ics_id: "18",
        ics_name: "BADGAON BHABHRA FARMERS PRODUCERS COMPANY LIMITED",
        village_id: "116",
        village_name: "Badgaon",
        farmer_name: "Blank FCO Farmer #{index + 1}"
      )
    end
    VrpIcsMapping.create!(
      vrp: vrp,
      fco_id: "Bhabra",
      fco_name: "Bhabra",
      ics_id: "18",
      ics_name: "BADGAON BHABHRA FARMERS PRODUCERS COMPANY LIMITED",
      village_id: "116",
      village_name: "Badgaon",
      afl_ids: ["999999"],
      created_by_type: "User",
      created_by_id: 1
    )
    User.create!(
      user_name: "blank_fco_admin",
      password: "secret",
      first_name: "Blank FCO Admin",
      user_type: "admin",
      status: "Active"
    )

    post login_path, params: { login: "blank_fco_admin", password: "secret" }
    follow_redirect!

    get vrp_mappings_target_mappings_path, params: { vrp_id: vrp.id }
    data = JSON.parse(response.body)
    assert_includes data.fetch("fco_options").map { |option| option["label"] }, "Bhabra"

    get vrp_mappings_target_mappings_path, params: {
      vrp_id: vrp.id,
      fco_id: "Bhabra||Bhabra"
    }
    data = JSON.parse(response.body)
    assert_includes data.fetch("ics_options").map { |option| option["value"] }, "18||BADGAON BHABHRA FARMERS PRODUCERS COMPANY LIMITED"

    get vrp_mappings_target_mappings_path, params: {
      vrp_id: vrp.id,
      fco_id: "Bhabra||Bhabra",
      ics_id: "18||BADGAON BHABHRA FARMERS PRODUCERS COMPANY LIMITED",
      village_ids: ["116||Badgaon"].to_json
    }
    farmer_rows = JSON.parse(response.body).fetch("farmers")
    assert_equal farmers.map { |farmer| farmer.id.to_s }.sort, farmer_rows.map { |farmer| farmer["id"] }.sort
  end

  test "target mapping fco dropdown removes null and duplicate name options" do
    vrp = create_vrp(
      name: "Unique FCO VRP",
      user_name: "unique_fco_vrp",
      mobile_no: "9876543889",
      email: "unique-fco-vrp@example.com",
      aadhar_no: "123456789089"
    )
    create_afl(fco_id: "1009", fco: "Bhabra", farmer_name: "Coded FCO Farmer")
    create_afl(fco_id: "Bhabra", fco: "Bhabra", farmer_name: "Name FCO Farmer")
    create_afl(fco_id: "1009", fco: "Bhabra - 1009", farmer_name: "Repeated Code Farmer")
    create_afl(fco_id: "NULL", fco: "NULL", farmer_name: "Null FCO Farmer")

    User.create!(
      user_name: "unique_fco_admin",
      password: "secret",
      first_name: "Unique FCO Admin",
      user_type: "admin",
      status: "Active"
    )
    post login_path, params: { login: "unique_fco_admin", password: "secret" }
    follow_redirect!

    get vrp_mappings_target_mappings_path, params: { vrp_id: vrp.id }

    assert_response :success
    options = JSON.parse(response.body).fetch("fco_options")
    assert_equal [ "Bhabra - 1009" ], options.filter_map { |option| option["label"] if option["label"].downcase.include?("bhabra") }
    refute options.any? { |option| option["label"].to_s.casecmp("null").zero? }
  end

  test "target mapping keeps training targets for mixed training and other activity selection" do
    vrp = create_vrp(
      name: "Mixed Target VRP",
      user_name: "mixed_target_vrp",
      mobile_no: "9876543666",
      email: "mixed-target@example.com",
      aadhar_no: "123456789066"
    )
    farmer = create_afl(farmer_name: "Mixed Target Farmer")
    mapping = VrpIcsMapping.create!(
      vrp: vrp,
      fco_id: "FCO1",
      fco_name: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      afl_ids: [farmer.id],
      created_by_type: "User",
      created_by_id: 1
    )
    ModuleRecord.create!(
      module_slug: "add-activity-group",
      data: {
        "main_activity_name" => "Farmers' Training",
        "main_activity_type" => "Training",
        "status" => "Active"
      }
    )
    ModuleRecord.create!(
      module_slug: "add-activity-group",
      data: {
        "main_activity_name" => "Seed Packet Distribution 2026-27",
        "main_activity_type" => "Other",
        "status" => "Active"
      }
    )
    ModuleRecord.create!(
      module_slug: "add-vrp-activity",
      data: {
        "main_activity" => "Seed Packet Distribution 2026-27",
        "sub_activity_name" => "Seed Packet Distribution",
        "status" => "Active"
      }
    )
    User.create!(
      user_name: "mixed_target_admin",
      password: "secret",
      first_name: "Mixed Target Admin",
      user_type: "admin",
      status: "Active"
    )

    post login_path, params: { login: "mixed_target_admin", password: "secret" }
    follow_redirect!

    assert_difference("TargetMapping.count", 2) do
      post target_mappings_path, params: {
        target_mapping: {
          vrp_id: vrp.id,
          fco_id: mapping.fco_id,
          ics_id: mapping.ics_id,
          village_id: mapping.village_id,
          month_name: "July",
          completion_date: Date.new(2026, 7, 31),
          main_activity_names: ["Farmers' Training", "Seed Packet Distribution 2026-27"],
          activity_names: ["Seed Packet Distribution"],
          target_quantity: 1,
          afl_ids: [farmer.id],
          training_targets: { week_wise_opg: "4" }
        }
      }
    end

    saved_targets = TargetMapping.where(vrp: vrp, month_name: "July").order(:id).to_a
    other_target = saved_targets.find { |target| target.activity_name == "Seed Packet Distribution" }
    training_target = saved_targets.find { |target| target.activity_name == "General Training/Meeting" }

    assert_equal "Seed Packet Distribution 2026-27", other_target.main_activity_name
    assert_equal [farmer.id.to_s], other_target.afl_ids
    assert_equal 1, other_target.target_quantity.to_i
    assert_equal "Farmers' Training", training_target.main_activity_name
    assert_equal [], training_target.afl_ids
    assert_equal 4, training_target.target_quantity.to_i
    refute saved_targets.any? { |target| target.main_activity_name == "Seed Packet Distribution 2026-27" && target.activity_name == "General Training/Meeting" }
  end

  test "target mapping vrp dropdown shows only approved vrps registered by current user" do
    user = User.create!(
      user_name: "target_owner",
      password: "secret",
      first_name: "Target Owner",
      user_type: "user",
      status: "Active"
    )
    own_vrp = create_vrp(
      name: "Own Approved Jeevika",
      user_name: "own_approved_jeevika",
      mobile_no: "9876543666",
      email: "own-approved-jeevika@example.com",
      aadhar_no: "123456789066",
      status: 55,
      created_by_id: user.id
    )
    other_vrp = create_vrp(
      name: "Other Approved Jeevika",
      user_name: "other_approved_jeevika",
      mobile_no: "9876543555",
      email: "other-approved-jeevika@example.com",
      aadhar_no: "123456789055",
      status: 55,
      created_by_id: user.id + 100
    )
    pending_vrp = create_vrp(
      name: "Own Pending Jeevika",
      user_name: "own_pending_jeevika",
      mobile_no: "9876543444",
      email: "own-pending-jeevika@example.com",
      aadhar_no: "123456789044",
      status: 25,
      created_by_id: user.id
    )

    post login_path, params: { login: "target_owner", password: "secret" }
    follow_redirect!
    get target_mappings_path

    assert_response :success
    assert_includes response.body, own_vrp.name
    refute_includes response.body, other_vrp.name
    refute_includes response.body, pending_vrp.name
  end

  test "other target forms accept completion date without legacy date key" do
    vrp = create_vrp(
      name: "Other Target VRP",
      user_name: "other_target_vrp",
      mobile_no: "9876543777",
      email: "other-target@example.com",
      aadhar_no: "123456789077",
      fcoc: "Other Department"
    )
    farmer = create_afl(farmer_name: "Other Target Farmer")
    target = TargetMapping.create!(
      vrp: vrp,
      fco_id: "FCO1",
      fco_name: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      month_name: "June",
      completion_date: Date.new(2026, 6, 30),
      main_activity_name: "Seed Packet Distribution 2026-27",
      activity_name: "Seed Packet Distribution",
      target_quantity: 1,
      farmer_count: 1,
      afl_ids: [farmer.id]
    )
    ModuleRecord.create!(
      module_slug: "add-activity-group",
      data: {
        "main_activity_name" => target.main_activity_name,
        "main_activity_type" => "Other",
        "achievement_fill" => "Manual",
        "status" => "Active"
      }
    )
    User.create!(
      user_name: "other_target_admin",
      password: "secret",
      first_name: "Other Target Admin",
      user_type: "admin",
      status: "Active"
    )

    post login_path, params: { login: "other_target_admin", password: "secret" }
    follow_redirect!

    assert_difference("ModuleRecord.where(module_slug: 'seed-distribution-target').count", 1) do
      post records_module_path("seed-distribution-target"), params: {
        module_record: other_target_params(vrp, target).merge(
          "farmer_count" => "1",
          "selected_farmer_ids" => [farmer.id.to_s]
        )
      }
    end
    seed_record = ModuleRecord.where(module_slug: "seed-distribution-target").order(:id).last
    assert_equal "2026-06-30", seed_record.data["completion_date"]
    assert_equal "2026-06-30", seed_record.data["date"]

    assert_difference("ModuleRecord.where(module_slug: 'papl360-target').count", 1) do
      post records_module_path("papl360-target"), params: {
        module_record: other_target_params(vrp, target)
      }
    end
    papl_record = ModuleRecord.where(module_slug: "papl360-target").order(:id).last
    assert_equal "2026-06-30", papl_record.data["completion_date"]
    assert_equal "2026-06-30", papl_record.data["date"]
  end

  test "other target forms accept new farmer target without mapped farmers" do
    vrp = create_vrp(
      name: "Manual Other Target VRP",
      user_name: "manual_other_target_vrp",
      mobile_no: "9876543999",
      email: "manual-other-target@example.com",
      aadhar_no: "123456789099",
      fcoc: "Manual Department"
    )
    target = TargetMapping.create!(
      vrp: vrp,
      fco_id: "FCO1",
      fco_name: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      month_name: "June",
      completion_date: Date.new(2026, 6, 30),
      main_activity_name: "Manual Seed Packet Distribution",
      activity_name: "Manual Seed Packet Distribution",
      target_quantity: 5,
      farmer_count: 0,
      afl_ids: []
    )
    ModuleRecord.create!(
      module_slug: "add-activity-group",
      data: {
        "main_activity_name" => target.main_activity_name,
        "main_activity_type" => "Other",
        "achievement_fill" => "Manual",
        "status" => "Active"
      }
    )
    User.create!(
      user_name: "manual_other_target_admin",
      password: "secret",
      first_name: "Manual Other Target Admin",
      user_type: "admin",
      status: "Active"
    )

    post login_path, params: { login: "manual_other_target_admin", password: "secret" }
    follow_redirect!

    assert_difference("ModuleRecord.where(module_slug: 'seed-distribution-target').count", 1) do
      post records_module_path("seed-distribution-target"), params: {
        module_record: other_target_params(vrp, target).merge("achievement" => "3")
      }
    end
  end

  test "jeevika bill approval starts at l1 approver" do
    user = User.create!(
      user_name: "bill_owner_#{SecureRandom.hex(4)}",
      password: "secret",
      first_name: "Lilabati",
      last_name: "Bhoi",
      stakeholder: "PAPL",
      role: "User",
      status: "Active"
    )
    vrp = create_vrp(
      name: "Approval Bill VRP",
      user_name: "approval_bill_vrp",
      mobile_no: "9876543999",
      email: "approval-bill-vrp@example.com",
      aadhar_no: "123456789099",
      status: 55,
      created_by_id: user.id
    )

    ModuleRecord.create!(
      module_slug: "approval-master",
      data: {
        "module_name" => "Jeevika Jankar Bill",
        "stakeholder_name" => "PAPL",
        "user_name" => user.user_name,
        "approval_level" => "First Appovel",
        "approver_approved_by" => "Sangam Kumari (Manager ics)",
        "status" => "Active"
      }
    )
    ModuleRecord.create!(
      module_slug: "approval-master",
      data: {
        "module_name" => "Jeevika Jankar Bill",
        "stakeholder_name" => "PAPL",
        "user_name" => user.user_name,
        "approval_level" => "Secound Appovel",
        "approver_approved_by" => "Akash Mandal (FCO-C Turekela)",
        "status" => "Active"
      }
    )
    bill = ModuleRecord.create!(
      module_slug: "jeevika-jankar-bill-process",
      data: {
        "select_vrp" => vrp.id.to_s,
        "select_vrp_name" => vrp.name,
        "financial_year" => "2026-2027",
        "bill_month" => "June",
        "created_by_id" => user.id.to_s,
        "created_by_username" => user.user_name,
        "created_by_name" => user.full_name,
        "status" => "Submitted (Not sent for approval)"
      }
    )

    post login_path, params: { login: user.user_name, password: "secret" }
    follow_redirect!

    patch send_for_approval_module_record_path("jeevika-jankar-bill-list", bill)

    assert_redirected_to module_path("jeevika-jankar-bill-list")
    assert_equal "Pending at Sangam Kumari (Manager ics)", bill.reload.data["status"]
    assert_equal "1", bill.data["approval_current_sequence"]
  end

  private

  def target_params(vrp, mapping, month, target_quantity, farmer_ids, activity_name = "Farm Visit", main_activity_name = "Farmer Visit")
    {
      vrp_id: vrp.id,
      fco_id: mapping.fco_id,
      ics_id: mapping.ics_id,
      village_id: mapping.village_id,
      month_name: month,
      completion_date: Date.new(2026, 7, 31),
      main_activity_name: main_activity_name,
      activity_name: activity_name,
      target_quantity: target_quantity,
      afl_ids: farmer_ids
    }
  end

  def other_target_params(vrp, target)
    {
      "main_activity_type" => "Other",
      "target_mapping_id" => target.id.to_s,
      "jeevika_jankar_id" => vrp.id.to_s,
      "jeevika_jankar_name" => vrp.id.to_s,
      "contact_number" => vrp.mobile_no,
      "department" => vrp.fcoc,
      "month" => target.month_name,
      "ics" => target.ics_name,
      "village" => target.village_name,
      "main_activity" => target.main_activity_name,
      "sub_activity" => target.activity_name,
      "completion_date" => "2026-06-30",
      "target" => target.target_quantity.to_i.to_s,
      "achievement" => "1"
    }
  end

  def create_vrp(attributes = {})
    defaults = {
      name: "Dashboard VRP",
      father_husband_name: "Test Father",
      gender: :male,
      date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current,
      aadhar_no: "123456789012",
      account_no: "1234567890",
      bank_name: "Test Bank",
      branch: "Test Branch",
      ifsc_code: "TEST0123456",
      address: "Test Address",
      mobile_no: "9876543210",
      email: "vrp#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1,
      office_detail_id: 0,
      to_office_detail_id: 0,
      vrp_type_ids: [1],
      gram_panchayat_ids: [1],
      village_ids: [1],
      is_active: true,
      is_deleted: false
    }

    Vrp.create!(defaults.merge(attributes))
  end

  def create_afl(attributes = {})
    defaults = {
      fco_id: "FCO1",
      fco: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      farmer_name: "Test Farmer"
    }

    Afl.create!(defaults.merge(attributes))
  end
end
