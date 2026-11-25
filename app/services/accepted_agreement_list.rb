# The "Accepted Agreement by Jeevika Jankar" list, shared by the web page and
# the mobile API so both show the same rows, search and visibility.
class AcceptedAgreementList
  # Jeevika Jankars the signed-in user may see: all for an admin, only
  # themselves for a Jeevika Jankar, else the ones mapped to the user.
  # user: the app user payload ("id", "record_type", "user_type", roles, office).
  def self.visible_vrps(user, request:)
    return Vrp.all if user.blank? || user["user_type"].to_s.strip.casecmp("admin").zero?
    return Vrp.where(id: user["id"]) if user["record_type"].to_s == "Vrp"

    policy = ModulesController.new
    policy.request = request
    policy.instance_variable_set(:@current_app_user, user)
    AgreementVrpScope.new(user, policy: policy).resolve
  end

  def self.enabled?
    defined?(Vrp) && Vrp.table_exists? && Vrp.column_names.include?("agreement_accepted_at")
  end

  # Filtered in Ruby rather than SQL because village and TO Name are resolved
  # after the query, from separate masters -- a SQL WHERE could not match
  # either, and those are two of the columns a reader actually searches by.
  def self.search(rows, term)
    term = term.to_s.strip
    return rows if term.blank?

    needle = term.downcase
    digits = term.gsub(/\D/, "")

    rows.select do |row|
      next true if %i[name village fcoc to_name].any? do |key|
        row[key].to_s.downcase.include?(needle)
      end

      digits.present? && row[:mobile_no].to_s.gsub(/\D/, "").include?(digits)
    end
  end

  attr_reader :village_resolver

  def initialize(visible_vrps)
    @visible_vrps = visible_vrps
  end

  # Newest first. Loads only whether a signature exists, not the Base64 image.
  def rows
    return [] unless self.class.enabled?

    vrps = @visible_vrps
      .includes(:vrp_profile)
      .select(:id, :name, :user_name, :mobile_no, :fcoc, :to_name, :agreement_accepted_at, :village_ids,
        Arel.sql("NULLIF(BTRIM(agreement_signature_data), '') IS NOT NULL AS agreement_signature_present"))
      .where.not(agreement_accepted_at: nil)
      .order(agreement_accepted_at: :desc)
      .to_a
    @village_resolver = AgreementVillageName.new.preload(vrps)
    to_names = JeevikaJankarToName.new
    vrps.map do |vrp|
      {
        id: vrp.id,
        name: vrp.name.presence || vrp.user_name.presence || "-",
        village: @village_resolver.call(vrp),
        fcoc: vrp.fcoc.presence || "-",
        to_name: to_names.for(vrp_id: vrp.id, fco: vrp.fcoc),
        mobile_no: vrp.mobile_no.presence || "-",
        accepted_at: vrp.agreement_accepted_at&.strftime("%d/%m/%Y %I:%M %p"),
        accepted_at_iso: vrp.agreement_accepted_at&.iso8601,
        signature_present: vrp[:agreement_signature_present]
      }
    end
  end
end
