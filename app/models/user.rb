class User < ApplicationRecord
  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png].freeze

  has_one_attached :aadhar_upload

  validates :user_name, presence: true
  validates :password, presence: true
  validate :uploaded_aadhar_is_image

  def full_name
    [first_name, last_name].compact_blank.join(" ")
  end

  def active?
    status.blank? || status == "Active"
  end

  private

  def uploaded_aadhar_is_image
    return unless aadhar_upload.attached?
    return if aadhar_upload.blob.content_type.in?(IMAGE_CONTENT_TYPES)

    errors.add(:aadhar_upload, "must be a JPEG, JPG, or PNG file")
  end
end
