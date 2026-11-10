require "digest"

# A farmer who has signed in from the Android app. Identity lives in the ASA
# register; this record is the login trail the web list reads.
class FarmerAppLogin < ApplicationRecord
  IDENTIFIER_TYPES = %w[mobile aadhaar].freeze

  # Matches index_farmer_app_logins_on_last_logged_in_at exactly. Asking for
  # NULLS LAST instead would make Postgres sort the whole table, and the
  # column is written on every login, so no row has a null here.
  scope :recent_first, -> { order(last_logged_in_at: :desc, id: :desc) }

  # Aadhaar is never stored, so the digest is what links repeat logins by the
  # same card. The register's own farmer id is preferred when it answers with
  # one; the digest only has to carry logins where it does not.
  def self.aadhaar_digest_for(aadhaar_no)
    digits = aadhaar_no.to_s.gsub(/\D/, "")
    return if digits.blank?

    Digest::SHA256.hexdigest("farmer-app-login:#{digits}")
  end

  def self.normalize_mobile(mobile)
    digits = mobile.to_s.gsub(/\D/, "")
    digits.length >= 10 ? digits[-10, 10] : digits
  end

  # Called once a farmer has passed OTP. `farmer` is the register payload.
  def self.record_login!(farmer:, identifier_type:, aadhaar_no: nil, ip: nil, device: nil, app_version: nil)
    farmer = farmer.to_h.with_indifferent_access
    external_id = farmer[:id].presence&.to_s
    digest = aadhaar_digest_for(aadhaar_no.presence || farmer[:aadhaar_no])
    aadhaar_digits = aadhaar_no.presence.to_s.gsub(/\D/, "")
    aadhaar_digits = farmer[:aadhaar_no].to_s.gsub(/\D/, "") if aadhaar_digits.blank?

    record = find_by(farmer_external_id: external_id) if external_id.present?
    record ||= find_by(aadhaar_digest: digest) if digest.present?
    record ||= new

    now = Time.current
    afl = afl_enrichment(farmer)
    record.assign_attributes(
      farmer_external_id: external_id.presence || record.farmer_external_id,
      full_name: farmer[:full_name].presence || farmer[:farmer_name].presence || record.full_name,
      mobile_no: normalize_mobile(farmer[:mobile_no]).presence || record.mobile_no,
      aadhaar_last4: aadhaar_digits.presence&.last(4) || record.aadhaar_last4,
      aadhaar_digest: digest.presence || record.aadhaar_digest,
      last_identifier_type: identifier_type.to_s.presence_in(IDENTIFIER_TYPES) || record.last_identifier_type,
      father_husband_name: farmer[:father_husband_name].presence || record.father_husband_name,
      village_name: register_place(farmer, :village) || afl[:village_name] || record.village_name,
      block_name: register_place(farmer, :block) || record.block_name,
      district_name: register_place(farmer, :district) || record.district_name,
      state_name: register_place(farmer, :state) || record.state_name,
      fco_name: farmer[:fco_name].presence || farmer[:fco_team_name].presence ||
        afl[:fco_name] || record.fco_name,
      ics_name: farmer[:ics_team_name].presence || farmer[:ics_name].presence ||
        afl[:ics_name] || record.ics_name,
      tracenet_id: farmer[:tracenet_id].presence || afl[:tracenet_id] || record.tracenet_id,
      login_count: record.login_count.to_i + 1,
      first_logged_in_at: record.first_logged_in_at || now,
      last_logged_in_at: now,
      last_login_ip: ip.presence || record.last_login_ip,
      last_device: device.to_s.first(200).presence || record.last_device,
      last_app_version: app_version.to_s.first(40).presence || record.last_app_version
    )
    record.save!
    record
  end

  # The register spells places differently depending on which block of the
  # payload they come from, so try the shapes it is known to use. Its land
  # rows normally carry village_id but no village_name, which is why the
  # caller falls back to the AFL master.
  def self.register_place(farmer, kind)
    farmer["#{kind}_name"].presence ||
      farmer.dig(:address, kind).presence ||
      farmer.dig(:grouping, kind).presence ||
      Array(farmer[:land_details]).filter_map { |row| row.is_a?(Hash) ? row["#{kind}_name"].presence : nil }.first
  end
  private_class_method :register_place

  # Village, FCO and ICS names the register only identifies by id. AFL already
  # holds the name for the same village_id, so the list can show a place
  # instead of a number without another call to the register.
  def self.afl_enrichment(farmer)
    return {} unless "Afl".safe_constantize&.table_exists?

    village_id = Array(farmer[:land_details]).filter_map do |row|
      row["village_id"].presence if row.is_a?(Hash)
    end.first.presence || farmer[:village_id].presence
    candidates = mobile_candidates(farmer[:mobile_no])
    return {} if candidates.blank? && village_id.blank?

    # Written against the mobile_no and village_id indexes on purpose. Matching
    # with regexp_replace instead would read every AFL row on each login.
    scope = Afl.select(:id, :mobile_no, :village_id, :village_name, :fco, :ics_name, :tracenet_no)
    relation =
      if candidates.present? && village_id.present?
        scope.where(mobile_no: candidates).or(scope.where(village_id: village_id.to_s))
      elsif candidates.present?
        scope.where(mobile_no: candidates)
      else
        scope.where(village_id: village_id.to_s)
      end

    # One trip covers both lookups. A row matched on mobile is this farmer, so
    # its FCO, ICS and Tracenet belong to them; a row matched only on village
    # belongs to some other farmer, so nothing but the village name is taken.
    rows = relation.limit(25).to_a
    own_row = rows.find { |row| candidates.include?(row.mobile_no.to_s) }
    village_row = own_row || rows.first
    return {} if village_row.blank?

    details = { village_name: village_row.village_name.presence }
    if own_row
      details.merge!(
        fco_name: own_row.fco.presence,
        ics_name: own_row.ics_name.presence,
        tracenet_id: own_row.tracenet_no.presence
      )
    end
    details.compact
  rescue StandardError => error
    Rails.logger.warn("FarmerAppLogin AFL enrichment failed: #{error.class} - #{error.message}")
    {}
  end
  private_class_method :afl_enrichment

  # AFL stores the number however it was imported. Listing the known spellings
  # keeps the lookup an indexed equality instead of a scan.
  def self.mobile_candidates(mobile)
    last10 = normalize_mobile(mobile)
    return [] unless last10.length == 10

    [last10, "91#{last10}", "+91#{last10}", "0#{last10}"]
  end
  private_class_method :mobile_candidates

  def masked_mobile
    digits = mobile_no.to_s.gsub(/\D/, "")
    return "-" if digits.blank?

    "#{'*' * [digits.length - 4, 0].max}#{digits.last(4)}"
  end

  def masked_aadhaar
    aadhaar_last4.present? ? "XXXX-XXXX-#{aadhaar_last4}" : "-"
  end
end
