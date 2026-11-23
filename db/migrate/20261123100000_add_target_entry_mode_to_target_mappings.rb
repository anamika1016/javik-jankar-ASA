class AddTargetEntryModeToTargetMappings < ActiveRecord::Migration[8.1]
  # Target Mapping has always offered two ways to pick where the work happens:
  # ICS Wise, which drills FCO -> ICS -> Village out of the farmer master, and
  # Block Wise, which drills FCO -> Block -> Village out of the office/ASA
  # directory. Both land in the same row, and Block Wise reuses the ics_id /
  # ics_name columns to hold the block, so nothing recorded which of the two
  # was used. The dashboard now lets you look at one, the other, or both, so
  # the choice has to be stored instead of guessed on every read.
  def up
    add_column :target_mappings, :target_entry_mode, :string, null: false, default: "ics_wise"

    # Backfill: a row is ICS Wise when the name saved in ics_name is a real ICS,
    # i.e. it is known to the farmer master or to the JJ's own ICS mapping.
    # Anything else came from the Block picker. Matching on the name only is
    # deliberate -- block ids and ICS ids come from different directories and
    # collide, so an id match proves nothing.
    execute <<~SQL.squish
      UPDATE target_mappings t
      SET target_entry_mode = 'block_wise'
      WHERE COALESCE(BTRIM(t.ics_name), '') <> ''
        AND NOT EXISTS (
          SELECT 1 FROM afls a
          WHERE LOWER(BTRIM(a.ics_name)) = LOWER(BTRIM(t.ics_name))
        )
        AND NOT EXISTS (
          SELECT 1 FROM vrp_ics_mappings m
          WHERE LOWER(BTRIM(m.ics_name)) = LOWER(BTRIM(t.ics_name))
        )
    SQL

    add_index :target_mappings, [:target_entry_mode, :month_name],
      name: "index_target_mappings_on_entry_mode_and_month"
  end

  def down
    remove_index :target_mappings, name: "index_target_mappings_on_entry_mode_and_month"
    remove_column :target_mappings, :target_entry_mode
  end
end
