class LgGramPanchayat < ApplicationRecord
  include LgDirectoryEntry

  MODULE_SLUGS = ["gram-panchayat-master"].freeze

  def self.name_column = :gram_panchayat_name
end
