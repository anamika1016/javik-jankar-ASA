class TargetMapping < ApplicationRecord
  belongs_to :vrp
  belongs_to :vrp_ics_mapping, optional: true

  serialize :afl_ids, coder: JSON

  before_validation :clean_afl_ids

  validates :vrp_id,
            :fco_id,
            :ics_id,
            :village_id,
            :month_name,
            :main_activity_name,
            :activity_name,
            :target_quantity,
            presence: true

  validates :target_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :cc_target, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :cc_target_within_opg_training

  def weekly_target_values
    saved = [week_1_target, week_2_target, week_3_target, week_4_target]
    return saved.map(&:to_i) if saved.all?(&:present?)

    monthly = target_quantity.to_i
    base, remainder = monthly.divmod(4)
    4.times.map { |index| base + (index < remainder ? 1 : 0) }
  end

  private

  def cc_target_within_opg_training
    return if cc_target.nil?

    if opg_training_target.nil? || cc_target > opg_training_target
      errors.add(:cc_target, "cannot exceed OPG Training target")
    end
  end

  def clean_afl_ids
    self.afl_ids = Array(afl_ids).map(&:to_s).reject(&:blank?).uniq
  end
end
