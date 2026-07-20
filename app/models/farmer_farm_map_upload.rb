class FarmerFarmMapUpload < ApplicationRecord
  include FarmerFarmLinkable

  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png].freeze
  MAP_TYPES = {
    "farm_map" => "Farm Map (lat long gps)",
    "crop_map_session_wise" => "Crop Map Session Wise Farm Map (lat long gps)"
  }.freeze

  has_one_attached :photo

  validates :map_type, inclusion: { in: MAP_TYPES.keys }
  validates :status, inclusion: { in: %w[Active Inactive] }
  validates :latitude, :longitude, :gps_accuracy, numericality: true, allow_blank: true
  validate :photo_is_attached
  validate :uploaded_photo_is_image

  def self.title_for(map_type)
    MAP_TYPES.fetch(map_type)
  end

  private

  def photo_is_attached
    errors.add(:photo, "is required") unless photo.attached?
  end

  def uploaded_photo_is_image
    return unless photo.attached?
    return if photo.blob.content_type.in?(IMAGE_CONTENT_TYPES)

    errors.add(:photo, "must be a JPEG, JPG, or PNG file")
  end
end
