# Videos published to the Android farmer app, state-wise or to all states.
class FarmerVideosController < ApplicationController
  include FarmerBroadcastAdmin

  private

  def broadcast_model = FarmerVideo
  def broadcast_label = "Video"
  def broadcast_index_path = farmer_videos_path
  def record_param_key = :farmer_video

  def build_attributes
    common_attributes.merge(
      description: params.dig(record_param_key, :description).to_s.strip,
      video_url: params.dig(record_param_key, :video_url).to_s.strip.presence,
      video_path: store_upload(params.dig(record_param_key, :video), VIDEO_EXTENSIONS),
      thumbnail_path: store_upload(params.dig(record_param_key, :thumbnail), IMAGE_EXTENSIONS),
      duration_label: params.dig(record_param_key, :duration_label).to_s.strip.presence
    )
  end
end
