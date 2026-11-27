class LgState < ApplicationRecord
  include LgDirectoryEntry

  MODULE_SLUGS = ["state-master"].freeze

  def self.name_column = :state_name
end
