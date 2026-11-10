class AddFarmerLoginLockAndContext < ActiveRecord::Migration[8.1]
  def change
    # Wrong-OTP lockout, counted per mobile number rather than per OTP.
    # Counting per OTP would let someone keep requesting fresh OTPs and guess
    # three times against each one forever.
    create_table :farmer_login_locks do |t|
      t.string :mobile_no, null: false
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_until
      t.datetime :last_failed_at
      t.timestamps
    end
    add_index :farmer_login_locks, :mobile_no, unique: true
    add_index :farmer_login_locks, :locked_until

    # Where the login came from. The app sends its coordinates when the farmer
    # has granted location permission; IP is recorded either way.
    change_table :farmer_app_logins, bulk: true do |t|
      t.decimal :last_login_latitude, precision: 10, scale: 7
      t.decimal :last_login_longitude, precision: 10, scale: 7
      t.string :last_login_place
    end
  end
end
