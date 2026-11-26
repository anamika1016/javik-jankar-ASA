module Api
  module V1
    # Crop masters for the app's dropdowns (read only; they are maintained on
    # the web under Crop). Filters accept a name or an id:
    #   GET /api/v1/crop-seasons
    #   GET /api/v1/crop-types?crop_season=Kharif        (or crop_season_id=)
    #   GET /api/v1/crops?crop_season=Kharif&crop_type=Cereal  (or *_id=)
    #   GET /api/v1/crop-masters   season -> types -> crops in one call
    class CropsController < BaseController
      def seasons
        render json: { success: true, crop_seasons: catalogue.seasons, count: catalogue.seasons.size }, status: :ok
      end

      def types
        types = catalogue.types(crop_season: crop_season)
        render json: { success: true, crop_types: types, count: types.size }, status: :ok
      end

      def index
        crops = catalogue.crops(crop_season: crop_season, crop_type: crop_type)
        render json: { success: true, crops: crops, count: crops.size }, status: :ok
      end

      def masters
        render json: { success: true, crop_seasons: catalogue.tree }, status: :ok
      end

      private

      def catalogue
        @catalogue ||= CropCatalogue.new
      end

      # An id that matches nothing filters to nothing, rather than to everything.
      def crop_season
        return params[:crop_season] if params[:crop_season_id].blank?

        catalogue.season_name(params[:crop_season_id]) || CropCatalogue::NO_MATCH
      end

      def crop_type
        return params[:crop_type] if params[:crop_type_id].blank?

        catalogue.type_name(params[:crop_type_id]) || CropCatalogue::NO_MATCH
      end
    end
  end
end
