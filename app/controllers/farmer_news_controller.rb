# News published to the Android farmer app, state-wise or to all states.
class FarmerNewsController < ApplicationController
  include FarmerBroadcastAdmin

  private

  def broadcast_model = FarmerNewsItem
  def broadcast_label = "News"
  def broadcast_index_path = farmer_news_index_path
  def record_param_key = :farmer_news_item

  def build_attributes
    common_attributes.merge(
      body: params.dig(record_param_key, :body).to_s.strip,
      link_url: params.dig(record_param_key, :link_url).to_s.strip.presence,
      image_path: store_upload(params.dig(record_param_key, :image), IMAGE_EXTENSIONS)
    )
  end
end
