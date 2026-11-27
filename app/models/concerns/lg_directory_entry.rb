# Shared behaviour for the five LG Directory master tables.
#
# These rows mirror module_records rows one-for-one, keeping the same id and
# the same `data` payload, so an LG model is a drop-in substitute anywhere the
# code reads `record.id` / `record.data` off a ModuleEntry. That is what lets
# the existing label-derivation rules keep working untouched -- only where the
# rows are read from changes, not what is done with them.
module LgDirectoryEntry
  extend ActiveSupport::Concern

  included do
    # `active` is maintained by the jj_lg_directory_sync trigger and already
    # encodes the deleted / is_deleted / discarded flags plus status, which is
    # the predicate active_module_record? applies in Ruby.
    scope :active, -> { where(active: true) }

    # Option lists are built newest-first and then de-duplicated by label,
    # keeping the first row seen for each name. That ordering decides which id
    # represents a repeated name, so it has to match what module_records did.
    scope :catalogue_order, -> { order(created_at: :desc, id: :desc) }

    scope :for_slug, ->(slug) { where(source_slug: Array(slug)) }
  end

  # Callers that group or branch on the slug work unchanged on these rows.
  def module_slug
    source_slug
  end

  class_methods do
    # The payload key this level is named by, used when a caller wants labels
    # without going through the generic derivation helpers.
    def name_column
      raise NotImplementedError, "#{name} must define name_column"
    end

    # [label, id] pairs for a dropdown, read straight off indexed columns --
    # no row instantiation and no JSON parsing.
    def option_pairs
      active.catalogue_order.pluck(name_column, :id)
    end
  end
end
