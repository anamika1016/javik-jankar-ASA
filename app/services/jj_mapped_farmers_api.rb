# frozen_string_literal: true

# Jeevika Jankar Mapped Farmers for React Native.
#
# This mirrors what /jj-mapped-farmers shows on the web: an admin picks any
# Jeevika Jankar, a Jeevika Jankar login only ever sees itself, and a staff
# login picks from the Jeevika Jankars under them. The web screen is left
# untouched, so the rules are restated here rather than shared.
class JjMappedFarmersApi
  EXTERNAL_HOST = "asa.ploughmanagro.com"
  MONTHS = Date::MONTHNAMES.compact.each_with_index.map do |name, index|
    { id: (index + 1).to_s, name: name, label: format("%s (%02d)", name, index + 1) }
  end.freeze
  YEARS = (2024..2030).map(&:to_s).freeze

  # The two external lookups are injected so a test can run without the
  # upstream server, and so a slow upstream never reaches the test suite.
  def initialize(current_app_user:, vrp_directory: nil, farmer_source: nil)
    @current_app_user = (current_app_user || {}).to_h.stringify_keys
    @vrp_directory = vrp_directory
    @farmer_source = farmer_source
  end

  def filters
    { months: MONTHS, years: YEARS }
  end

  # Who the caller is allowed to look at, and who is already chosen for them.
  def scope
    {
      login_type: login_type,
      can_choose_jeevika_jankar: !jeevika_jankar_login?,
      selected_mobile_no: nil,
      jeevika_jankars: jeevika_jankar_options
    }
  end

  def jeevika_jankar_options
    return [] if jeevika_jankar_login?
    return directory.map { |entry| entry.slice(:id, :name, :mobile_no, :label) } if admin_login?

    staff_jeevika_jankars.filter_map do |vrp|
      mobile = vrp.mobile_no.to_s.strip
      next if mobile.blank?

      name = vrp.name.presence || vrp.user_name.to_s
      { id: vrp.id.to_s, name: name, mobile_no: mobile,
        label: [name, mobile].compact_blank.join(" - ") }
    end.uniq { |option| option[:mobile_no] }.sort_by { |option| option[:label].to_s.downcase }
  end

  def mapped_farmers(mobile_no: nil, month: nil, year: nil, village_id: nil)
    selected = resolve_mobile_no(mobile_no)
    month = month.to_s.strip.presence || Time.current.month.to_s
    year = year.to_s.strip.presence || Time.current.year.to_s

    base = {
      login_type: login_type,
      can_choose_jeevika_jankar: !jeevika_jankar_login?,
      jeevika_jankars: jeevika_jankar_options,
      filters: { mobile_no: selected, jeevika_jankar_name: jeevika_jankar_name_for(selected),
                 month: month, year: year, village_id: village_id.to_s.strip.presence }
    }
    return base.merge(mapped_villages: [], farmers: [], count: 0, total_count: 0) if selected.blank?

    data = farmer_source_call(mobile_no: selected, month: month, year: year)
    all_farmers = Array(data[:farmers])
    village = village_id.to_s.strip
    farmers = village.blank? ? all_farmers : all_farmers.select do |farmer|
      farmer[:village_id].to_s == village || farmer[:village_name].to_s.casecmp(village).zero?
    end

    base.merge(mapped_villages: Array(data[:mapped_villages]), farmers: farmers,
      count: farmers.size, total_count: all_farmers.size)
  end

  # A Jeevika Jankar login is locked to itself; anyone else picks, but a staff
  # login may only pick from the Jeevika Jankars under them.
  def resolve_mobile_no(requested)
    return own_mobile_no if jeevika_jankar_login?

    requested = requested.to_s.strip
    return requested.presence if admin_login?

    allowed = jeevika_jankar_options.map { |option| option[:mobile_no].to_s }
    return requested if requested.present? && allowed.include?(requested)
    return nil if requested.present?
    # Nothing to choose between, so the only Jeevika Jankar is loaded straight away.
    allowed.one? ? allowed.first : nil
  end

  def login_type
    return "admin" if admin_login?
    return "jeevika_jankar" if jeevika_jankar_login?

    "staff"
  end

  private

  attr_reader :current_app_user

  def admin_login?
    return @admin_login if defined?(@admin_login)

    @admin_login = current_app_user["user_type"].to_s.casecmp("admin").zero? ||
      current_app_user["role"].to_s.casecmp("admin").zero?
  end

  # A staff login is never a Jeevika Jankar login, even when a Vrp row happens
  # to carry the same mobile number.
  def jeevika_jankar_login?
    return @jeevika_jankar_login if defined?(@jeevika_jankar_login)

    return @jeevika_jankar_login = false if admin_login?

    record_type = current_app_user["record_type"].to_s
    @jeevika_jankar_login = record_type.casecmp("Vrp").zero? ||
      current_app_user["user_type"].to_s.casecmp("vrp").zero?
  end

  def own_mobile_no
    [current_app_user["mobile_no"], current_app_user["username"], current_app_user["user_name"]]
      .compact_blank.map { |value| value.to_s.strip }.find(&:present?)
  end

  def jeevika_jankar_name_for(mobile_no)
    return nil if mobile_no.blank?

    if jeevika_jankar_login?
      return current_app_user["name"].presence || current_app_user["username"].presence || mobile_no
    end

    match = jeevika_jankar_options.find { |option| option[:mobile_no].to_s == mobile_no.to_s }
    match ? match[:name] : mobile_no
  end

  def staff_jeevika_jankars
    return [] unless model_ready?(:Vrp)

    scope = Vrp.all
    scope = scope.where(status: 55) if Vrp.column_names.include?("status")
    scope = scope.where(is_active: true) if Vrp.column_names.include?("is_active")

    labels = cluster_labels
    if labels.any?
      return scope.where.not(cluster_incharge: [nil, ""]).select do |vrp|
        labels.include?(person_key(vrp.cluster_incharge))
      end
    end

    keys = office_keys
    if keys.any?
      return scope.where.not(fcoc: [nil, ""]).select do |vrp|
        keys.include?(AgreementVrpScope.office_key(vrp.fcoc))
      end
    end

    own_registered(scope).to_a
  end

  # A saved cluster name often carries the role in brackets.
  def person_key(value)
    value.to_s.sub(/\s*\([^)]*\)\s*\z/, "").gsub(/\s+/, " ").strip.downcase
  end

  def cluster_labels
    roles = [current_app_user["role"], current_app_user["role_name"],
             current_app_user["stakeholder_role"], current_app_user["user_management_role"]]
      .compact_blank.join(" ").downcase
    return [] unless roles.include?("cluster") || roles.match?(/\bcc\b/)

    [current_app_user["name"], current_app_user["username"], current_app_user["user_name"]]
      .compact_blank.map { |value| person_key(value) }.uniq
  end

  def office_keys
    [current_app_user["fcoc"], current_app_user["fcoc_name"], current_app_user["office_name"],
     current_app_user["office"], current_app_user["parent_office"]]
      .compact_blank.filter_map { |value| AgreementVrpScope.office_key(value).presence }.uniq
  end

  def own_registered(scope)
    ids = [current_app_user["id"]].compact_blank.map(&:to_s)
    return Vrp.none if ids.blank?

    owned = Vrp.where(created_by_id: ids)
    owned = owned.or(Vrp.where(user_id: ids)) if Vrp.column_names.include?("user_id")
    scope.merge(owned)
  end

  def directory
    @directory ||= Array(@vrp_directory ? @vrp_directory.call : fetch_external_vrp_users)
  end

  def farmer_source_call(mobile_no:, month:, year:)
    return @farmer_source.call(mobile_no: mobile_no, month: month, year: year) if @farmer_source

    fetch_external_mapped_farmers(mobile_no: mobile_no, month: month, year: year)
  end

  def fetch_external_vrp_users
    Rails.cache.fetch("asa-external-vrp-users-list", expires_in: 10.minutes, skip_nil: true) do
      payload = external_get("/api/get_user_list")
      next [] unless payload["result"].is_a?(Array)

      payload["result"].filter_map do |row|
        name = row.dig("user_profile", "name").to_s.strip
        mobile = row["mobile_no"].to_s.strip.presence || row["username"].to_s.strip
        next if mobile.blank?

        { id: row["id"].to_s, name: name.presence || mobile, mobile_no: mobile,
          label: name.present? ? "#{name} (#{mobile})" : mobile }
      end.uniq { |row| row[:mobile_no] }.sort_by { |row| row[:name].downcase }
    end
  rescue StandardError => error
    Rails.logger.warn("Unable to fetch external VRP users: #{error.class} - #{error.message}")
    []
  end

  def fetch_external_mapped_farmers(mobile_no:, month:, year:)
    empty = { farmers: [], mapped_villages: [], count: 0 }
    return empty if mobile_no.blank? || month.blank? || year.blank?

    Rails.cache.fetch(["asa-jj-mapped-farmers-full", mobile_no, month, year].join(":"),
      expires_in: 2.minutes, skip_nil: true) do
      payload = external_get("/api/farmer", MOBILE_NO: mobile_no, MONTH: month, YEAR: year)
      next empty unless payload["result"].is_a?(Array)

      rows = payload["result"]
      { farmers: rows.each_with_index.map { |row, index| farmer_row(row, index) },
        mapped_villages: village_rows(rows), count: rows.size }
    end
  rescue StandardError => error
    Rails.logger.warn("Unable to fetch external mapped farmers: #{error.class} - #{error.message}")
    empty
  end

  def external_get(path, query = {})
    uri = URI::HTTPS.build(host: EXTERNAL_HOST, path: path)
    uri.query = URI.encode_www_form(query) if query.any?
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5,
      read_timeout: 12) { |http| http.get(uri.request_uri) }
    return {} unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    return {} unless payload.is_a?(Hash) && (payload["status"] == true || payload["status_code"] == 200)

    payload
  end

  def village_rows(rows)
    rows.filter_map do |row|
      grouping = hash_at(row, "grouping")
      address = hash_at(row, "address")
      name = grouping["village"].presence || address["village"].presence || row.dig("farmer", "village_name")
      next if name.blank?

      id = grouping["village_id"].presence || address["village_lg_code"].presence
      { id: id.to_s.presence || name, name: name }
    end.uniq { |village| [village[:id], village[:name].downcase] }.sort_by { |village| village[:name].downcase }
  end

  def farmer_row(row, index)
    farmer = hash_at(row, "farmer")
    family = hash_at(row, "family")
    address = hash_at(row, "address")
    grouping = hash_at(row, "grouping")
    lands = Array(row["lands"])
    total_area = lands.sum { |land| land["total_area"].to_f }.round(3)

    {
      sl_no: index + 1,
      farmer_unique_id: farmer["farmer_unique_id"].presence || "-",
      farmer_name: farmer["farmer_name"].presence || "-",
      father_husband_name: farmer["father_husband_name"].presence || family["head_of_family_male"].presence || "-",
      mobile_no: farmer["mobile_no"].presence || "-",
      gender: farmer["gender"].presence || "-",
      social_category: family["social_category"].presence || "-",
      economic_category: family["social_economic_category"].presence || "-",
      village_name: grouping["village"].presence || address["village"].presence || farmer["village_name"].presence || "-",
      village_id: grouping["village_id"].presence || address["village_lg_code"].presence || "-",
      gp_name: address["gram_panchayat"].presence || "-",
      block_name: address["block"].presence || "-",
      district_name: address["district"].presence || "-",
      fco_name: farmer["fco_name"].presence || "-",
      khasra_no: lands.filter_map { |land| land["khasra_no"].presence || land["plot_no"].presence }.compact_blank.join(", ").presence || "-",
      land_area: total_area.positive? ? total_area : "-",
      crop_names: lands.flat_map { |land| Array(land["crops"]) }.filter_map { |crop| crop["crop_name"].presence }.uniq.join(", ").presence || "-",
      status: row["status"].presence || "Pending",
      vrp_user: family["user"].presence || "-"
    }
  end

  def hash_at(row, key)
    row[key].is_a?(Hash) ? row[key] : {}
  end

  def model_ready?(name)
    klass = name.to_s.safe_constantize
    klass.present? && (!klass.respond_to?(:table_exists?) || klass.table_exists?)
  end
end
