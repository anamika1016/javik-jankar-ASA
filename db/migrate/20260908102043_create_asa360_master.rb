class CreateAsa360Master < ActiveRecord::Migration[8.1]
  def change
    create_table :asa360_master do |t|
      t.string :o_type, limit: 50
      t.string :o_name, limit: 200
      t.integer :o_id
    end
  end
end
