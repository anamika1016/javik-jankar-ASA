class UseTracenetAndCoordinatesForAflImportKey < ActiveRecord::Migration[8.1]
  def up
    remove_index :afls, name: "index_afls_on_import_key" if index_name_exists?(:afls, "index_afls_on_import_key")

    execute "UPDATE afls SET import_key = NULL"
    execute <<~SQL.squish
      WITH keyed_rows AS (
        SELECT
          id,
          encode(
            sha256(
              concat_ws(
                '|',
                lower(trim(tracenet_no)),
                to_char(longitude, 'FM999999999999990.00000000'),
                to_char(lattitude, 'FM999999999999990.00000000')
              )::bytea
            ),
            'hex'
          ) AS import_key,
          row_number() OVER (
            PARTITION BY
              lower(trim(tracenet_no)),
              to_char(longitude, 'FM999999999999990.00000000'),
              to_char(lattitude, 'FM999999999999990.00000000')
            ORDER BY id
          ) AS row_position
        FROM afls
        WHERE tracenet_no IS NOT NULL
          AND trim(tracenet_no) <> ''
          AND longitude IS NOT NULL
          AND lattitude IS NOT NULL
      )
      UPDATE afls
      SET import_key = keyed_rows.import_key
      FROM keyed_rows
      WHERE afls.id = keyed_rows.id
        AND keyed_rows.row_position = 1
    SQL

    add_index :afls, :import_key, unique: true, where: "import_key IS NOT NULL"
  end

  def down
    remove_index :afls, name: "index_afls_on_import_key" if index_name_exists?(:afls, "index_afls_on_import_key")
    execute "UPDATE afls SET import_key = NULL"
    add_index :afls, :import_key, unique: true, where: "import_key IS NOT NULL"
  end
end
