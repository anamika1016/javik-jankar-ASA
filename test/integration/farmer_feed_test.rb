require "test_helper"
require_relative "../support/farmer_api_stubs"

# News and videos published from the web, read by the Android app.
# The point of the feature is the state split, so that is what is pinned down.
class FarmerFeedTest < ActionDispatch::IntegrationTest
  include FarmerApiStubs

  MP_FARMER = {
    "id" => 5, "full_name" => "Pooja", "mobile_no" => "7898071513",
    "aadhaar_no" => "111122223333",
    "land_details" => [{ "state_id" => 1, "district_id" => 36, "block_id" => 90, "village_id" => 10143 }]
  }.freeze
  ODISHA_FARMER = {
    "id" => 9, "full_name" => "Rayali Bai", "mobile_no" => "9000000001",
    "aadhaar_no" => "444455556666",
    "land_details" => [{ "state_id" => 8, "district_id" => 70, "block_id" => 120, "village_id" => 20001 }]
  }.freeze

  setup do
    @admin = User.create!(user_name: "feed_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  # --- publishing from the web ------------------------------------------

  test "news published for a state records that state, All States records none" do
    post farmer_news_index_path, params: {
      farmer_news_item: { title: "MP seed subsidy", body: "Apply by 30 November.", state_id: "1" }
    }
    assert_redirected_to farmer_news_index_path

    post farmer_news_index_path, params: {
      farmer_news_item: { title: "Nationwide advisory", body: "Sow after first rain.", state_id: "all" }
    }
    assert_redirected_to farmer_news_index_path

    state_news = FarmerNewsItem.find_by(title: "MP seed subsidy")
    all_news = FarmerNewsItem.find_by(title: "Nationwide advisory")

    assert_equal "1", state_news.state_id
    assert_not state_news.all_states?
    assert_nil all_news.state_id
    assert all_news.all_states?
    assert_equal "All States", all_news.state_label
    # The display name is what a reader wants under "By …".
    assert_equal "Admin", state_news.created_by
  end

  test "news without a headline is refused and says why" do
    assert_no_difference -> { FarmerNewsItem.count } do
      post farmer_news_index_path, params: { farmer_news_item: { title: "  ", state_id: "all" } }
    end

    assert_response :unprocessable_entity
    assert_select ".farmer-feed-errors", text: /Title can't be blank/
  end

  test "a video needs either a link or a file" do
    assert_no_difference -> { FarmerVideo.count } do
      post farmer_videos_path, params: { farmer_video: { title: "Soil health", state_id: "all" } }
    end

    assert_response :unprocessable_entity
    assert_select ".farmer-feed-errors", text: /Upload a video file or paste a video link/
  end

  test "a video published with a link is listed and playable" do
    post farmer_videos_path, params: {
      farmer_video: { title: "Soil health", state_id: "1", duration_label: "4:30",
                      video_url: "https://youtu.be/abc123" }
    }
    assert_redirected_to farmer_videos_path

    video = FarmerVideo.last
    assert_equal "https://youtu.be/abc123", video.playback_url
    assert_not video.uploaded?

    get farmer_videos_path
    assert_response :success
    assert_select "td", text: /Soil health/
    assert_select "a", text: "Play"
  end

  test "an uploaded video file is stored and served from this host" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new("not really a video"), "video/mp4", original_filename: "Kisan Training.mp4"
    )
    post farmer_videos_path, params: {
      farmer_video: { title: "Training clip", state_id: "all", video: file }
    }
    assert_redirected_to farmer_videos_path

    video = FarmerVideo.last
    assert video.uploaded?
    assert_match %r{\A/uploads/farmer_feed/\d+-[0-9a-f]+-kisan-training\.mp4\z}, video.video_path
    assert File.exist?(Rails.root.join("public", video.video_path.delete_prefix("/")))
  ensure
    path = FarmerVideo.last&.video_path
    FileUtils.rm_f(Rails.root.join("public", path.delete_prefix("/"))) if path
  end

  test "a file type that is not a video is refused rather than stored" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new("PK"), "application/zip", original_filename: "payload.zip"
    )
    assert_no_difference -> { FarmerVideo.count } do
      post farmer_videos_path, params: { farmer_video: { title: "Bad", state_id: "all", video: file } }
    end

    assert_response :unprocessable_entity
    assert_select ".farmer-feed-errors", text: /Allowed file types/
  end

  test "publishing can be deactivated and deleted from the list" do
    post farmer_news_index_path, params: { farmer_news_item: { title: "Temporary", state_id: "all" } }
    item = FarmerNewsItem.last

    patch toggle_status_farmer_news_path(item)
    assert_equal "Inactive", item.reload.status

    patch toggle_status_farmer_news_path(item)
    assert_equal "Active", item.reload.status

    assert_difference -> { FarmerNewsItem.count }, -1 do
      delete farmer_news_path(item)
    end
  end

  # --- what the app receives --------------------------------------------

  test "a farmer sees their own state's news plus All States, never another state's" do
    FarmerNewsItem.create!(title: "MP only", state_id: "1")
    FarmerNewsItem.create!(title: "Odisha only", state_id: "8")
    FarmerNewsItem.create!(title: "Everyone", state_id: nil)

    titles = app_feed(MP_FARMER, "/api/v1/farmer/news").map { |item| item["title"] }
    assert_includes titles, "MP only"
    assert_includes titles, "Everyone"
    assert_not_includes titles, "Odisha only"
  end

  test "a farmer in another state sees that state's feed instead" do
    FarmerNewsItem.create!(title: "MP only", state_id: "1")
    FarmerNewsItem.create!(title: "Odisha only", state_id: "8")
    FarmerNewsItem.create!(title: "Everyone", state_id: nil)

    titles = app_feed(ODISHA_FARMER, "/api/v1/farmer/news").map { |item| item["title"] }
    assert_equal ["Everyone", "Odisha only"].sort, titles.sort
  end

  test "deactivated news disappears from the app without being deleted" do
    item = FarmerNewsItem.create!(title: "Draft notice", state_id: nil)
    assert_equal ["Draft notice"], app_feed(MP_FARMER, "/api/v1/farmer/news").map { |n| n["title"] }

    item.update!(status: "Inactive")
    assert_empty app_feed(MP_FARMER, "/api/v1/farmer/news")
    assert FarmerNewsItem.exists?(item.id)
  end

  test "the app gets videos for its state with absolute URLs it can play" do
    FarmerVideo.create!(title: "MP clip", state_id: "1", video_path: "/uploads/farmer_feed/a.mp4",
      thumbnail_path: "/uploads/farmer_feed/a.jpg")
    FarmerVideo.create!(title: "Linked clip", state_id: nil, video_url: "https://youtu.be/abc123")
    FarmerVideo.create!(title: "Odisha clip", state_id: "8", video_url: "https://youtu.be/zzz")

    videos = app_feed(ODISHA_FARMER, "/api/v1/farmer/videos")
    titles = videos.map { |v| v["title"] }
    assert_includes titles, "Odisha clip"
    assert_includes titles, "Linked clip"
    assert_not_includes titles, "MP clip"

    uploaded = app_feed(MP_FARMER, "/api/v1/farmer/videos").find { |v| v["title"] == "MP clip" }
    assert_match %r{\Ahttps?://.+/uploads/farmer_feed/a\.mp4\z}, uploaded["video_url"]
    assert_match %r{\Ahttps?://.+/uploads/farmer_feed/a\.jpg\z}, uploaded["thumbnail_url"]
    assert uploaded["uploaded"]

    linked = app_feed(MP_FARMER, "/api/v1/farmer/videos").find { |v| v["title"] == "Linked clip" }
    assert_equal "https://youtu.be/abc123", linked["video_url"]
    assert_not linked["uploaded"]
  end

  test "newest is first so the app does not have to sort" do
    FarmerNewsItem.create!(title: "Older", state_id: nil, published_at: 3.days.ago)
    FarmerNewsItem.create!(title: "Newest", state_id: nil, published_at: 1.hour.ago)
    FarmerNewsItem.create!(title: "Middle", state_id: nil, published_at: 1.day.ago)

    assert_equal %w[Newest Middle Older], app_feed(MP_FARMER, "/api/v1/farmer/news").map { |n| n["title"] }
  end

  test "the feed refuses a request with no farmer token" do
    FarmerNewsItem.create!(title: "Everyone", state_id: nil)

    get "/api/v1/farmer/news"
    assert_response :unauthorized

    # A staff token is not a farmer token.
    get "/api/v1/farmer/news", headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(@admin)}" }
    assert_response :unauthorized
  end

  test "the whole feed is read in one query, however many items there are" do
    10.times { |i| FarmerNewsItem.create!(title: "News #{i}", state_id: nil) }
    login = FarmerAppLogin.record_login!(farmer: MP_FARMER, identifier_type: "mobile")
    token = FarmerApiToken.encode(login)

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] if payload[:sql] =~ /FROM "farmer_news"/
    end
    get "/api/v1/farmer/news", headers: { "Authorization" => "Bearer #{token}" }
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_response :success
    assert_equal 10, JSON.parse(response.body)["news"].size
    assert_equal 1, queries.size, "the feed must not query per item"
  end

  private

  # Signs a farmer in the way the app does, then reads the feed.
  def app_feed(farmer, path)
    login = FarmerAppLogin.record_login!(farmer: farmer, identifier_type: "mobile")
    get path, headers: { "Authorization" => "Bearer #{FarmerApiToken.encode(login)}" }
    assert_response :success

    body = JSON.parse(response.body)
    body["news"] || body["videos"]
  end
end
