require "test_helper"

# The unbounded TargetMapping loads behind the dashboard, the bill rows and the
# training/other-target forms used includes(:vrp), which carries every Jeevika
# Jankar column along - including agreement_signature_data, the signature image
# stored when the agreement was accepted. None of those screens read it, and on
# an unbounded load it is the bulk of the payload.
#
# preload_target_vrps! attaches the same associations without that one column.
# These tests pin that target.vrp still answers from memory, that every other
# attribute is intact, and that the signature itself is still reachable where it
# is actually used.
class TargetVrpPreloadTest < ActiveSupport::TestCase
  SIGNATURE = "data:image/png;base64,SIGNATUREDATA".freeze

  setup do
    @vrp = Vrp.create!(
      name: "Preload JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "881234567890", account_no: "8812345678", bank_name: "Bank",
      branch: "Br", ifsc_code: "TEST0123456", address: "Addr",
      mobile_no: "9880000001", email: "preload_jj@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 55,
      user_name: "preload_jj", password: "secret",
      fcoc: "FCO-Bhawanipatna", cluster_incharge: "CC One",
      agreement_signature_data: SIGNATURE
    )
    @farmer = Afl.create!(fco_id: "995", fco: "Bhawanipatna", ics_id: "ics",
      ics_name: "ICS", village_id: "v", village_name: "Village", farmer_name: "F1")
    @target = TargetMapping.create!(
      vrp: @vrp, fco_id: "995", fco_name: "Bhawanipatna", ics_id: "ics",
      ics_name: "ICS", village_id: "v", village_name: "Village",
      month_name: "September", main_activity_name: "Farmers' Training",
      activity_name: "Soil", target_quantity: 1, afl_ids: [@farmer.id],
      week_wise_opg_target: 2, opg_training_target: 2
    )
    # A Jeevika Jankar is required on a saved mapping, so the only way a nil
    # vrp_id reaches the preload is an unsaved record. It still must not raise.
    @orphan = TargetMapping.new(vrp_id: nil, month_name: "September")
  end

  def preloaded(targets)
    ModulesController.new.send(:preload_target_vrps!, targets)
  end

  test "the association answers from memory without another query" do
    targets = TargetMapping.where(id: @target.id).to_a
    preloaded(targets)

    queries = []
    callback = ->(*args) { queries << args.last[:sql].to_s }
    vrp = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      vrp = targets.first.vrp
    end

    assert_equal @vrp.id, vrp.id
    assert_empty queries.grep(/FROM "vrps"/),
      "reading target.vrp went back to the database instead of using the preload"
  end

  test "every attribute the screens read is still present" do
    targets = preloaded(TargetMapping.where(id: @target.id).to_a)
    vrp = targets.first.vrp

    # A representative spread of what the module screens actually read.
    assert_equal @vrp.name, vrp.name
    assert_equal @vrp.user_name, vrp.user_name
    assert_equal @vrp.mobile_no, vrp.mobile_no
    assert_equal @vrp.fcoc, vrp.fcoc
    assert_equal @vrp.cluster_incharge, vrp.cluster_incharge
    assert_equal @vrp.status, vrp.status
    assert_equal @vrp.email, vrp.email
    assert_equal @vrp.village_ids, vrp.village_ids

    expected = Vrp.column_names - ["agreement_signature_data"]
    assert_equal expected.sort, vrp.attributes.keys.sort,
      "the preload changed which columns the association carries"
  end

  test "a target without a Jeevika Jankar stays nil rather than raising" do
    targets = TargetMapping.where(id: @target.id).to_a + [@orphan]

    assert_nothing_raised { preloaded(targets) }
    assert_nil @orphan.vrp
    assert_equal @vrp.id, targets.first.vrp.id
  end

  test "the signature is untouched and still readable where it is used" do
    preloaded(TargetMapping.where(id: @target.id).to_a)

    assert_equal SIGNATURE, Vrp.find(@vrp.id).agreement_signature_data,
      "the stored signature must be unchanged"
  end

  test "preloading an empty list is a no-op" do
    assert_equal [], preloaded([])
  end

  test "one query covers every distinct Jeevika Jankar in the batch" do
    second = TargetMapping.create!(
      vrp: @vrp, fco_id: "995", fco_name: "Bhawanipatna", ics_id: "ics",
      ics_name: "ICS", village_id: "v", village_name: "Village",
      month_name: "October", main_activity_name: "Farmers' Training",
      activity_name: "Soil", target_quantity: 1, afl_ids: [],
      week_wise_opg_target: 2, opg_training_target: 2
    )
    targets = TargetMapping.where(id: [@target.id, second.id]).to_a

    queries = []
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      queries << sql if sql.match?(/FROM "vrps"/)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { preloaded(targets) }

    assert_equal 1, queries.size
    assert_not_includes queries.first, "agreement_signature_data"
  end
end
