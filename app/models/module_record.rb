class ModuleRecord < ApplicationRecord
  serialize :data, coder: JSON

  validates :module_slug, presence: true
  validates :data, presence: true
end
