module Api
  module V1
    class AddFarmerFormsController < FarmerTargetBaseController
      MODULE_SLUG = "add-farmer-form".freeze
      RESOURCE_TITLE = "Add Farmer Form".freeze
      RESOURCE_KEY = "add_farmer_forms".freeze
      PARAM_KEY = :add_farmer_form

      def index
        render_list(RESOURCE_KEY)
      end

      def show
        render_show
      end

      def create
        render_create
      end

      def form_options
        render_form_options
      end
    end
  end
end
