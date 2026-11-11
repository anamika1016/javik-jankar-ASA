# A video shown in the Android farmer app, either uploaded here or linked.
class FarmerVideo < ApplicationRecord
  include FarmerBroadcast

  validate :video_source_present

  # What the app should play: an uploaded file is served from this host, a
  # link is played as-is.
  def playback_url
    video_path.presence || video_url.presence
  end

  def uploaded?
    video_path.present?
  end

  private

  def video_source_present
    return if video_url.present? || video_path.present?

    errors.add(:base, "Upload a video file or paste a video link.")
  end
end
