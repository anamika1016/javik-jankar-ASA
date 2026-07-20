class DisableAflDuplicateImportIndex < ActiveRecord::Migration[8.1]
  def up
    remove_index :afls, name: "index_afls_on_import_key" if index_name_exists?(:afls, "index_afls_on_import_key")
    execute "UPDATE afls SET import_key = NULL"
  end

  def down
    add_index :afls, :import_key, unique: true, where: "import_key IS NOT NULL"
  end
end
