class CreateAfls < ActiveRecord::Migration[8.1]
  def change
    create_table :afls do |t|
      t.string :fco_id
      t.string :fco
      t.string :fpo_id
      t.string :ics_id
      t.string :village_id
      t.string :ginning_id
      t.string :broker_id
      t.string :farmer_name
      t.string :father_name
      t.string :tracenet_no
      t.decimal :total_farm_area, precision: 18, scale: 4
      t.decimal :purchase_quantity_amount, precision: 18, scale: 4
      t.decimal :estimate_quantity, precision: 18, scale: 4
      t.decimal :purchase_quantity, precision: 18, scale: 4
      t.date :purchase_date
      t.string :dispoce
      t.string :ip
      t.date :date
      t.decimal :estimate_quantity_admin, precision: 18, scale: 4
      t.string :slip_no
      t.string :mobile_no
      t.string :purchase_product
      t.string :purchase_product_type
      t.string :khasara_no
      t.decimal :longitude, precision: 20, scale: 8
      t.decimal :lattitude, precision: 20, scale: 8
      t.string :aadhar
      t.string :reg_type
      t.string :fy
      t.string :qr_aadhar
      t.string :qr_mobile
      t.text :qrcode
      t.datetime :qrcode_date
      t.string :status

      t.timestamps
    end

    add_index :afls, :farmer_name
    add_index :afls, :mobile_no
    add_index :afls, :tracenet_no
    add_index :afls, :slip_no
  end
end
