require "test_helper"

# The lg_* tables only earn their place if reading from them is
# indistinguishable from reading module_records. These tests pin that: same
# rows, same ids, same order, same payloads, through every write path.
#
# Ids matter most. vrp_profiles.state_id/district_id/block_id/
# gram_panchayat_id/village_id and the vrps.village_ids / gram_panchayat_ids
# arrays all store module_records ids, so the mirror has to keep them.
class LgDirectoryEquivalenceTest < ActiveSupport::TestCase
  SLUGS = %w[state-master district-master block-master gram-panchayat-master village-master lg-directory-list].freeze

  setup do
    ModuleRecord.where(module_slug: SLUGS).delete_all
    @created = {}
    SLUGS.each_with_index do |slug, slug_index|
      @created[slug] = 3.times.map do |index|
        ModuleRecord.create!(module_slug: slug, data: payload_for(slug, "#{slug}-#{index}"),
          created_at: Time.current - ((slug_index * 10) + index).minutes)
      end
    end
    # One inactive row per slug, by each of the four ways a row goes inactive.
    @inactive = SLUGS.flat_map do |slug|
      [{ "status" => "Inactive" }, { "deleted" => "1" }, { "is_deleted" => "true" }, { "discarded" => "yes" }].map do |flag|
        ModuleRecord.create!(module_slug: slug, data: payload_for(slug, "hidden-#{slug}").merge(flag))
      end
    end
  end

  test "every slug is covered and nothing else is" do
    assert LgDirectory.covers?(SLUGS)
    SLUGS.each { |slug| assert LgDirectory.covers?(slug), slug }
    assert_not LgDirectory.covers?("training-form")
    assert_not LgDirectory.covers?(["village-master", "training-form"]), "a mixed request must fall back"
    assert_not LgDirectory.covers?([])
  end

  test "each slug returns the same ids in the same order as module_records" do
    SLUGS.each do |slug|
      assert_equal old_ids(slug), LgDirectory.records_for(slug).map(&:id), slug
    end
  end

  test "multi-slug reads match the combined module_records order" do
    [%w[village-master lg-directory-list],
     %w[block-master lg-directory-list],
     %w[gram-panchayat-master lg-directory-list village-master]].each do |slugs|
      assert_equal old_ids(slugs), LgDirectory.records_for(slugs).map(&:id), slugs.inspect
    end
  end

  test "payloads come back byte-identical" do
    SLUGS.each do |slug|
      old = old_records(slug).index_by(&:id)
      LgDirectory.records_for(slug).each do |row|
        assert_equal old.fetch(row.id).data, row.data, "#{slug} ##{row.id}"
      end
    end
  end

  test "inactive rows are excluded exactly as active_module_record? excludes them" do
    hidden_ids = @inactive.map(&:id)
    SLUGS.each do |slug|
      ids = LgDirectory.records_for(slug).map(&:id)
      assert_empty ids & hidden_ids, slug
    end
  end

  test "ids are preserved, because stored mappings point at them" do
    SLUGS.each do |slug|
      LgDirectory.records_for(slug).each do |row|
        source = ModuleRecord.find_by(id: row.id)
        assert_not_nil source, "id #{row.id} must still resolve to its module record"
        assert_equal slug, source.module_slug
      end
    end
  end

  test "option_pairs matches building the pairs off module_records" do
    {
      "state-master" => "state_name", "district-master" => "district_name",
      "block-master" => "block_name", "gram-panchayat-master" => "gram_panchayat_name",
      "village-master" => "village_name", "lg-directory-list" => "village_name"
    }.each do |slug, key|
      expected = old_records(slug).map { |record| [record.data[key], record.id] }
      assert_equal expected, LgDirectory.option_pairs(slug), slug
    end
  end

  test "a new module record shows up immediately" do
    record = ModuleRecord.create!(module_slug: "village-master", data: payload_for("village-master", "Fresh Village"))
    assert_includes LgDirectory.records_for("village-master").map(&:id), record.id
    assert_equal old_ids("village-master"), LgDirectory.records_for("village-master").map(&:id)
  end

  test "deactivating a record hides it, reactivating brings it back" do
    record = @created["village-master"].first
    record.update!(data: record.data.merge("status" => "Inactive"))
    assert_not_includes LgDirectory.records_for("village-master").map(&:id), record.id

    record.update!(data: record.data.merge("status" => "Active"))
    assert_includes LgDirectory.records_for("village-master").map(&:id), record.id
  end

  test "deleting a module record removes the mirrored row" do
    record = @created["block-master"].first
    record.destroy!
    assert_not_includes LgDirectory.records_for("block-master").map(&:id), record.id
    assert_nil LgBlock.find_by(id: record.id)
  end

  # Bulk writes skip ActiveRecord callbacks. In a database that has the
  # jj_lg_directory_sync trigger they are still mirrored; in one built from
  # db/schema.rb (which cannot carry a trigger) they are not, so the caller
  # resyncs -- which is what LgDirectoryImporter does after its insert_all!.
  test "resync repairs the mirror after an insert_all! that skipped callbacks" do
    result = ModuleRecord.insert_all!([{
      module_slug: "village-master", data: payload_for("village-master", "Bulk Village"),
      created_at: Time.current, updated_at: Time.current
    }])
    id = result.rows.flatten.first

    LgDirectory.resync!(["village-master"])

    row = LgVillage.find_by(id: id)
    assert_not_nil row
    assert_equal "Bulk Village", row.village_name
    assert_equal old_ids("village-master"), LgDirectory.records_for("village-master").map(&:id)
  end

  test "resync drops rows a delete_all removed" do
    ids = @created["district-master"].map(&:id)
    ModuleRecord.where(id: ids).delete_all

    LgDirectory.resync!(["district-master"])

    assert_empty LgDistrict.where(id: ids)
    assert_equal old_ids("district-master"), LgDirectory.records_for("district-master").map(&:id)
  end

  test "an import resyncs the mirror on its own" do
    headers = ["State Name", "State Code", "District Name", "District Code",
      "Block Name", "Block Code", "Gram Name", "Gram Code", "Village Name", "Village Code"]
    rows = [["MP", "23", "Pandhurna", "455", "Sausar", "0246", "Gram A", "03656", "Imported Village", "495999"]]

    LgDirectoryImporter.import_rows(rows, headers)

    assert_includes LgVillage.where(active: true).pluck(:village_name), "Imported Village"
    assert_includes LgBlock.where(active: true).pluck(:block_name), "Sausar"
    assert_equal old_ids("village-master"), LgDirectory.records_for("village-master").map(&:id)
    assert_equal old_ids("block-master"), LgDirectory.records_for("block-master").map(&:id)
  end

  test "resync is idempotent" do
    before = LgDirectory::MODELS.to_h { |model| [model.table_name, model.order(:id).pluck(:id)] }
    3.times { LgDirectory.resync! }
    LgDirectory::MODELS.each do |model|
      assert_equal before[model.table_name], model.order(:id).pluck(:id), model.table_name
    end
  end

  # The payload field names differ per master: village-master calls the block
  # "block", lg-directory-list calls it "cd_block_name", block-master calls it
  # "block_name". All three have to land in the same column.
  test "the block name is extracted whichever alias the master used" do
    village = ModuleRecord.create!(module_slug: "village-master",
      data: { "block" => "Alias Block", "village_name" => "V1", "status" => "Active" })
    directory = ModuleRecord.create!(module_slug: "lg-directory-list",
      data: { "cd_block_name" => "Alias Block", "village_name" => "V2", "status" => "Active" })
    block = ModuleRecord.create!(module_slug: "block-master",
      data: { "block_name" => "Alias Block", "status" => "Active" })

    assert_equal "Alias Block", LgVillage.find(village.id).block_name
    assert_equal "Alias Block", LgVillage.find(directory.id).block_name
    assert_equal "Alias Block", LgBlock.find(block.id).block_name
  end

  # The mirror stores `data` as jsonb, which sorts and de-duplicates object
  # keys, so it is faithful as a Hash but not byte-for-byte as JSON text. Any
  # caller that compares a payload by its string form -- vrp_detail_village_index
  # reads its catalogue as `json` for exactly that reason -- has to keep reading
  # module_records. This pins the limitation so it is found here rather than as
  # a village that silently stops matching.
  test "payloads are Hash-equal but not key-order-preserving" do
    record = ModuleRecord.create!(module_slug: "village-master",
      data: { "zz" => "Z", "village_name" => "Ordered", "aa" => "A", "status" => "Active" })
    row = LgVillage.find(record.id)

    assert_equal record.data, row.data, "the payload must still be Hash-equal"
    assert_equal record.data.keys.sort, row.data.keys.sort, "no key may be lost"
    # jsonb orders keys by length first, then bytewise -- not as written.
    assert_equal %w[aa zz status village_name], row.data.keys,
      "a caller relying on the written key order must not read this table"
    assert_not_equal record.data.keys, row.data.keys
  end

  test "a malformed payload does not break the mirror" do
    record = ModuleRecord.create!(module_slug: "village-master", data: "not-an-object")
    row = LgVillage.find_by(id: record.id)
    assert_not_nil row, "the row still mirrors"
    assert_nil row.village_name
    assert_equal({}, row.data)
  end

  private

  def old_records(slugs)
    ModuleRecord.where(module_slug: Array(slugs))
      .order(created_at: :desc, id: :desc)
      .select { |record| active_module_record?(record) }
  end

  def old_ids(slugs)
    old_records(slugs).map(&:id)
  end

  # The predicate the controllers apply in Ruby today.
  def active_module_record?(record)
    data = record.data
    return false unless data.is_a?(Hash)
    return false if %w[deleted is_deleted discarded].any? do |key|
      %w[1 true yes deleted].include?(data[key].to_s.strip.downcase)
    end

    status = data["status"].to_s.strip
    status.blank? || status.casecmp("Active").zero?
  end

  def payload_for(slug, name)
    base = { "status" => "Active" }
    case slug
    when "state-master" then base.merge("state_name" => name, "state_code" => "23")
    when "district-master" then base.merge("state" => "MP", "district_name" => name, "district_code" => "455")
    when "block-master" then base.merge("state" => "MP", "district" => "D", "block_name" => name, "block_code" => "0246")
    when "gram-panchayat-master" then base.merge("state" => "MP", "district" => "D", "block" => "B", "gram_panchayat_name" => name, "gp_code" => "03656")
    when "village-master" then base.merge("state" => "MP", "district" => "D", "block" => "B", "gram_panchayat" => "GP", "village_name" => name, "village_code" => "495194")
    when "lg-directory-list" then base.merge("state_name" => "MP", "district_name" => "D", "cd_block_name" => "B", "gram_panchayat" => "GP", "village_name" => name, "village_code" => "495195")
    end
  end
end
