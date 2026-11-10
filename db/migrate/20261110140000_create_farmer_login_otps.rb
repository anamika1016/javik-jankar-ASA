class CreateFarmerLoginOtps < ActiveRecord::Migration[8.1]
  def change
    # Single-use enforcement and the wrong-attempt counter for farmer login.
    #
    # These were held in Rails.cache first, which was wrong: a cache is
    # allowed to lose entries, and losing one here silently re-enables OTP
    # replay and unlimited guessing. The test environment uses :null_store,
    # which made that failure total -- a used OTP verified a second time.
    #
    # The OTP is stored only as a SHA-256 digest, and the farmer's register
    # payload is deliberately not stored here: it carries an Aadhaar number.
    create_table :farmer_login_otps do |t|
      t.string :jti, null: false
      t.string :mobile_no, null: false
      t.string :identifier_type
      t.string :aadhaar_digest
      t.string :otp_digest, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :consumed_at
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :farmer_login_otps, :jti, unique: true
    # Resend throttling asks "was one issued for this mobile just now".
    add_index :farmer_login_otps, [:mobile_no, :created_at]
    # Lets expired rows be swept without scanning the table.
    add_index :farmer_login_otps, :expires_at
  end
end
