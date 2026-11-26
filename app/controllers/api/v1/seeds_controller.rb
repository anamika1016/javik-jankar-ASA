module Api
  module V1
    # Seed masters for the app (read only; maintained on the web under Seed).
    # Filters accept a name or an id:
    #   GET /api/v1/seed-crops
    #   GET /api/v1/seed-varieties?seed_crop=Soybean            (or seed_crop_id=)
    #   GET /api/v1/seed-products?seed_crop=&seed_variety=&fpo= (or *_id=)
    #   GET /api/v1/seed-products/:id
    #   GET /api/v1/seed-masters   seed crop -> varieties -> products in one call
    # A product's amount/subsidy is null when it is not to be shown to farmers.
    class SeedsController < BaseController
      def crops
        render json: { success: true, seed_crops: catalogue.crops, count: catalogue.crops.size }, status: :ok
      end

      def varieties
        rows = catalogue.varieties(seed_crop: seed_crop)
        render json: { success: true, seed_varieties: rows, count: rows.size }, status: :ok
      end

      def products
        rows = catalogue.products(seed_crop: seed_crop, seed_variety: seed_variety, fpo: params[:fpo])
        render json: { success: true, seed_products: rows, count: rows.size }, status: :ok
      end

      def product
        row = catalogue.product(params[:id])
        return render json: { success: false, message: "Seed product not found." }, status: :not_found unless row

        render json: { success: true, seed_product: row }, status: :ok
      end

      def masters
        render json: { success: true, seed_crops: catalogue.tree }, status: :ok
      end

      private

      def catalogue
        @catalogue ||= SeedCatalogue.new(base_url: request.base_url)
      end

      def seed_crop
        return params[:seed_crop] if params[:seed_crop_id].blank?

        catalogue.crop_name(params[:seed_crop_id]) || SeedCatalogue::NO_MATCH
      end

      def seed_variety
        return params[:seed_variety] if params[:seed_variety_id].blank?

        catalogue.variety_name(params[:seed_variety_id]) || SeedCatalogue::NO_MATCH
      end
    end
  end
end
