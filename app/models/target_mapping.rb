class TargetMapping < ApplicationRecord
  # How the location was picked when the target was given. ICS Wise walks the
  # farmer master (FCO -> ICS -> Village); Block Wise walks the office/ASA
  # directory (FCO -> Block -> Village) and keeps the block in ics_id/ics_name.
  ICS_WISE_ENTRY_MODE = "ics_wise".freeze
  BLOCK_WISE_ENTRY_MODE = "block_wise".freeze
  ENTRY_MODES = [ICS_WISE_ENTRY_MODE, BLOCK_WISE_ENTRY_MODE].freeze

  belongs_to :vrp
  belongs_to :vrp_ics_mapping, optional: true

  serialize :afl_ids, coder: JSON

  if column_names.include?("target_entry_mode")
    scope :ics_wise, -> { where(target_entry_mode: ICS_WISE_ENTRY_MODE) }
    scope :block_wise, -> { where(target_entry_mode: BLOCK_WISE_ENTRY_MODE) }

    validates :target_entry_mode, inclusion: { in: ENTRY_MODES }
  end

  # Anything unrecognised is ICS Wise, the mode the Target Mapping form opens on.
  def self.normalize_entry_mode(value)
    normalized = value.to_s.strip.downcase
    ENTRY_MODES.include?(normalized) ? normalized : ICS_WISE_ENTRY_MODE
  end

  def block_wise_entry?
    has_attribute?(:target_entry_mode) && target_entry_mode.to_s == BLOCK_WISE_ENTRY_MODE
  end

  before_validation :clean_afl_ids
  before_validation :sync_master_reference_ids

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
  if column_names.include?("cc_target")
    validates :cc_target, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validate :cc_target_within_opg_training
  end

  def weekly_target_values
    saved = [week_1_target, week_2_target, week_3_target, week_4_target]
    return saved.map(&:to_i) if saved.all?(&:present?)

    monthly = target_quantity.to_i
    base, remainder = monthly.divmod(4)
    4.times.map { |index| base + (index < remainder ? 1 : 0) }
  end

  private

  def cc_target_within_opg_training
    return unless has_attribute?(:cc_target)
    return if cc_target.nil?

    if opg_training_target.nil? || cc_target > opg_training_target
      errors.add(:cc_target, "cannot exceed OPG Training target")
    end
  end

  def clean_afl_ids
    self.afl_ids = Array(afl_ids).map(&:to_s).reject(&:blank?).uniq
  end

  def sync_master_reference_ids
    self.month_id = master_record_id(ModuleMonth, :month_name, month_name) if has_attribute?(:month_id)
    self.main_activity_id = master_record_id(ModuleMainActivity, :main_activity_name, main_activity_name) if has_attribute?(:main_activity_id)
    return unless has_attribute?(:sub_activity_id)

    scope = ModuleSubActivity.active
    if has_attribute?(:main_activity_id) && ModuleSubActivity.column_names.include?("main_activity_id")
      scope = scope.where(main_activity_id: main_activity_id)
    elsif ModuleSubActivity.column_names.include?("main_activity")
      scope = scope.where("LOWER(BTRIM(main_activity)) = ?", main_activity_name.to_s.strip.downcase)
    end
    self.sub_activity_id = scope.where("LOWER(BTRIM(sub_activity_name)) = ?", activity_name.to_s.strip.downcase)
      .order(created_at: :desc, id: :desc).pick(:id)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordNotFound
    # Legacy rows without a matching master remain readable by their label.
    self.month_id = nil if has_attribute?(:month_id)
    self.main_activity_id = nil if has_attribute?(:main_activity_id)
    self.sub_activity_id = nil if has_attribute?(:sub_activity_id)
  end

  def master_record_id(model, column, value)
    return if value.blank? || !model.table_exists? || !model.column_names.include?(column.to_s)

    model.active.where("LOWER(BTRIM(#{model.connection.quote_column_name(column)})) = ?", value.to_s.strip.downcase)
      .order(created_at: :desc, id: :desc).pick(:id)
  end
end
