# The version table has no domain model of its own. This tiny read-only model
# keeps request-time cache-version reads in Active Record.
#
# It lives in its own file because Zeitwerk maps one constant to one path. It
# used to sit at the bottom of app/services/module_record_read_version.rb,
# where Zeitwerk never knew it existed: on a development reload ApplicationRecord
# was replaced while this class survived still inheriting the previous one, and
# the next request raised "superclass mismatch for ModuleRecordReadVersionRecord".
class ModuleRecordReadVersionRecord < ApplicationRecord
  self.table_name = ModuleRecordReadVersion::TABLE
  self.primary_key = :source_key
end
