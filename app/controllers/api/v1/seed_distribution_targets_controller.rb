module Api
  module V1
    class SeedDistributionTargetsController < FarmerTargetBaseController
      MODULE_SLUG = "seed-distribution-target".freeze
      RESOURCE_TITLE = "Seed Distribution Target".freeze
      RESOURCE_KEY = "seed_distribution_targets".freeze
      PARAM_KEY = :seed_distribution_target

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
