# Run with RAILS_ENV=test bin/rails runner script/jj_read_benchmark.rb.
# Synthetic records are rolled back; this must use a dedicated test database.
require "benchmark"
abort "Use RAILS_ENV=test with a dedicated test database" unless Rails.env.test?

def measure_jj_read
  GC.start
  before = GC.stat(:total_allocated_objects)
  value = nil
  elapsed = Benchmark.realtime { value = yield }
  [{ milliseconds: (elapsed * 1000).round(2), allocated_objects: GC.stat(:total_allocated_objects) - before }, value]
end

report = {}
ActiveRecord::Base.transaction do
  now = Time.current
  attributes = { aadhar_no: "123456789012", account_no: "123", address: "Test", branch: "Test",
    date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current, email: "audit@example.test",
    experience_in_years: 0, father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456",
    mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0, created_at: now, updated_at: now,
    fcoc: "FCO Sausar", agreement_signature_data: "x" * 65_536 }
  Vrp.insert_all!(500.times.map { |index| attributes.merge(name: "Audit JJ #{index}") })
  controller = ModulesController.new
  before, expected = measure_jj_read do
    Vrp.order(:name).where(is_active: [true, nil], is_deleted: [false, nil])
      .filter_map { |vrp| controller.send(:jeevika_jankar_transfer_label, vrp) }.uniq
  end
  after, actual = measure_jj_read { controller.send(:transferable_jeevika_jankar_options) }
  raise "Transfer labels changed" unless expected == actual
  report[:transfer_500_jjs_with_64kb_signatures] = { before: before, after: after, labels_equal: true,
    omitted_signature_bytes: 500 * 65_536 }

  steps = 40.times.flat_map do |channel|
    3.times.map do |level|
      ModuleRecord.new(id: channel * 3 + level + 1, created_at: now, updated_at: now, data: {
        "module_name" => "VRP Bill", "stakeholder_name" => "Staff #{channel}",
        "user_name" => "", "approval_level" => ["First Approval", "Second Approval", "Third Approval"][level]
      })
    end
  end
  controller.define_singleton_method(:jeevika_bill_approval_master_steps) { steps }
  controller.define_singleton_method(:jeevika_bill_approval_step_matches_bill?) { |step, _record| step.data["stakeholder_name"] == "Staff 5" }
  bills = 500.times.map { |index| ModuleRecord.new(id: 500_000 + index, data: {}) }
  before, expected = measure_jj_read do
    bills.map do |bill|
      keys = steps.select { |step| controller.send(:jeevika_bill_approval_step_matches_bill?, step, bill) }
        .map { |step| controller.send(:approval_channel_key, step) }.uniq
      steps.select { |step| keys.include?(controller.send(:approval_channel_key, step)) }
        .group_by { |step| controller.send(:approval_channel_key, step) }.values
        .map { |rows| controller.send(:ordered_approval_channel_steps, rows) }.reject(&:blank?)
        .max_by { |rows| controller.send(:approval_channel_priority, rows) } || []
    end
  end
  after, actual = measure_jj_read { bills.map { |bill| controller.send(:jeevika_bill_approval_steps, bill) } }
  raise "Approval channel selection changed" unless expected == actual
  report[:approval_channels_500_bills_120_steps] = { before: before, after: after, channels_equal: true }
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate(report)
