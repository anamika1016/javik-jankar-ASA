# Shared behaviour for the small masters mirrored out of module_records onto
# tables of their own.
#
# Each row keeps module_entries.id as its primary key and the payload verbatim
# in `data`, so these models are drop-in substitutes anywhere the code reads
# `record.id` / `record.data` off a ModuleEntry. The named columns are
# PostgreSQL generated columns derived from `data`, so they are always in step
# with it and are read-only here.
module ModuleMasterRecord
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(active: true) }
    # Option lists are newest-first then de-duplicated by label, keeping the
    # first row per label, matching what module_records returned.
    scope :catalogue_order, -> { order(created_at: :desc, id: :desc) }
  end

  # Callers that group or branch on the slug work unchanged on these rows.
  def module_slug
    self.class.module_slug
  end

  class_methods do
    def module_slug
      raise NotImplementedError, "#{name} must define module_slug"
    end

    # [label, id] pairs for a dropdown, straight off indexed columns.
    def option_pairs(column = label_column)
      label_key = respond_to?(:option_label_key) ? option_label_key : column
      if column_names.include?(label_key.to_s)
        return active.catalogue_order.where.not(label_key => nil).pluck(label_key, :id)
      end

      quoted_key = connection.quote(label_key.to_s)
      active.catalogue_order
        .where("NULLIF(BTRIM(data ->> ?), '') IS NOT NULL", label_key.to_s)
        .pluck(Arel.sql("data ->> #{quoted_key}"), :id)
    end

    def label_column
      raise NotImplementedError, "#{name} must define label_column"
    end
  end
end
