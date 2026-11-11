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
    assert_select "button.farmer-video-play[data-video-kind=youtube]"
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

  # The app shipped without an Authorization header and got a bare 401, which
  # told the developer nothing. Each refusal now names its own cause.
  # The whole chain the app has to walk, exactly as the Android client does
  # it: OTP, verify, then the two feeds with the token from verify.
  test "OTP login to news and videos works end to end with the verify token" do
    FarmerNewsItem.create!(title: "MP seed subsidy", body: "Apply by 30 November.", state_id: "1")
    FarmerNewsItem.create!(title: "Nationwide advisory", state_id: nil)
    FarmerNewsItem.create!(title: "Odisha only", state_id: "8")
    FarmerVideo.create!(title: "Soil health", state_id: "1", video_url: "https://youtu.be/abc123")
    FarmerVideo.create!(title: "Odisha clip", state_id: "8", video_url: "https://youtu.be/zzz")

    token = nil
    # The register answers with state_id 1; the master turns that into a name.
    AsaLocationNames.stub_names(state: { "1" => "Madhya Pradesh" }) do
      stub_farmer_apis(farmer: MP_FARMER) do |sent_otps|
        post "/api/v1/farmer/login/otp/send",
          params: { mobile_no: "7898071513" }.to_json,
          headers: { "Content-Type" => "application/json" }
        assert_response :ok

        post "/api/v1/farmer/login/otp/verify",
          params: { otp_token: json_body["otp_token"], otp: sent_otps.last }.to_json,
          headers: { "Content-Type" => "application/json" }
        assert_response :ok
        token = json_body["token"]
        assert token.present?, "verify must hand back a token"
      end
    end

    auth = { "Authorization" => "Bearer #{token}" }

    get "/api/v1/farmer/news", headers: auth
    assert_response :success
    assert json_body["success"]
    assert_equal "Madhya Pradesh", json_body["state"]
    assert_equal ["Nationwide advisory", "MP seed subsidy"].sort,
      json_body["news"].map { |n| n["title"] }.sort

    get "/api/v1/farmer/videos", headers: auth
    assert_response :success
    assert_equal ["Soil health"], json_body["videos"].map { |v| v["title"] }
    assert_equal "https://youtu.be/abc123", json_body["videos"].first["video_url"]
  end

  test "a farmer whose register record has no state still gets the All States feed" do
    FarmerNewsItem.create!(title: "Everyone", state_id: nil)
    FarmerNewsItem.create!(title: "MP only", state_id: "1")
    stateless = MP_FARMER.merge("id" => 77, "aadhaar_no" => "777788889999", "land_details" => [])

    titles = app_feed(stateless, "/api/v1/farmer/news").map { |n| n["title"] }
    assert_equal ["Everyone"], titles
    assert_nil FarmerAppLogin.find_by(farmer_external_id: "77").state_id
  end

  # A url_field in the browser silently refuses to submit a link typed without
  # a scheme, which is how pasted links were being lost.
  test "a link pasted without https is saved, not dropped" do
    post farmer_news_index_path, params: {
      farmer_news_item: { title: "Advisory", state_id: "all", link_url: "example.com/news" }
    }
    assert_redirected_to farmer_news_index_path
    assert_equal "https://example.com/news", FarmerNewsItem.last.link_url

    post farmer_videos_path, params: {
      farmer_video: { title: "Clip", state_id: "all", video_url: "youtu.be/dQw4w9WgXcQ" }
    }
    assert_redirected_to farmer_videos_path
    assert_equal "https://youtu.be/dQw4w9WgXcQ", FarmerVideo.last.video_url
  end

  test "a news link reaches the app and the web list" do
    FarmerNewsItem.create!(title: "Advisory", state_id: nil, link_url: "example.com/news")

    get farmer_news_index_path
    assert_response :success
    assert_select "a[href='https://example.com/news']", text: "Open"

    item = app_feed(MP_FARMER, "/api/v1/farmer/news").first
    assert_equal "https://example.com/news", item["link_url"]
  end

  test "a YouTube link is turned into something a player can embed" do
    FarmerVideo.create!(title: "Clip", state_id: nil, video_url: "https://www.youtube.com/watch?v=abc123XYZ")

    video = app_feed(MP_FARMER, "/api/v1/farmer/videos").first
    assert_equal "youtube", video["source_type"]
    assert_equal "abc123XYZ", video["youtube_id"]
    assert_equal "https://www.youtube.com/embed/abc123XYZ", video["embed_url"]
    assert_not video["uploaded"]
  end

  test "an uploaded file is embeddable at its own absolute URL" do
    FarmerVideo.create!(title: "Clip", state_id: nil, video_path: "/uploads/farmer_feed/a.mp4")

    video = app_feed(MP_FARMER, "/api/v1/farmer/videos").first
    assert_equal "file", video["source_type"]
    assert_nil video["youtube_id"]
    assert_match %r{\Ahttps?://.+/uploads/farmer_feed/a\.mp4\z}, video["embed_url"]
  end

  test "the video list plays in place instead of opening a new tab" do
    FarmerVideo.create!(title: "Clip", state_id: nil, video_url: "https://youtu.be/abc123XYZ",
      thumbnail_path: "/uploads/farmer_feed/a.jpg")

    get farmer_videos_path
    assert_response :success
    assert_select "button.farmer-video-play[data-video-kind=youtube]"
    assert_select "button.farmer-video-play[data-video-embed='https://www.youtube.com/embed/abc123XYZ']"
    assert_select "dialog#farmer-video-dialog"
    # Nothing should send the admin away from the page to watch.
    assert_select "a[target=_blank]", text: "Play", count: 0
  end

  test "the feed says which state it answered for" do
    FarmerNewsItem.create!(title: "Everyone", state_id: nil)
    login = FarmerAppLogin.record_login!(farmer: MP_FARMER, identifier_type: "mobile")

    get "/api/v1/farmer/news", headers: { "Authorization" => "Bearer #{FarmerApiToken.encode(login)}" }
    assert_response :success
    assert_equal "1", json_body["state_id"]
    assert_equal 1, json_body["count"]
  end

  test "a request with no Authorization header says exactly that" do
    FarmerNewsItem.create!(title: "Everyone", state_id: nil)

    get "/api/v1/farmer/news"
    assert_response :unauthorized
    assert_equal "missing_token", json_body["error"]
    assert_match(/Authorization header is missing/, json_body["message"])
    assert_match(%r{/api/v1/farmer/login/otp/verify}, json_body["message"])
  end

  test "a staff token on the farmer feed is named as the wrong token type" do
    get "/api/v1/farmer/videos",
      headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(@admin)}" }

    assert_response :unauthorized
    assert_equal "wrong_token_type", json_body["error"]
    assert_match(/staff or Jeevika Jankar token/, json_body["message"])
  end

  test "a farmer token that has expired asks for a fresh login" do
    login = FarmerAppLogin.record_login!(farmer: MP_FARMER, identifier_type: "mobile")
    token = FarmerApiToken.encode(login, expires_in: 1.minute)

    travel_to(2.minutes.from_now) do
      get "/api/v1/farmer/news", headers: { "Authorization" => "Bearer #{token}" }
    end

    assert_response :unauthorized
    assert_equal "invalid_token", json_body["error"]
    assert_match(/Please login again/, json_body["message"])
  end

  test "the token also works as a query parameter for clients that cannot set headers" do
    FarmerNewsItem.create!(title: "Everyone", state_id: nil)
    login = FarmerAppLogin.record_login!(farmer: MP_FARMER, identifier_type: "mobile")

    get "/api/v1/farmer/news", params: { token: FarmerApiToken.encode(login) }
    assert_response :success
    assert_equal ["Everyone"], json_body["news"].map { |n| n["title"] }
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

  def json_body
    JSON.parse(response.body)
  end

  # Signs a farmer in the way the app does, then reads the feed.
  def app_feed(farmer, path)
    login = FarmerAppLogin.record_login!(farmer: farmer, identifier_type: "mobile")
    get path, headers: { "Authorization" => "Bearer #{FarmerApiToken.encode(login)}" }
    assert_response :success

    body = JSON.parse(response.body)
    body["news"] || body["videos"]
  end
end
