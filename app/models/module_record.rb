class ModuleRecord < ApplicationRecord
  include GloballyUniqueUsername
  serialize :data, coder: JSON

  validates :module_slug, presence: true
  validates :data, presence: true
end
