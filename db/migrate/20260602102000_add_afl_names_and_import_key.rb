class AddAflNamesAndImportKey < ActiveRecord::Migration[8.1]
  def up
    add_column :afls, :fpo_name, :string
    add_column :afls, :ics_name, :string
    add_column :afls, :village_name, :string
    add_column :afls, :import_key, :string

    execute <<~SQL.squish
      WITH keyed_rows AS (
        SELECT
          id,
          encode(
            sha256(
              concat_ws(
                '|',
                lower(trim(coalesce(slip_no, ''))),
                lower(trim(coalesce(tracenet_no, ''))),
                lower(trim(coalesce(farmer_name, ''))),
                lower(trim(coalesce(father_name, ''))),
                lower(trim(coalesce(mobile_no, ''))),
                coalesce(purchase_date::text, ''),
                lower(trim(coalesce(purchase_product, ''))),
                lower(trim(coalesce(purchase_product_type, ''))),
                lower(trim(coalesce(khasara_no, ''))),
                lower(trim(coalesce(fco_id, ''))),
                lower(trim(coalesce(fpo_id, ''))),
                lower(trim(coalesce(ics_id, ''))),
                lower(trim(coalesce(village_id, '')))
              )::bytea
            ),
            'hex'
          ) AS import_key,
          row_number() OVER (
            PARTITION BY concat_ws(
              '|',
              lower(trim(coalesce(slip_no, ''))),
              lower(trim(coalesce(tracenet_no, ''))),
              lower(trim(coalesce(farmer_name, ''))),
              lower(trim(coalesce(father_name, ''))),
              lower(trim(coalesce(mobile_no, ''))),
              coalesce(purchase_date::text, ''),
              lower(trim(coalesce(purchase_product, ''))),
              lower(trim(coalesce(purchase_product_type, ''))),
              lower(trim(coalesce(khasara_no, ''))),
              lower(trim(coalesce(fco_id, ''))),
              lower(trim(coalesce(fpo_id, ''))),
              lower(trim(coalesce(ics_id, ''))),
              lower(trim(coalesce(village_id, '')))
            )
            ORDER BY id
          ) AS row_position
        FROM afls
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
    remove_index :afls, :import_key
    remove_column :afls, :import_key
    remove_column :afls, :village_name
    remove_column :afls, :ics_name
    remove_column :afls, :fpo_name
  end
end
