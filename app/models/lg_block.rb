class LgBlock < ApplicationRecord
  include LgDirectoryEntry

  MODULE_SLUGS = ["block-master"].freeze

  def self.name_column = :block_name
end
