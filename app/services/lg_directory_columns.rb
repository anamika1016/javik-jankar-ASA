# The one definition of how a module_records payload maps onto the lg_* table
# columns, so the backfill migration, the database trigger and LgDirectory#sync!
# cannot drift apart.
#
# The same field goes by different names depending on which master wrote the
# row -- village-master stores the block as "block", lg-directory-list as
# "cd_block_name", block-master as "block_name" -- so each column takes the
# first alias present. The alias lists come from LgDirectoryImporter's
# MODULE_DEFINITIONS, which is what writes these payloads.
module LgDirectoryColumns
  ALIASES = {
    "state_name" => %w[state_name state],
    "state_code" => %w[state_code],
    "district_name" => %w[district_name district],
    "district_code" => %w[district_code],
    "sub_district_name" => %w[sub_district_name sub_district],
    "sub_district_code" => %w[sub_district_code],
    "block_name" => %w[block_name cd_block_name block],
    "block_code" => %w[block_code cd_block_code],
    "gram_panchayat_name" => %w[gram_panchayat_name gram_panchayat],
    "gp_code" => %w[gp_code],
    "village_name" => %w[village_name village],
    "village_code" => %w[village_code]
  }.freeze

  # Mirrors active_module_record?: any of the three delete flags set, or a
  # status that is present and not "Active", means inactive. Blank is active.
  ACTIVE_SQL = <<~SQL.squish.freeze
    NOT (
      COALESCE(LOWER(BTRIM(payload ->> 'deleted')), '') IN ('1', 'true', 'yes', 'deleted')
      OR COALESCE(LOWER(BTRIM(payload ->> 'is_deleted')), '') IN ('1', 'true', 'yes', 'deleted')
      OR COALESCE(LOWER(BTRIM(payload ->> 'discarded')), '') IN ('1', 'true', 'yes', 'deleted')
      OR (COALESCE(BTRIM(payload ->> 'status'), '') <> '' AND LOWER(BTRIM(payload ->> 'status')) <> 'active')
    )
  SQL
end
