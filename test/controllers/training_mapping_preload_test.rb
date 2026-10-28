require "test_helper"

# preload_training_target_mappings_for_records! resolves every target mapping a
# set of training records points at. Its own comment notes a form may reference
# thousands of them, and it used to load them with includes(:vrp) - which drags
# agreement_signature_data, the stored signature image, along for every mapping.
#
# It now batches with find_in_batches and attaches the Jeevika Jankar through
# preload_target_vrps! instead. These tests pin that the cache it builds is
# identical - same keys, same values, same insertion order - and that the
# association still answers without going back to the database.
class TrainingMappingPreloadTest < ActiveSupport::TestCase
  SIGNATURE = "data:image/png;base64,SIGNATUREDATA".freeze

  setup do
    @vrp = Vrp.create!(
      name: "Mapping JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "881234567891", account_no: "8812345679", bank_name: "Bank",
      branch: "Br", ifsc_code: "TEST0123456", address: "Addr",
      mobile_no: "9880000002", email: "mapping_jj@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 55,
      user_name: "mapping_jj", password: "secret",
      fcoc: "FCO-Bhawanipatna", cluster_incharge: "CC One",
      agreement_signature_data: SIGNATURE
    )
    @farmer = Afl.create!(fco_id: "996", fco: "Bhawanipatna", ics_id: "ics",
      ics_name: "ICS", village_id: "v", village_name: "Village", farmer_name: "F1")

    @targets = 3.times.map do |i|
      TargetMapping.create!(
        vrp: @vrp, fco_id: "996", fco_name: "Bhawanipatna", ics_id: "ics",
        ics_name: "ICS", village_id: "v", village_name: "Village",
        month_name: "September", main_activity_name: "Farmers' Training",
        activity_name: "Soil #{i}", target_quantity: 1, afl_ids: [@farmer.id],
        week_wise_opg_target: 2, opg_training_target: 2
      )
    end
  end

  # A stand-in for the training records the method reads mapping ids off of.
  def record_for(ids)
    ModuleRecord.new(module_slug: "training-form",
      data: { "target_mapping_ids" => ids.map(&:to_s) })
  end

  def filled_cache(records)
    controller = ModulesController.new
    controller.send(:preload_training_target_mappings_for_records!, records)
    controller.instance_variable_get(:@training_record_target_mapping_cache)
  end

  test "cache holds one entry per requested mapping, keyed by id string" do
    cache = filled_cache([record_for(@targets.map(&:id))])

    assert_equal @targets.map { |t| t.id.to_s }.sort, cache.keys.sort
    assert_equal @targets.map(&:id).sort, cache.values.map(&:id).sort
  end

  test "entry order follows the requested ids, not the load order" do
    reversed = @targets.map(&:id).reverse

    cache = filled_cache([record_for(reversed)])

    # Every missing id is seeded with nil before anything is loaded, and Ruby
    # keeps a key in its original position when the value is later replaced.
    # So the order is the caller's id order and the batch load cannot change
    # it - which is why swapping find_each for find_in_batches is invisible.
    assert_equal reversed.map(&:to_s), cache.keys
  end

  test "the Jeevika Jankar answers from memory without another query" do
    cache = filled_cache([record_for(@targets.map(&:id))])
    target = cache[@targets.first.id.to_s]

    queries = []
    callback = ->(*args) { queries << args.last[:sql].to_s }
    vrp = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      vrp = target.vrp
    end

    assert_equal @vrp.id, vrp.id
    assert_empty queries.grep(/FROM "vrps"/),
      "reading target.vrp went back to the database instead of using the preload"
  end

  test "attributes the training screens read are intact" do
    cache = filled_cache([record_for(@targets.map(&:id))])
    vrp = cache[@targets.first.id.to_s].vrp

    assert_equal @vrp.name, vrp.name
    assert_equal @vrp.mobile_no, vrp.mobile_no
    assert_equal @vrp.fcoc, vrp.fcoc
    assert_equal @vrp.cluster_incharge, vrp.cluster_incharge
    assert_equal @vrp.status, vrp.status
  end

  test "a mapping id with no row stays cached as nil rather than disappearing" do
    missing = @targets.map(&:id).max + 1_000
    cache = filled_cache([record_for(@targets.map(&:id) + [missing])])

    assert cache.key?(missing.to_s),
      "an unresolvable mapping id must stay in the cache so it is not queried again"
    assert_nil cache[missing.to_s]
  end

  test "the signature column is left out of the attached Jeevika Jankar" do
    cache = filled_cache([record_for(@targets.map(&:id))])
    vrp = cache[@targets.first.id.to_s].vrp

    # This is the whole point of the change: the row arrives without the image.
    assert_not vrp.has_attribute?("agreement_signature_data"),
      "the signature column was loaded again, so the payload was not reduced"
    # It is still reachable wherever the agreement screens actually need it.
    assert_equal SIGNATURE, Vrp.find(@vrp.id).agreement_signature_data
  end
end
