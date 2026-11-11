class CreateFarmerPushNotifications < ActiveRecord::Migration[8.1]
  def change
    # The FCM token a farmer's phone registers after logging in. One row per
    # device, not per farmer: a farmer may sign in on a new handset, and the
    # old token has to keep working until FCM says it is dead.
    create_table :farmer_devices do |t|
      t.references :farmer_app_login, null: false, foreign_key: true, index: false
      t.string :token, null: false
      t.string :platform
      t.string :app_version
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    # A token belongs to exactly one farmer. Re-registering it after a
    # different farmer signs in on the same phone must move it, not duplicate.
    add_index :farmer_devices, :token, unique: true
    add_index :farmer_devices, [:farmer_app_login_id, :last_seen_at],
      name: "index_farmer_devices_on_login_and_seen"

    # What was pushed, to how many phones, and whether it worked. Without this
    # "the farmers did not get the notification" is unanswerable.
    create_table :farmer_push_messages do |t|
      t.string :notifiable_type, null: false
      t.bigint :notifiable_id, null: false
      t.string :title
      t.text :body
      t.string :state_id
      t.integer :device_count, null: false, default: 0
      t.integer :sent_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.string :status, null: false, default: "Pending"
      t.text :error
      t.datetime :sent_at
      t.timestamps
    end

    add_index :farmer_push_messages, [:notifiable_type, :notifiable_id],
      name: "index_farmer_push_messages_on_notifiable"
    add_index :farmer_push_messages, :created_at, order: { created_at: :desc }
  end
end
