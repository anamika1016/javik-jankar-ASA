module Api
  module V1
    class JeevikaJankarMastersController < BaseController
      include VrpAccess

      MASTER_CONFIG = {
        "all_list" => [ "lg-directory-list", %w[state_name state_code district_name district_code block_name block_code gram_name gram_code village_name village_code] ],
        "states" => [ "state-master", %w[state_name state_code status] ],
        "districts" => [ "district-master", %w[state district_name district_code status] ],
        "blocks" => [ "block-master", %w[state district block_name block_code status] ],
        "gram_panchayats" => [ "gram-panchayat-master", %w[state district block gram_panchayat_name gp_code status] ],
        "villages" => [ "village-master", %w[state district block gram_panchayat village_name village_code status] ],
        "months" => [ "month-master", %w[month_name financial_year status] ],
        "parent_offices" => [ "parent-office-add", %w[stakeholder_category parent_office_type parent_office parent_office_name office_level status] ],
        "office_categories" => [ "office-category-add", %w[stakeholder_category parent_category office_name office_level status] ],
        "sub_offices" => [ "office-mapping-add", %w[stakeholder_category parent_category office_name sub_office_name office_level status] ],
        "types" => [ "add-vrp-type", %w[jeevika_jankar_type_name vrp_type_name position_type_name status] ]
      }.freeze

      MASTER_CONFIG.each_key do |action_name|
        define_method(action_name) { render_master(action_name) }
      end

      def create_type
        merge_json_body_params!
        name = params[:jeevika_jankar_type_name].presence || params[:name].presence
        if name.blank?
          return render json: {
            success: false,
            message: "Jeevika Jankar Type Name is required.",
            errors: [ "Jeevika Jankar Type Name can't be blank" ]
          }, status: :unprocessable_entity
        end

        duplicate = ModuleRecord.where(module_slug: "add-vrp-type").find do |record|
          existing_name = record.data["jeevika_jankar_type_name"].presence ||
            record.data["vrp_type_name"].presence ||
            record.data["position_type_name"].presence
          existing_name.to_s.casecmp(name.to_s.strip).zero?
        end
        if duplicate
          return render json: {
            success: false,
            message: "Jeevika Jankar Type already exists.",
            errors: [ "Jeevika Jankar Type Name has already been taken" ]
          }, status: :unprocessable_entity
        end

        record = ModuleRecord.new(
          module_slug: "add-vrp-type",
          data: {
            "jeevika_jankar_type_name" => name.to_s.strip,
            "status" => normalized_status(params[:status])
          }
        )
        record.created_by_id = current_api_user.id if record.respond_to?(:created_by_id=)

        if record.save
          render json: {
            success: true,
            message: "Jeevika Jankar Type saved successfully.",
            jeevika_jankar_type: record_payload(record, MASTER_CONFIG.fetch("types").last)
          }, status: :created
        else
          render json: {
            success: false,
            message: "Jeevika Jankar Type save failed.",
            errors: record.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def cluster_incharges
        rows = api_cluster_incharge_mappings.map do |mapping|
          {
            label: mapping[:label].to_s,
            value: mapping[:value].to_s,
            office_category: mapping[:office_category].to_s,
            office_name: mapping[:office_name].to_s,
            parent_office: mapping[:parent_office].to_s
          }
        end

        render json: {
          success: true,
          message: "Cluster Incharges fetched successfully.",
          cluster_incharges: rows,
          count: rows.size
        }, status: :ok
      end

      private

      def current_app_user
        current_api_user_payload
      end

      def api_cluster_incharge_mappings
        hierarchy_mappings = cluster_incharge_user_mappings
        return hierarchy_mappings if hierarchy_mappings.any?
        return [] unless model_ready?(:User)

        User.order(:first_name, :last_name, :user_name).filter_map do |user|
          next unless user.active?

          role = [user.role, user.role_name, user.user_management_role, user.person_type]
            .compact_blank.join(" ")
          next unless role.downcase.include?("cluster")

          name = user.full_name.presence || user.user_name.to_s.strip
          next if name.blank?

          {
            label: role.present? ? "#{name} (#{role})" : name,
            value: name,
            office_category: user_office_category(user),
            office_name: user_office_name(user),
            parent_office: user.parent_office.to_s.strip
          }
        end.uniq { |mapping| normalize_approver_label(mapping[:value]) }
      end

      def render_master(resource_name)
        slug, fields = MASTER_CONFIG.fetch(resource_name)
        records = ModuleRecord.where(module_slug: slug).order(created_at: :desc)
        records = records.select { |record| active_record?(record) } unless include_inactive?
        records = records.select { |record| matches_filters?(record) }
        rows = records.map { |record| record_payload(record, fields) }
        rows = rows.reject { |row| row[:jeevika_jankar_type_name].blank? } if resource_name == "types"

        response = {
          success: true,
          message: "#{resource_name.humanize} fetched successfully.",
          resource_name => rows,
          count: rows.size
        }
        response[:jeevika_jankar_types] = rows if resource_name == "types"

        render json: response, status: :ok
      end

      def record_payload(record, fields)
        payload = fields.each_with_object({ id: record.id }) do |field, result|
          result[field] = record.data[field]
        end

        if record.module_slug == "add-vrp-type"
          type_name = record.data["jeevika_jankar_type_name"].presence ||
            record.data["vrp_type_name"].presence ||
            record.data["position_type_name"].presence
          payload[:jeevika_jankar_type_name] = type_name
          payload[:label] = type_name
          payload[:value] = record.id
        end

        payload
      end

      def active_record?(record)
        status = record.data["status"].to_s.strip
        status.blank? || status.casecmp("active").zero?
      end

      def include_inactive?
        ActiveModel::Type::Boolean.new.cast(params[:include_inactive])
      end

      def matches_filters?(record)
        filter_keys.all? do |key|
          requested = params[key].to_s.strip
          requested.blank? || record.data[key].to_s.strip.casecmp(requested).zero?
        end
      end

      def filter_keys
        %w[state district block gram_panchayat stakeholder_category parent_category office_name financial_year]
      end

      def normalized_status(status)
        status.to_s.casecmp("inactive").zero? ? "Inactive" : "Active"
      end

      def merge_json_body_params!
        return unless request.body.present?

        body = request.raw_post.to_s
        return if body.blank?

        json = JSON.parse(body)
        json.each { |key, value| params[key] = value if params[key].blank? } if json.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
