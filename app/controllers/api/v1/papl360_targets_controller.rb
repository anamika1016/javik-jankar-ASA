module Api
  module V1
    class Papl360TargetsController < FarmerTargetBaseController
      MODULE_SLUG = "papl360-target".freeze
      RESOURCE_TITLE = "ASA360 Target".freeze
      RESOURCE_KEY = "papl360_targets".freeze
      PARAM_KEY = :papl360_target

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
