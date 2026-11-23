class BackfillAppUserLoginOffice < ActiveRecord::Migration[8.1]
  # Rows written before the office fallback existed have one side blank: a
  # Jeevika Jankar kept only fcoc, a staff user only office_name, because the
  # two models hold their office in different columns. Fill the empty side in
  # from the one that was captured so the existing history reads the same as
  # new rows.
  #
  # Only blanks are written; nothing already recorded is overwritten.
  def up
    execute <<~SQL.squish
      UPDATE app_user_logins
      SET office_name = fcoc
      WHERE COALESCE(BTRIM(office_name), '') = ''
        AND COALESCE(BTRIM(fcoc), '') <> ''
    SQL
  end

  def down
    # Nothing to undo: this only filled in blanks, and which rows were blank
    # is no longer knowable.
  end
end
