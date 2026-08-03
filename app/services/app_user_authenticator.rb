class AppUserAuthenticator
  def self.authenticate(login:, password:)
    new(login: login, password: password).authenticate
  end

  def self.authenticate_vrp(login:, password:)
    new(login: login, password: password).authenticate_vrp
  end

  def initialize(login:, password:)
    @login = login.to_s.strip
    @password = password.to_s
  end

  def authenticate
    return if @login.blank? || @password.blank?

    login_key = @login.downcase
    raw_login = @login

    user = find_model_user_by_login(User, login_key, raw_login) do |scope|
      User.column_names.include?("status") ? scope.where.not(status: "Inactive") : scope
    end
    return user if user

    vrp = find_model_user_by_login(Vrp, login_key, raw_login) do |scope|
      scope = Vrp.column_names.include?("is_active") ? scope.where(is_active: true) : scope
      Vrp.column_names.include?("is_deleted") ? scope.where(is_deleted: false) : scope
    end
    return vrp if vrp

    find_module_record_user_by_login(login_key, raw_login)
  end

  def authenticate_vrp
    return if @login.blank? || @password.blank?

    login_key = @login.downcase
    raw_login = @login
    find_model_user_by_login(Vrp, login_key, raw_login) do |scope|
      scope = Vrp.column_names.include?("is_active") ? scope.where(is_active: true) : scope
      Vrp.column_names.include?("is_deleted") ? scope.where(is_deleted: false) : scope
    end
  end

  private

  def find_model_user_by_login(model_class, login_key, raw_login)
    return unless authentication_model_ready?(model_class)
    return unless model_class.column_names.include?("password")

    match_clauses = []
    match_clauses << "LOWER(user_name) = :login" if model_class.column_names.include?("user_name")
    match_clauses << "LOWER(email) = :login" if model_class.column_names.include?("email")
    match_clauses << "mobile_no = :raw_login" if model_class.column_names.include?("mobile_no")
    return if match_clauses.empty?

    scope = model_class.all
    scope = yield(scope) if block_given?
    scope
      .where(match_clauses.join(" OR "), login: login_key, raw_login: raw_login)
      .find_by(password: @password)
  rescue StandardError => e
    Rails.logger.warn("Login lookup failed for #{model_class}: #{e.class} - #{e.message}")
    nil
  end

  def find_module_record_user_by_login(login_key, raw_login)
    return unless authentication_model_ready?(ModuleRecord)

    ModuleRecord
      .where(module_slug: "new-user")
      .where(<<~SQL.squish, login: login_key, raw_login: raw_login)
        LOWER(data::jsonb ->> 'user_name') = :login OR
        LOWER(data::jsonb ->> 'email') = :login OR
        data::jsonb ->> 'mobile_no' = :raw_login
      SQL
      .where("COALESCE(LOWER(data::jsonb ->> 'status'), 'active') <> 'inactive'")
      .find_by("data::jsonb ->> 'password' = ?", @password)
  rescue StandardError => e
    Rails.logger.warn("ModuleRecord login lookup failed: #{e.class} - #{e.message}")
    find_module_record_user_with_legacy_scan(login_key, raw_login)
  end

  # Keep compatibility with any historic row whose data is not valid JSON. The
  # indexed query above is the normal fast path; this only runs for malformed
  # legacy data or a database adapter without PostgreSQL JSON operators.
  def find_module_record_user_with_legacy_scan(login_key, raw_login)
    ModuleRecord.where(module_slug: "new-user").find_each do |record|
      next unless module_record_active_for_login?(record)
      next unless module_record_login_matches?(record, login_key, raw_login)

      return record if module_record_value(record, "password").to_s == @password
    end

    nil
  rescue StandardError => e
    Rails.logger.warn("Legacy ModuleRecord login lookup failed: #{e.class} - #{e.message}")
    nil
  end

  def module_record_login_matches?(record, login_key, raw_login)
    [
      module_record_value(record, "user_name").to_s.downcase == login_key,
      module_record_value(record, "email").to_s.downcase == login_key,
      module_record_value(record, "mobile_no").to_s == raw_login
    ].any?
  end

  def module_record_active_for_login?(record)
    module_record_value(record, "status").to_s.downcase != "inactive"
  end

  def module_record_value(record, key)
    data = record.respond_to?(:data) ? record.data : {}
    data = JSON.parse(data) if data.is_a?(String)
    return unless data.respond_to?(:[])

    data[key] || data[key.to_sym]
  rescue JSON::ParserError
    nil
  end

  def authentication_model_ready?(model_class)
    model_class.present? && model_class.respond_to?(:table_exists?) && model_class.table_exists?
  rescue StandardError
    false
  end
end
