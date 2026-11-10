class CreateFarmerAppLoginEvents < ActiveRecord::Migration[8.1]
  def up
    # One row per sign-in, where farmer_app_logins keeps only the latest.
    # Without this a date filter could not answer "who logged in on the 8th":
    # a farmer who signed in on the 8th and again on the 10th would only ever
    # be found under the 10th.
    create_table :farmer_app_login_events do |t|
      t.references :farmer_app_login, null: false, foreign_key: true, index: false
      t.datetime :logged_in_at, null: false
      t.string :identifier_type
      t.string :ip
      t.string :device
      t.string :app_version
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.string :place
      t.timestamps
    end

    # The list is "logins on this date, newest first".
    add_index :farmer_app_login_events, :logged_in_at, order: { logged_in_at: :desc }
    add_index :farmer_app_login_events, [:farmer_app_login_id, :logged_in_at],
      name: "index_farmer_login_events_on_login_and_time"

    # Existing rows only know their last sign-in; carry that across so the
    # history that does exist is not lost when the list switches to events.
    execute <<~SQL.squish
      INSERT INTO farmer_app_login_events
        (farmer_app_login_id, logged_in_at, identifier_type, ip, device, app_version,
         latitude, longitude, place, created_at, updated_at)
      SELECT id, last_logged_in_at, last_identifier_type, last_login_ip, last_device,
             last_app_version, last_login_latitude, last_login_longitude, last_login_place,
             NOW(), NOW()
      FROM farmer_app_logins
      WHERE last_logged_in_at IS NOT NULL
    SQL
  end

  def down
    drop_table :farmer_app_login_events
  end
end
