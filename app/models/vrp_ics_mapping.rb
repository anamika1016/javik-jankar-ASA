class VrpIcsMapping < ApplicationRecord
  belongs_to :vrp
  has_many :target_mappings, dependent: :destroy

  serialize :afl_ids, coder: JSON

  validates :vrp_id, :fco_id, :ics_id, :village_id, presence: true
  validate :at_least_one_farmer_selected

  before_validation :clean_afl_ids

  def farmer_count
    Array(afl_ids).size
  end

  private

  def clean_afl_ids
    self.afl_ids = Array(afl_ids).map(&:to_s).reject(&:blank?).uniq
  end

  def at_least_one_farmer_selected
    errors.add(:afl_ids, "select at least one farmer") if Array(afl_ids).blank?
  end
end
