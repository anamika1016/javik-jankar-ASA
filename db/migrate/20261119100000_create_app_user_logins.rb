class CreateAppUserLogins < ActiveRecord::Migration[8.1]
  def change
    # One row per sign-in from the Jeevika Jankar / staff mobile app. Nothing
    # recorded these before: the API handed out a token and kept no trace, so
    # "who used the app today" had no answer.
    #
    # Identity is copied in rather than joined: a Jeevika Jankar may be
    # renamed or moved to another office later, and the login list has to
    # keep showing who they were at the time.
    create_table :app_user_logins do |t|
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :name
      t.string :username
      t.string :mobile_no
      t.string :role
      t.string :office_name
      t.string :fcoc
      t.string :login_method, null: false, default: "password"
      t.string :ip
      t.string :device
      t.string :app_version
      t.datetime :logged_in_at, null: false
      t.timestamps
    end

    # The list is always "logins on this date, newest first".
    add_index :app_user_logins, :logged_in_at, order: { logged_in_at: :desc }
    # "How often does this person use the app" reads one person's history.
    add_index :app_user_logins, [:record_type, :record_id, :logged_in_at],
      name: "index_app_user_logins_on_user_and_time"
  end
end
