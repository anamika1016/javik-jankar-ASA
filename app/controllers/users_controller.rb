class UsersController < ApplicationController
  before_action :set_user, only: [:edit, :update, :destroy, :toggle_status, :set_status]
  before_action :load_form_options, only: [:new, :edit, :create, :update]

  def index
    @users = User.order(created_at: :desc)
  end

  def new
    @user = User.new(status: "Active")
  end

  def create
    @user = User.new(user_params)

    if @user.password != params.dig(:user, :confirmed_password).to_s
      flash.now[:alert] = "Password and Confirmed Password must match."
      render :new, status: :unprocessable_entity
      return
    end

    if @user.save
      redirect_to users_path, notice: "User saved successfully."
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if user_params[:password].to_s != params.dig(:user, :confirmed_password).to_s
      flash.now[:alert] = "Password and Confirmed Password must match."
      render :edit, status: :unprocessable_entity
      return
    end

    if @user.update(user_params)
      refresh_current_user_session_if_needed
      redirect_to users_path, notice: "User updated successfully."
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
    redirect_to users_path, notice: "User deleted successfully."
  end

  def toggle_status
    next_status = @user.status == "Inactive" ? "Active" : "Inactive"
    @user.update(status: next_status)
    redirect_to users_path, notice: "Status changed to #{next_status}."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @user.update(status: next_status)
    redirect_to users_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    permitted = params.require(:user).permit(
      :stakeholder, :stakeholder_role, :role, :state, :district, :block, :gram_panchayat, :village,
      :parent_office, :office_category, :office_name, :sub_office_name, :office, :full_address, :pincode, :first_name, :last_name,
      :gender, :email, :password, :user_name, :mobile_no,
      :user_type, :user_management_role, :person_type, :role_name, :status
    )
    permitted[:office] = permitted[:sub_office_name].presence || permitted[:office_name].presence || permitted[:office]
    permitted
  end

  def load_form_options
    @gender_options = ["Male", "Female", "Other"]
    @user_type_options = ["Admin", "User"]
    @status_options = ["Active", "Inactive"]
    @stakeholder_options = module_record_options("stakeholder-master", "stakeholder_name_in_english")
    @stakeholder_role_options = module_record_options("stakeholder-role", "stakeholder_role")
    @role_options = module_record_options("role-name", "role_name")
    @user_management_role_options = module_record_options("user-management-role", "user_management_role")
    @person_type_options = module_record_options("person-type", "person_type")
    @role_management_mappings = role_management_mappings
    @state_options = module_record_options("state-master", "state_name")
    @district_options = module_record_options("district-master", "district_name")
    @block_options = module_record_options("block-master", "block_name")
    @gram_panchayat_options = (
      module_record_options("gram-panchayat-master", ["gram_panchayat_name", "gram_panchayat", "gp_name", "gram_name", "name"]) +
      module_record_options("lg-directory-list", ["gram_panchayat", "gp_code"])
    ).compact_blank.uniq
    @village_options = module_record_options("village-master", "village_name")
    @location_hierarchy_mappings = location_hierarchy_mappings
    @parent_office_options = module_record_options("parent-office-add", ["parent_office_name", "parent_category"])
    @office_name_options = module_record_options("office-category-add", ["office_name", "category_name"])
    @office_category_mappings = office_category_mappings
    @sub_office_name_options = module_record_options("office-mapping-add", ["sub_office_name", "office_mapping", "office"])
    @ics_options = module_record_options("ics-master", "ics_name")
  end

  def module_record_options(module_slug, field_key)
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    field_keys = Array(field_key)
    ModuleRecord
      .where(module_slug: module_slug)
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .filter_map do |record|
        if ["gram-panchayat-master", "lg-directory-list"].include?(module_slug)
          gram_panchayat_name_from_record(record)
        else
          first_present_data(record, *field_keys)
        end
      end
      .uniq
  end

  def role_management_mappings
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    stakeholder_role_mappings = ModuleRecord
      .where(module_slug: "stakeholder-role")
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map do |record|
        stakeholder_role = first_present_data(record, "stakeholder_role").to_s.strip
        parent_office = first_present_data(record, "parent_office", "parent_category", "office_name", "office").to_s.strip
        office_name = first_present_data(record, "office_name", "office").to_s.strip
        mapping_labels_for_option(stakeholder_role, :stakeholder_role).map do |stakeholder_role_label|
          {
            stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
            stakeholder_role: stakeholder_role,
            stakeholder_role_label: stakeholder_role_label,
            parent_office: parent_office,
            office_category: parent_office,
            office_name: office_name,
            office: office_name,
            role: "",
            role_label: "",
            role_name: "",
            role_name_label: "",
            user_management_role: "",
            user_management_role_label: "",
            person_type: "",
            person_type_label: ""
          }
        end
      end

    role_mappings = ModuleRecord
      .where(module_slug: "role-name")
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map do |record|
        role = first_present_data(record, "role_name").to_s.strip
        mapping_labels_for_option(role, :role).map do |role_label|
          {
            stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
            stakeholder_role: first_present_data(record, "stakeholder_role").to_s.strip,
            role: role,
            role_label: role_label,
            role_name: "",
            role_name_label: "",
            user_management_role: "",
            user_management_role_label: "",
            person_type: "",
            person_type_label: ""
          }
        end
      end

    user_management_role_mappings = ModuleRecord
      .where(module_slug: "user-management-role")
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map do |record|
        user_management_role = first_present_data(record, "user_management_role").to_s.strip
        mapping_labels_for_option(user_management_role, :user_management_role).map do |user_management_role_label|
          {
            stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
            stakeholder_role: first_present_data(record, "stakeholder_role").to_s.strip,
            role: first_present_data(record, "role", "role_name").to_s.strip,
            role_name: "",
            role_name_label: "",
            user_management_role: user_management_role,
            user_management_role_label: user_management_role_label,
            person_type: "",
            person_type_label: ""
          }
        end
      end

    person_type_mappings = ModuleRecord
      .where(module_slug: "person-type")
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map do |record|
        person_type = first_present_data(record, "person_type").to_s.strip
        mapping_labels_for_option(person_type, :person_type).map do |person_type_label|
          {
            stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
            stakeholder_role: first_present_data(record, "stakeholder_role").to_s.strip,
            role: first_present_data(record, "role", "role_name").to_s.strip,
            role_name: "",
            role_name_label: "",
            user_management_role: first_present_data(record, "user_management_role").to_s.strip,
            person_type: person_type,
            person_type_label: person_type_label
          }
        end
      end

    (stakeholder_role_mappings + role_mappings + user_management_role_mappings + person_type_mappings)
      .reject { |mapping| mapping[:stakeholder_role].blank? && mapping[:role].blank? && mapping[:role_name].blank? && mapping[:user_management_role].blank? && mapping[:person_type].blank? }
      .uniq
  end

  def mapping_labels_for_option(value, _attribute)
    return [] if value.blank?

    [value]
  end

  def registered_names_for_option(attribute, value)
    return [] if value.blank?

    (
      registered_vrp_names_for_option(attribute, value) +
      registered_user_names_for_option(attribute, value) +
      registered_module_user_names_for_option(attribute, value)
    ).compact_blank.uniq
  end

  def registered_vrp_names_for_option(attribute, value)
    return [] unless defined?(Vrp) && Vrp.table_exists?
    return [] unless Vrp.column_names.include?(attribute.to_s)

    Vrp.where(attribute => value).order(updated_at: :desc).filter_map { |vrp| vrp.name.presence }
  end

  def registered_user_names_for_option(attribute, value)
    return [] unless defined?(User) && User.table_exists?
    return [] unless User.column_names.include?(attribute.to_s)

    User.where(attribute => value).order(updated_at: :desc).filter_map { |user| user.full_name.presence || user.user_name.presence }
  end

  def registered_module_user_names_for_option(attribute, value)
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    key = attribute.to_s
    ModuleRecord
      .where(module_slug: "new-user")
      .order(updated_at: :desc)
      .select { |record| active_module_record?(record) && record.data[key].to_s.strip.casecmp(value.to_s.strip).zero? }
      .filter_map { |record| [record.data["first_name"], record.data["last_name"]].compact_blank.join(" ").presence || record.data["user_name"].presence }
  end

  def first_present_data(record, *keys)
    keys.filter_map { |key| record.data[key].presence }.first
  end

  def active_module_record?(record)
    return false if truthy_module_flag?(record.data["deleted"]) ||
      truthy_module_flag?(record.data["is_deleted"]) ||
      truthy_module_flag?(record.data["discarded"])

    status = record.data["status"].to_s.strip
    return true if status.blank?

    status.casecmp("Active").zero?
  end

  def truthy_module_flag?(value)
    ["1", "true", "yes", "deleted"].include?(value.to_s.strip.downcase)
  end

  def gram_panchayat_name_from_record(record)
    first_non_code_data(record, "gram_panchayat_name", "gram_panchayat", "gram_panchayat_id", "gp_name", "gram_name", "name", "gp_code", "gram_code")
  end

  def first_non_code_data(record, *keys)
    values = keys.filter_map { |key| record.data[key].to_s.strip.presence }
    values.find { |value| !code_like_location_value?(value) } || values.first
  end

  def code_like_location_value?(value)
    value.to_s.strip.match?(/\A[\d\s.\/-]+\z/)
  end

  def office_category_mappings
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    ModuleRecord
      .where(module_slug: ["office-category-add", "office-mapping-add"])
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .map do |record|
        office_category = first_present_data(record, "office_category", "category_name")
        office_name = first_present_data(record, "office_name", "office")
        if record.module_slug == "office-category-add"
          office_category = office_name if office_category.blank?
          office_name = ""
        elsif record.module_slug == "office-mapping-add"
          office_category = office_name if office_category.blank?
          office_name = first_present_data(record, "sub_office_name", "office_mapping", "office").to_s.strip
        end

        {
          stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
          parent_office: first_present_data(record, "parent_category", "parent_office", "parent_office_name").to_s.strip,
          office_category: office_category.to_s.strip,
          office_name: office_name.to_s.strip,
          office: office_name.presence || office_category.to_s.strip,
          office_level: first_present_data(record, "office_level").to_s.strip
        }
      end
      .reject { |mapping| mapping[:office_category].blank? && mapping[:office_name].blank? }
      .uniq
  end

  def location_hierarchy_mappings
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    states = active_records_for_location("state-master").map do |record|
      location_row(record, state: first_present_data(record, "state_name"))
    end

    districts = active_records_for_location("district-master").map do |record|
      location_row(record,
        state: first_present_data(record, "state"),
        district: first_present_data(record, "district_name"))
    end

    blocks = active_records_for_location("block-master").map do |record|
      location_row(record,
        state: first_present_data(record, "state"),
        district: first_present_data(record, "district"),
        block: first_present_data(record, "block_name"))
    end

    gram_panchayats = active_records_for_location("gram-panchayat-master").map do |record|
      location_row(record,
        state: first_present_data(record, "state"),
        district: first_present_data(record, "district"),
        block: first_present_data(record, "block"),
        gram_panchayat: gram_panchayat_name_from_record(record))
    end

    villages = active_records_for_location("village-master").map do |record|
      location_row(record,
        state: first_present_data(record, "state"),
        district: first_present_data(record, "district"),
        block: first_present_data(record, "block"),
        gram_panchayat: gram_panchayat_name_from_record(record),
        village: first_present_data(record, "village_name", "village", "name"))
    end

    lg_directory_rows = active_records_for_location("lg-directory-list").map do |record|
      location_row(record,
        state: first_present_data(record, "state", "state_name"),
        district: first_present_data(record, "district", "district_name"),
        block: first_present_data(record, "block", "cd_block_name"),
        gram_panchayat: gram_panchayat_name_from_record(record),
        village: first_present_data(record, "village", "village_name"))
    end

    states + districts + blocks + gram_panchayats + villages + lg_directory_rows
  end

  def active_records_for_location(module_slug)
    ModuleRecord
      .where(module_slug: module_slug)
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
  end

  def location_row(record, values)
    row = { id: record.id.to_s }
    values.each { |key, value| row[key] = value.to_s.strip if value.present? }
    row
  end

  def refresh_current_user_session_if_needed
    stored_user = session[:app_user]
    return unless stored_user.present?
    return unless stored_user["id"].to_i == @user.id || stored_user["username"].to_s == @user.user_name.to_s

    refresh_app_user_session!(@user)
  end
end
