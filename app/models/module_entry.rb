# Active module storage. module_entries is a writable UNION ALL view over the
# dedicated tables, not a second aggregate data table. module_records remains
# an untouched archive and is never read or written by this model.
class ModuleEntry < ApplicationRecord
  include GloballyUniqueUsername

  class DataType < ActiveRecord::Type::Serialized
    def deserialize(value)
      return value unless value.nil? || value.is_a?(String)
      super
    end
  end
  attribute :data, DataType.new(ActiveRecord::Type::Text.new, JSON)
  validates :module_slug, :data, presence: true
  self.table_name = "module_entries"
  self.primary_key = "id"
  self.sequence_name = "module_entry_id_seq"
  self.ignored_columns = %w[xmin ctid storage_order]

  # Existing form names and session/token identities remain stable.
  def self.model_name = ActiveModel::Name.new(self, nil, "ModuleRecord")

  # PostgreSQL views do not advertise their primary key in pg_index. Preserve
  # the original insert_all! result contract explicitly (including imported IDs).
  def self.insert_all!(attributes, returning: nil, record_timestamps: nil)
    super(attributes, returning: returning.nil? ? [:id] : returning, record_timestamps: record_timestamps)
  end

  scope :active, -> {
    where.not("COALESCE(LOWER(BTRIM(data::jsonb ->> 'deleted')), '') IN (?)", %w[1 true yes deleted])
      .where.not("COALESCE(LOWER(BTRIM(data::jsonb ->> 'is_deleted')), '') IN (?)", %w[1 true yes deleted])
      .where.not("COALESCE(LOWER(BTRIM(data::jsonb ->> 'discarded')), '') IN (?)", %w[1 true yes deleted])
      .where("COALESCE(BTRIM(data::jsonb ->> 'status'), '') = '' OR LOWER(BTRIM(data::jsonb ->> 'status')) = 'active'")
  }
  scope :catalogue_order, -> { order(created_at: :desc, id: :desc) }
  scope :for_slug, ->(slug) { where(module_slug: slug) }

  # UNION views cannot be locked directly. Lock the dedicated row, then reload
  # its public shape. A concurrent slug move is retried without an archive read.
  def lock!(lock = true)
    raise ActiveRecord::ReadOnlyError, "Lock query attempted while in readonly mode" if self.class.current_preventing_writes
    return self unless persisted?
    raise "Locking a record with unpersisted changes is not supported" if has_changes_to_save?
    return reload unless lock

    connection = self.class.connection
    clause = lock == true ? "FOR UPDATE" : lock.to_s
    loop do
      table = connection.select_value(<<~SQL.squish)
        SELECT sources.table_name FROM module_entry_identities identities
        JOIN module_entry_sources sources ON sources.slug = identities.module_slug
        WHERE identities.id = #{connection.quote(id)}
      SQL
      raise ActiveRecord::RecordNotFound, "Couldn't find module entry with id=#{id}" unless table
      found = connection.select_value("SELECT id FROM #{connection.quote_table_name(table)} WHERE id = #{connection.quote(id)} #{clause}")
      break if found
      raise ActiveRecord::RecordNotFound, "Module entry is locked" if clause.include?("SKIP LOCKED")
    end
    reload
  end
end
