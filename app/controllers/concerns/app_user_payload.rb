module AppUserPayload
  extend ActiveSupport::Concern

  private

  def app_user_session_payload(user)
    data = user.respond_to?(:data) ? user.data : {}

    {
      "id" => user.id,
      "record_type" => app_user_record_type(user),
      "username" => user.respond_to?(:user_name) ? user.user_name : data["user_name"],
      "name" => app_user_display_name(user, data),
      "stakeholder" => user.respond_to?(:stakeholder) ? user.stakeholder : data["stakeholder"],
      "stakeholder_role" => user.respond_to?(:stakeholder_role) ? user.stakeholder_role : data["stakeholder_role"],
      "role" => user.respond_to?(:role) ? user.role : data["role"],
      "role_name" => user.respond_to?(:role_name) ? user.role_name : data["role_name"],
      "user_management_role" => user.respond_to?(:user_management_role) ? user.user_management_role : data["user_management_role"],
      "person_type" => user.respond_to?(:person_type) ? user.person_type : data["person_type"],
      "vrp_types" => app_user_vrp_types(user),
      "parent_office" => user.respond_to?(:parent_office) ? user.parent_office : data["parent_office"],
      "office_category" => user.respond_to?(:office_category) ? user.office_category : data["office_category"],
      "office_name" => user.respond_to?(:office_name) ? user.office_name : data["office_name"],
      "sub_office_name" => user.respond_to?(:sub_office_name) ? user.sub_office_name : data["sub_office_name"],
      "office" => user.respond_to?(:office) ? user.office : data["office"],
      "fcoc" => user.respond_to?(:fcoc) ? user.fcoc : data["fcoc"],
      "email" => user.respond_to?(:email) ? user.email : data["email"],
      "mobile_no" => user.respond_to?(:mobile_no) ? user.mobile_no : data["mobile_no"],
      "user_type" => app_user_type(user, data)
    }
  end

  def app_user_display_name(user, data)
    return user.full_name if user.respond_to?(:full_name) && user.full_name.present?
    return user.name if user.respond_to?(:name) && user.name.present?

    [data["first_name"], data["last_name"]].compact_blank.join(" ")
  end

  def app_user_record_type(user)
    return user.class.name if user.is_a?(ApplicationRecord)

    "ModuleRecord"
  end

  def app_user_type(user, data)
    return "VRP" if user.is_a?(Vrp)
    return user.user_type if user.respond_to?(:user_type) && user.user_type.present?

    data["user_type"].presence || "User"
  end

  def app_user_vrp_types(user)
    return [] unless user.respond_to?(:vrp_type_ids)

    ids = Array(user.vrp_type_ids).reject(&:blank?)
    return [] if ids.blank?

    labels = []
    labels += VrpType.where(id: ids).pluck(:type_name) if "VrpType".safe_constantize&.table_exists?
    if defined?(ModuleRecord) && ModuleRecord.table_exists?
      labels += ModuleRecord.where(module_slug: "add-vrp-type", id: ids).filter_map { |record| record.data["jeevika_jankar_type_name"].presence || record.data["vrp_type_name"].presence }
    end
    labels.compact_blank.uniq
  end
end
