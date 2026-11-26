# Active Crop Season -> Crop Type -> Crop masters, for the mobile API.
# Uses the same "active" rule as the web forms: not deleted, and status blank
# or Active. A type or crop whose parent season/type is not active is left out,
# so the app never offers a choice the web dropdowns would not.
class CropCatalogue
  # Filter value that matches nothing (e.g. an id that is not a saved master).
  NO_MATCH = Object.new.freeze

  def initialize
    @seasons = rows("crop-season-master") { |data| { name: data["crop_season_name"] } }
    season_keys = @seasons.map { |season| key(season[:name]) }.to_set
    @types = rows("crop-type-master") { |data| { name: data["crop_type_name"], crop_season: data["crop_season"] } }
      .select { |type| season_keys.include?(key(type[:crop_season])) }
    type_keys = @types.map { |type| [key(type[:crop_season]), key(type[:name])] }.to_set
    @crops = rows("crop-master") { |data| { name: data["crop_name"], grade: data["grade"], crop_season: data["crop_season"], crop_type: data["crop_type"] } }
      .select { |crop| type_keys.include?([key(crop[:crop_season]), key(crop[:crop_type])]) }
  end

  attr_reader :seasons

  # Records of one master that the web dropdowns treat as active: not
  # deleted, and status blank or Active.
  def self.active_records(slug)
    ModuleRecord.where(module_slug: slug)
      .where.not("COALESCE(LOWER(BTRIM(data::jsonb ->> 'deleted')), '') IN (?)", %w[1 true yes deleted])
      .where.not("COALESCE(LOWER(BTRIM(data::jsonb ->> 'is_deleted')), '') IN (?)", %w[1 true yes deleted])
      .where.not("COALESCE(LOWER(BTRIM(data::jsonb ->> 'discarded')), '') IN (?)", %w[1 true yes deleted])
      .where("COALESCE(BTRIM(data::jsonb ->> 'status'), '') = '' OR LOWER(BTRIM(data::jsonb ->> 'status')) = 'active'")
      .order(:id)
  end

  def types(crop_season: nil)
    @types.select { |type| matches?(type[:crop_season], crop_season) }
  end

  def crops(crop_season: nil, crop_type: nil)
    @crops.select { |crop| matches?(crop[:crop_season], crop_season) && matches?(crop[:crop_type], crop_type) }
  end

  # Season -> its types -> their crops, for one call that fills all three dropdowns.
  def tree
    @seasons.map do |season|
      season.merge(crop_types: types(crop_season: season[:name]).map do |type|
        type.except(:crop_season).merge(crops: crops(crop_season: season[:name], crop_type: type[:name]).map { |crop| crop.slice(:id, :name, :grade) })
      end)
    end
  end

  def season_name(id) = name_by_id(@seasons, id)
  def type_name(id) = name_by_id(@types, id)

  private

  def rows(slug)
    self.class.active_records(slug)
      .filter_map do |record|
        row = yield(record.data).transform_values { |value| value.to_s.strip }
        { id: record.id }.merge(row) if row[:name].present?
      end
      .uniq { |row| row.except(:id).transform_values { |value| key(value) } }
      .sort_by { |row| key(row[:name]) }
  end

  def matches?(value, wanted)
    return false if wanted.equal?(NO_MATCH)

    wanted.to_s.strip.blank? || key(value) == key(wanted)
  end

  def name_by_id(rows, id)
    rows.find { |row| row[:id].to_s == id.to_s.strip }&.dig(:name)
  end

  def key(value)
    value.to_s.squish.downcase
  end
end
