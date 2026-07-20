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

  private

  def clean_afl_ids
    self.afl_ids = Array(afl_ids).map(&:to_s).reject(&:blank?).uniq
  end
end
