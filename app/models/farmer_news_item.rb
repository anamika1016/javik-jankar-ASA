# A news post shown in the Android farmer app.
class FarmerNewsItem < ApplicationRecord
  self.table_name = "farmer_news"

  include FarmerBroadcast
  include FarmerBroadcastPush

  before_validation { self.link_url = FarmerBroadcast.normalise_url(link_url) }

  private

  def push_title = title
  def push_body = body.to_s.strip.presence || "Tap to read the latest update."
end
