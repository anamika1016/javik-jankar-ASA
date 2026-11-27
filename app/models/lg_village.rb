# Holds both village masters: the Village Entry screen (village-master) and the
# combined All List (lg-directory-list), which is village-grained too. Callers
# that read villages today read both slugs together, so they live in one table.
class LgVillage < ApplicationRecord
  include LgDirectoryEntry

  MODULE_SLUGS = ["village-master", "lg-directory-list"].freeze

  def self.name_column = :village_name
end
