module Api
  module V1
    # GET /api/v1/units  active units from the Unit Master (read only).
    class UnitsController < BaseController
      def index
        units = CropCatalogue.active_records("unit-master")
          .filter_map { |record| { id: record.id, name: record.data["unit_name"].to_s.strip } }
          .reject { |unit| unit[:name].blank? }
          .uniq { |unit| unit[:name].squish.downcase }
          .sort_by { |unit| unit[:name].squish.downcase }

        render json: { success: true, units: units, count: units.size }, status: :ok
      end
    end
  end
end
