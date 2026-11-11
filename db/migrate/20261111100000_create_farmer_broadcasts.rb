class CreateFarmerBroadcasts < ActiveRecord::Migration[8.1]
  def change
    # News and videos published to the Android app, either to one state or to
    # every state. A null state_id means "All States" -- the farmer's own
    # state is matched by id rather than by name, because the register spells
    # state names inconsistently and an id cannot be mistyped.
    create_table :farmer_news do |t|
      t.string :title, null: false
      t.text :body
      t.string :link_url
      t.string :image_path
      t.string :state_id
      t.string :state_name
      t.string :status, null: false, default: "Active"
      t.datetime :published_at, null: false
      t.string :created_by
      t.timestamps
    end

    create_table :farmer_videos do |t|
      t.string :title, null: false
      t.text :description
      t.string :video_url
      t.string :video_path
      t.string :thumbnail_path
      t.string :duration_label
      t.string :state_id
      t.string :state_name
      t.string :status, null: false, default: "Active"
      t.datetime :published_at, null: false
      t.string :created_by
      t.timestamps
    end

    # The app always asks the same question: active items for my state or for
    # all states, newest first. One index answers it without a sort.
    add_index :farmer_news, [:status, :state_id, :published_at],
      order: { published_at: :desc }, name: "index_farmer_news_on_feed"
    add_index :farmer_videos, [:status, :state_id, :published_at],
      order: { published_at: :desc }, name: "index_farmer_videos_on_feed"

    # Which state's feed a farmer gets. Resolved at login from the register.
    add_column :farmer_app_logins, :state_id, :string
    add_index :farmer_app_logins, :state_id
  end
end
