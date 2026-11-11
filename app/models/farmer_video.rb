# A video shown in the Android farmer app, either uploaded here or linked.
class FarmerVideo < ApplicationRecord
  include FarmerBroadcast

  before_validation { self.video_url = FarmerBroadcast.normalise_url(video_url) }

  validate :video_source_present

  # What the app should play: an uploaded file is served from this host, a
  # link is played as-is.
  def playback_url
    video_path.presence || video_url.presence
  end

  def uploaded?
    video_path.present?
  end

  # A YouTube link has to be embedded, not dropped into a <video> tag.
  YOUTUBE_ID = %r{
    (?:youtu\.be/|youtube\.com/(?:embed/|shorts/|watch\?(?:.*&)?v=))([A-Za-z0-9_-]{6,})
  }x

  def youtube_id
    video_url.to_s[YOUTUBE_ID, 1]
  end

  # What a player can open directly: the file, a YouTube embed, or the link.
  def embed_url
    return video_path if uploaded?
    return "https://www.youtube.com/embed/#{youtube_id}" if youtube_id

    video_url
  end

  def source_type
    return "file" if uploaded?
    return "youtube" if youtube_id

    "link"
  end

  private

  def video_source_present
    return if video_url.present? || video_path.present?

    errors.add(:base, "Upload a video file or paste a video link.")
  end
end
