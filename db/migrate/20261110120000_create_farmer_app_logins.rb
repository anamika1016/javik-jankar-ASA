class CreateFarmerAppLogins < ActiveRecord::Migration[8.1]
  def change
    # One row per farmer who has signed in from the Android app. The farmer
    # master itself stays in the ASA register (farmer_details_by_identifier);
    # this table only records who logged in, when, and the identity snapshot
    # needed to list them on the web without calling the register per row.
    #
    # Aadhaar is deliberately not stored in full -- only the last four digits,
    # for display, plus a one-way digest so the same farmer is recognised
    # across logins. Lookups always go back to the register.
    create_table :farmer_app_logins do |t|
      t.string :farmer_external_id
      t.string :full_name
      t.string :mobile_no
      t.string :aadhaar_last4, limit: 4
      t.string :aadhaar_digest
      t.string :last_identifier_type
      t.string :father_husband_name
      t.string :village_name
      t.string :block_name
      t.string :district_name
      t.string :state_name
      t.string :fco_name
      t.string :ics_name
      t.string :tracenet_id
      t.integer :login_count, null: false, default: 0
      t.datetime :first_logged_in_at
      t.datetime :last_logged_in_at
      t.string :last_login_ip
      t.string :last_device
      t.string :last_app_version
      t.timestamps
    end

    add_index :farmer_app_logins, :farmer_external_id, unique: true,
      name: "index_farmer_app_logins_on_farmer_external_id"
    add_index :farmer_app_logins, :mobile_no
    add_index :farmer_app_logins, :aadhaar_digest
    # The list is always "newest login first", paged. A composite index
    # matching that exact order lets Postgres read a page straight off the
    # index instead of sorting the table.
    add_index :farmer_app_logins, [:last_logged_in_at, :id],
      order: { last_logged_in_at: :desc, id: :desc },
      name: "index_farmer_app_logins_on_recent_login"
  end
end
