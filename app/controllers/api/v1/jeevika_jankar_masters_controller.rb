module Api
  module V1
    class JeevikaJankarMastersController < BaseController
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
        "types" => [ "add-vrp-type", %w[jeevika_jankar_type_name status] ]
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
          record.data["jeevika_jankar_type_name"].to_s.casecmp(name.to_s.strip).zero?
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

      private

      def render_master(resource_name)
        slug, fields = MASTER_CONFIG.fetch(resource_name)
        records = ModuleRecord.where(module_slug: slug).order(created_at: :desc)
        records = records.select { |record| active_record?(record) } unless include_inactive?
        records = records.select { |record| matches_filters?(record) }
        rows = records.map { |record| record_payload(record, fields) }

        render json: {
          success: true,
          message: "#{resource_name.humanize} fetched successfully.",
          resource_name => rows,
          count: rows.size
        }, status: :ok
      end

      def record_payload(record, fields)
        fields.each_with_object({ id: record.id }) do |field, payload|
          payload[field] = record.data[field]
        end
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
