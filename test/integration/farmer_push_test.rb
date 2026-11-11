require "test_helper"
require_relative "../support/farmer_api_stubs"

# Push notifications for news and videos: device registration, who a
# broadcast reaches, and what happens when Firebase is unhappy.
class FarmerPushTest < ActionDispatch::IntegrationTest
  include FarmerApiStubs
  include ActiveJob::TestHelper

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
    @admin = User.create!(user_name: "push_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    post login_path, params: { login: @admin.user_name, password: "secret" }
    @sent = []
    stub_fcm
  end

  teardown { unstub_fcm }

  # --- device registration ----------------------------------------------

  test "a signed-in farmer can register the phone for notifications" do
    login = sign_in(MP_FARMER)

    post "/api/v1/farmer/devices",
      params: { fcm_token: "tok-mp-1", platform: "android", app_version: "1.0.4" }.to_json,
      headers: auth(login)

    assert_response :success
    assert json_body["success"]
    device = FarmerDevice.sole
    assert_equal "tok-mp-1", device.token
    assert_equal login.id, device.farmer_app_login_id
    assert_equal "1.0.4", device.app_version
  end

  test "registering the same phone twice keeps one row and refreshes it" do
    login = sign_in(MP_FARMER)

    2.times do
      post "/api/v1/farmer/devices", params: { fcm_token: "tok-mp-1" }.to_json, headers: auth(login)
      assert_response :success
    end

    assert_equal 1, FarmerDevice.count
  end

  # A handed-down phone must not keep getting the previous farmer's feed.
  test "the same phone signing in as another farmer moves the token over" do
    first = sign_in(MP_FARMER)
    post "/api/v1/farmer/devices", params: { fcm_token: "shared-phone" }.to_json, headers: auth(first)

    second = sign_in(ODISHA_FARMER)
    post "/api/v1/farmer/devices", params: { fcm_token: "shared-phone" }.to_json, headers: auth(second)
    assert_response :success

    assert_equal 1, FarmerDevice.count
    assert_equal second.id, FarmerDevice.sole.farmer_app_login_id
  end

  test "registration without a token says which field is missing" do
    login = sign_in(MP_FARMER)

    post "/api/v1/farmer/devices", params: {}.to_json, headers: auth(login)
    assert_response :unprocessable_entity
    assert_equal "missing_fcm_token", json_body["error"]
  end

  test "registration without a farmer token is refused" do
    post "/api/v1/farmer/devices", params: { fcm_token: "tok" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
    assert_equal "missing_token", json_body["error"]
    assert_equal 0, FarmerDevice.count
  end

  test "signing out stops notifications for that phone" do
    login = sign_in(MP_FARMER)
    post "/api/v1/farmer/devices", params: { fcm_token: "tok-mp-1" }.to_json, headers: auth(login)

    delete "/api/v1/farmer/devices", params: { fcm_token: "tok-mp-1" }.to_json, headers: auth(login)
    assert_response :success
    assert_equal 0, FarmerDevice.count
  end

  # --- who a broadcast reaches ------------------------------------------

  test "publishing news notifies that state's phones and nobody else's" do
    register("tok-mp", MP_FARMER)
    register("tok-odisha", ODISHA_FARMER)

    perform_enqueued_jobs do
      post farmer_news_index_path, params: {
        farmer_news_item: { title: "MP seed subsidy", body: "Apply by 30 November.", state_id: "1" }
      }
    end

    assert_equal ["tok-mp"], @sent.flat_map { |call| call[:tokens] }
    message = FarmerNewsItem.last.last_push_message
    assert_equal "Sent", message.status
    assert_equal 1, message.sent_count
    assert_equal "MP seed subsidy", message.title
  end

  test "an All States post reaches every registered phone" do
    register("tok-mp", MP_FARMER)
    register("tok-odisha", ODISHA_FARMER)

    perform_enqueued_jobs do
      post farmer_news_index_path, params: {
        farmer_news_item: { title: "Nationwide advisory", state_id: "all" }
      }
    end

    assert_equal %w[tok-mp tok-odisha].sort, @sent.flat_map { |call| call[:tokens] }.sort
  end

  test "publishing a video notifies with a deep link the app can open" do
    register("tok-mp", MP_FARMER)

    perform_enqueued_jobs do
      post farmer_videos_path, params: {
        farmer_video: { title: "Soil health", description: "How to read a soil card.",
                        state_id: "1", video_url: "youtu.be/abc123XYZ" }
      }
    end

    call = @sent.sole
    assert_equal "Soil health", call[:title]
    assert_equal "How to read a soil card.", call[:body]
    assert_equal "video", call[:data][:type]
    assert_equal "farmer://videos/#{FarmerVideo.last.id}", call[:data][:deep_link]
  end

  test "a post with no description still carries readable notification text" do
    register("tok-mp", MP_FARMER)

    perform_enqueued_jobs do
      post farmer_news_index_path, params: { farmer_news_item: { title: "Headline only", state_id: "1" } }
    end

    assert_equal "Tap to read the latest update.", @sent.sole[:body]
  end

  test "publishing does not make the admin wait on Firebase" do
    register("tok-mp", MP_FARMER)

    assert_enqueued_with(job: FarmerPushBroadcastJob) do
      post farmer_news_index_path, params: { farmer_news_item: { title: "Queued", state_id: "1" } }
    end

    assert_redirected_to farmer_news_index_path
    assert_empty @sent, "nothing should be sent inside the web request"
    assert_equal "Pending", FarmerNewsItem.last.last_push_message.status
  end

  # --- what goes wrong ---------------------------------------------------

  test "a state with no registered phone is recorded as skipped, not failed" do
    perform_enqueued_jobs do
      post farmer_news_index_path, params: { farmer_news_item: { title: "Nobody yet", state_id: "1" } }
    end

    message = FarmerNewsItem.last.last_push_message
    assert_equal "Skipped", message.status
    assert_match(/registered for notifications yet/, message.error)
  end

  test "with Firebase unconfigured the post still publishes and says why" do
    register("tok-mp", MP_FARMER)
    unstub_fcm
    with_unconfigured_fcm do
      perform_enqueued_jobs do
        post farmer_news_index_path, params: { farmer_news_item: { title: "No firebase", state_id: "1" } }
      end
    end

    assert_equal 1, FarmerNewsItem.count, "publishing must not depend on push working"
    message = FarmerNewsItem.last.last_push_message
    assert_equal "Failed", message.status
    assert_match(/Firebase is not configured/, message.error)
  end

  test "a token Firebase calls dead is deleted so it is not retried forever" do
    register("tok-dead", MP_FARMER)
    register("tok-live", MP_FARMER)
    @fcm_result = FcmClient::Result.new(sent: 1, failed: 1, dead_tokens: ["tok-dead"])

    perform_enqueued_jobs do
      post farmer_news_index_path, params: { farmer_news_item: { title: "Cleanup", state_id: "1" } }
    end

    assert_equal ["tok-live"], FarmerDevice.pluck(:token)
  end

  test "a deactivated post is not pushed even if the job runs later" do
    register("tok-mp", MP_FARMER)
    post farmer_news_index_path, params: { farmer_news_item: { title: "Pulled back", state_id: "1" } }
    item = FarmerNewsItem.last
    item.update!(status: "Inactive")

    perform_enqueued_jobs

    assert_empty @sent
    assert_equal "Skipped", item.last_push_message.reload.status
  end

  test "the web list reports whether the notification went out" do
    register("tok-mp", MP_FARMER)
    perform_enqueued_jobs do
      post farmer_news_index_path, params: { farmer_news_item: { title: "Delivered", state_id: "1" } }
    end

    get farmer_news_index_path
    assert_response :success
    assert_select "th", text: "Notification"
    assert_select ".status-pill", text: "Sent"
    assert_select ".farmer-sub", text: /Sent to 1 of 1 device/
  end

  test "the status task reports credentials, devices and recent broadcasts" do
    register("tok-mp", MP_FARMER)
    perform_enqueued_jobs do
      post farmer_news_index_path, params: { farmer_news_item: { title: "Delivered", state_id: "1" } }
    end

    output = capture_rake("farmer_push:status")
    assert_match(/Firebase configured : yes/, output)
    assert_match(/Registered devices  : 1/, output)
    assert_match(/\[Sent\s*\] Delivered/, output)
  end

  test "the status task names the missing credentials instead of crashing" do
    unstub_fcm
    output = with_unconfigured_fcm { capture_rake("farmer_push:status") }

    assert_match(/Firebase configured : NO/, output)
    assert_match(/FCM_SERVICE_ACCOUNT_JSON/, output)
  end

  private

  # $stdout is swapped first so the ensure always has something to put back;
  # loading the tasks can raise, and restoring nil breaks every later test.
  def capture_rake(task)
    original = $stdout
    out = StringIO.new
    begin
      require "rake"
      Rails.application.load_tasks unless Rake::Task.task_defined?(task)
      Rake::Task[task].reenable
      $stdout = out
      Rake::Task[task].invoke
    ensure
      $stdout = original
    end
    out.string
  end

  def json_body = JSON.parse(response.body)

  def auth(login)
    { "Content-Type" => "application/json",
      "Authorization" => "Bearer #{FarmerApiToken.encode(login)}" }
  end

  def sign_in(farmer)
    FarmerAppLogin.record_login!(farmer: farmer, identifier_type: "mobile")
  end

  def register(token, farmer)
    FarmerDevice.register!(login: sign_in(farmer), token: token)
  end

  # Firebase with no credentials: send_notification is the real one, which
  # refuses before touching the network.
  def with_unconfigured_fcm
    FcmClient.singleton_class.class_eval do
      alias_method :__original_configured?, :configured?
      define_method(:configured?) { false }
    end
    yield
  ensure
    FcmClient.singleton_class.class_eval do
      remove_method :configured?
      alias_method :configured?, :__original_configured?
      remove_method :__original_configured?
    end
  end

  # Records what would have gone to Firebase. No test may reach it for real.
  def stub_fcm
    sent = @sent
    holder = self
    FcmClient.singleton_class.class_eval do
      alias_method :__original_send_notification, :send_notification
      alias_method :__original_configured?, :configured?
      define_method(:configured?) { true }
      define_method(:send_notification) do |tokens:, title:, body:, data: {}|
        sent << { tokens: Array(tokens), title: title, body: body, data: data }
        holder.instance_variable_get(:@fcm_result) ||
          FcmClient::Result.new(sent: Array(tokens).size, failed: 0, dead_tokens: [])
      end
    end
  end

  def unstub_fcm
    return unless FcmClient.singleton_class.method_defined?(:__original_send_notification)

    FcmClient.singleton_class.class_eval do
      remove_method :send_notification
      remove_method :configured?
      alias_method :send_notification, :__original_send_notification
      alias_method :configured?, :__original_configured?
      remove_method :__original_send_notification
      remove_method :__original_configured?
    end
  end
end
