module Api
  module V1
    class FarmerTrainingsController < FarmerTargetBaseController
      MODULE_SLUG = "training-form".freeze
      RESOURCE_TITLE = "Farmer Training Form".freeze
      RESOURCE_KEY = "farmer_trainings".freeze
      PARAM_KEY = :farmer_training

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
