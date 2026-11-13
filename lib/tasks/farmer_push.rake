namespace :farmer_push do
  desc "Check push is wired up: credentials, registered devices, recent broadcasts"
  task status: :environment do
    if FcmClient.configured?
      puts "Firebase configured : yes"
    else
      puts "Firebase configured : NO"
      puts "  Put the Firebase service-account .json at either of these, then restart:"
      FcmClient.expected_key_paths.each do |path|
        puts "    #{path} #{File.exist?(path) ? '(exists but could not be read or parsed)' : '(not found)'}"
      end
      puts "  Or set FCM_SERVICE_ACCOUNT_FILE / FCM_SERVICE_ACCOUNT_JSON."
      puts "  Currently: FILE=#{ENV['FCM_SERVICE_ACCOUNT_FILE'].presence || '(unset)'} " \
           "JSON=#{ENV['FCM_SERVICE_ACCOUNT_JSON'].present? ? '(set)' : '(unset)'}"
    end
    puts "Registered devices  : #{FarmerDevice.count}"
    FarmerDevice.joins(:farmer_app_login).group("farmer_app_logins.state_name").count
      .each { |state, count| puts "  #{state.presence || '(no state)'}: #{count}" }

    puts "\nLast 10 broadcasts:"
    FarmerPushMessage.recent_first.limit(10).each do |message|
      puts format("  [%-7s] %-40s %s", message.status, message.title.to_s.first(40), message.summary)
      puts "            #{message.error}" if message.error.present?
    end
    puts "  (none yet)" if FarmerPushMessage.none?
  end

  desc "Send a test notification to one FCM token: rake 'farmer_push:test[<token>]'"
  task :test, [:token] => :environment do |_task, args|
    token = args[:token].to_s.strip
    abort "Usage: rake 'farmer_push:test[<fcm-token>]'" if token.blank?
    abort "Firebase is not configured. Set FCM_SERVICE_ACCOUNT_JSON and FCM_PROJECT_ID." unless FcmClient.configured?

    result = FcmClient.send_notification(
      tokens: [token],
      title: "Test notification",
      body: "If you can read this, push is working.",
      data: { type: "test", id: "0", deep_link: "farmer://news/0" }
    )

    if result.ok? && result.sent.positive?
      puts "Sent. Check the phone."
    else
      puts "Not sent. sent=#{result.sent} failed=#{result.failed} error=#{result.error.inspect}"
      puts "Firebase called this token dead; it is no longer valid." if result.dead_tokens.any?
    end
  end
end
