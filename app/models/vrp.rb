class Vrp < ApplicationRecord
  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png].freeze

  default_scope { where(is_deleted: false) }

  belongs_to :vrp_bank_master, optional: true

  has_one :vrp_profile, dependent: :destroy
  has_many :vrp_ics_mappings, dependent: :destroy
  has_many :target_mappings, dependent: :destroy
  enum :gender, { male: 1, female: 2 }
  serialize :vrp_type_ids, coder: JSON
  serialize :project_master_ids, coder: JSON
  serialize :ics_master_ids, coder: JSON
  serialize :gram_panchayat_ids, coder: JSON
  serialize :village_ids, coder: JSON

  has_one_attached :photo
  has_one_attached :aadhar_upload
  has_one_attached :bank_passbook_upload

  accepts_nested_attributes_for :vrp_profile, reject_if: :all_blank, allow_destroy: true

  validates :name,
            :father_husband_name,
            :gender,
            :date_of_birth,
            :date_of_joining,
            :aadhar_no,
            :account_no,
            :branch,
            :ifsc_code,
            :bank_name,
            :address,
            :mobile_no,
            :experience_in_years,
            presence: true
  validates :aadhar_no, format: { with: /\A\d{12}\z/, message: "must be 12 digits" }, allow_blank: true
  validates :mobile_no, format: { with: /\A[6-9]\d{9}\z/, message: "must be 10 digits starting with 6-9" }, allow_blank: true
  validates :ifsc_code, format: { with: /\A[A-Z]{4}0[A-Z0-9]{6}\z/i, message: "is invalid" }, allow_blank: true
  validates :experience_in_years, numericality: { greater_than_or_equal_to: 0, allow_blank: true }
  validate :selected_registration_lists_are_present
  validate :uploaded_documents_are_images
  before_validation :set_default_office_values
  before_validation :sync_bank_name_from_master
  before_validation :sync_profile_location_from_lists
  before_validation :sync_location_lists_from_profile
  before_save :remove_blank_array_values

  def agreement_accepted?
    return false unless has_attribute?(:agreement_accepted_at)

    agreement_accepted_at.present?
  end

  private

  def set_default_office_values
    self.office_detail_id = 0 if office_detail_id.blank?
    self.to_office_detail_id = 0 if to_office_detail_id.blank?
  end

  def sync_location_lists_from_profile
    return unless vrp_profile

    self.gram_panchayat_ids = [vrp_profile.gram_panchayat_id] if gram_panchayat_ids.blank? && vrp_profile.gram_panchayat_id.present?
    self.village_ids = [vrp_profile.village_id] if village_ids.blank? && vrp_profile.village_id.present?
  end

  def sync_profile_location_from_lists
    return unless vrp_profile

    first_gram_panchayat_id = cleaned_ids(gram_panchayat_ids).first
    first_village_id = cleaned_ids(village_ids).first

    vrp_profile.gram_panchayat_id = first_gram_panchayat_id if first_gram_panchayat_id.present?
    vrp_profile.village_id = first_village_id if first_village_id.present?
  end

  def remove_blank_array_values
    self.vrp_type_ids = cleaned_ids(vrp_type_ids)
    self.gram_panchayat_ids = cleaned_ids(gram_panchayat_ids)
    self.village_ids = cleaned_ids(village_ids)
    self.project_master_ids = cleaned_ids(project_master_ids)
    self.ics_master_ids = cleaned_ids(ics_master_ids)
  end

  def cleaned_ids(ids)
    Array(ids).reject(&:blank?)
  end

  def selected_registration_lists_are_present
    {
      vrp_type_ids: "Select at least one VRP type",
      gram_panchayat_ids: "Select at least one gram panchayat",
      village_ids: "Select at least one village"
    }.each do |attribute, message|
      errors.add(attribute, message) if cleaned_ids(public_send(attribute)).blank?
    end
  end

  def uploaded_documents_are_images
    {
      photo: photo,
      aadhar_upload: aadhar_upload,
      bank_passbook_upload: bank_passbook_upload
    }.each do |attribute, attachment|
      next unless attachment.attached?
      next if attachment.blob.content_type.in?(IMAGE_CONTENT_TYPES)

      errors.add(attribute, "must be a JPEG, JPG, or PNG file")
    end
  end

  def sync_bank_name_from_master
    self.bank_name = vrp_bank_master&.name if bank_name.blank? && vrp_bank_master
  end

end
