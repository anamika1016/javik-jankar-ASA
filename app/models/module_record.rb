class ModuleRecord < ApplicationRecord
  include GloballyUniqueUsername

  # Source writes still use the existing JSON-in-text format. Dedicated-table
  # reads can also return PostgreSQL's already-decoded jsonb value; converting
  # that payload to text inside SQL and parsing it back for every predicate was
  # particularly costly for bill and training summaries.
  class DataType < ActiveRecord::Type::Serialized
    def deserialize(value)
      return value unless value.nil? || value.is_a?(String)

      super
    end
  end
  attribute :data, DataType.new(ActiveRecord::Type::Text.new, JSON)

  validates :module_slug, presence: true
  validates :data, presence: true

  # The LG Directory masters are mirrored into the lg_* tables, which the
  # dropdowns read instead of parsing these payloads in Ruby. A database
  # trigger mirrors bulk and raw-SQL writes; this covers the ordinary
  # create/update/destroy the module screens do, so the mirror stays correct
  # even where db/schema.rb has dropped the trigger (it cannot represent one).
  # The upsert is idempotent, so both firing is harmless.
  after_commit :sync_lg_directory_mirror, if: :lg_directory_record?

  private

  def lg_directory_record?
    defined?(LgDirectory) && LgDirectory::SLUGS.include?(module_slug) ||
      (saved_change_to_module_slug? && defined?(LgDirectory) &&
        LgDirectory::SLUGS.include?(module_slug_before_last_save))
  end

  def sync_lg_directory_mirror
    LgDirectory.sync!([id])
  rescue StandardError => error
    # A mirror failure must not take down a master save. The rake task
    # `lg_directory:resync` rebuilds derived directory values from the
    # dedicated tables.
    Rails.logger.error("LG directory mirror sync failed for ##{id}: #{error.class} - #{error.message}")
  end
end
