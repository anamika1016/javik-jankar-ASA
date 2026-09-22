module Api
  module V1
    class TrainingFormsController < FarmerTrainingsController
      MODULE_SLUG = "training-form".freeze
      RESOURCE_TITLE = "Training Form".freeze
      RESOURCE_KEY = "training_forms".freeze
      PARAM_KEY = :training_form

      def index
        render_list(self.class::RESOURCE_KEY)
      end

      def photos
        record = farmer_target_api.find(params[:id])
        unless record
          return render json: { success: false, message: "Training Form record not found." }, status: :not_found
        end

        paths = training_photo_paths(record)
        photos = paths.map.with_index do |path, index|
          {
            id: index + 1,
            url: path.to_s.match?(/\Ahttps?:\/\//i) ? path : "#{request.base_url}#{path}",
            filename: File.basename(path.to_s)
          }
        end

        render json: {
          success: true,
          training_form_id: record.id,
          photo_count: photos.size,
          photos: photos
        }, status: :ok
      end
    end
  end
end
