class WidenAflCoordinateColumns < ActiveRecord::Migration[8.1]
  def change
    change_column :afls, :longitude, :decimal, precision: 20, scale: 8
    change_column :afls, :lattitude, :decimal, precision: 20, scale: 8
  end
end
