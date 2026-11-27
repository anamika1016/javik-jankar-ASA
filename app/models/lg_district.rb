class LgDistrict < ApplicationRecord
  include LgDirectoryEntry

  MODULE_SLUGS = ["district-master"].freeze

  def self.name_column = :district_name
end
