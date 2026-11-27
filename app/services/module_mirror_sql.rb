# SQL fragments shared by the module mirror tables and the trigger that fills
# them, so the "is this row active?" rule is written once.
module ModuleMirrorSql
  # The predicate active_module_record? applies in Ruby: any of the three
  # delete flags set, or a status that is present and not "Active", means
  # inactive. A blank status is active.
  #
  # Phrased against a `data` jsonb column so it can be used as a generated
  # column expression; LgDirectoryColumns::ACTIVE_SQL is the same rule phrased
  # against a `payload` alias inside the LG trigger.
  ACTIVE_FROM_DATA = <<~SQL.squish.freeze
    NOT (
      COALESCE(LOWER(BTRIM(data ->> 'deleted')), '') IN ('1', 'true', 'yes', 'deleted')
      OR COALESCE(LOWER(BTRIM(data ->> 'is_deleted')), '') IN ('1', 'true', 'yes', 'deleted')
      OR COALESCE(LOWER(BTRIM(data ->> 'discarded')), '') IN ('1', 'true', 'yes', 'deleted')
      OR (COALESCE(BTRIM(data ->> 'status'), '') <> '' AND LOWER(BTRIM(data ->> 'status')) <> 'active')
    )
  SQL

  # Delete flags only, for records whose `status` carries a workflow state
  # rather than an active/inactive flag -- bills move through "Pending at ...",
  # "Final Approved", "Paid", and none of those mean the row is gone.
  ACTIVE_FROM_DELETE_FLAGS = <<~SQL.squish.freeze
    NOT (
      COALESCE(LOWER(BTRIM(data ->> 'deleted')), '') IN ('1', 'true', 'yes', 'deleted')
      OR COALESCE(LOWER(BTRIM(data ->> 'is_deleted')), '') IN ('1', 'true', 'yes', 'deleted')
      OR COALESCE(LOWER(BTRIM(data ->> 'discarded')), '') IN ('1', 'true', 'yes', 'deleted')
    )
  SQL
end
