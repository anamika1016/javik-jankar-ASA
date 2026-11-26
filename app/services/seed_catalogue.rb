# Active Seed Crop -> Seed Variety -> Seed Product masters, for the mobile API.
# Same "active" rule as the web forms. A variety or product whose seed crop
# or variety is not active is left out. A product's Amount or Subsidy is only
# given when its "Kisan ko dikhaye" tick is on (amount_status/subsidy_status).
class SeedCatalogue
  NO_MATCH = CropCatalogue::NO_MATCH

  def initialize(base_url: nil)
    @base_url = base_url.to_s.chomp("/")
    @crops = rows("seed-crop-master") { |data| { name: data["seed_crop_name"].to_s.strip } }
    crop_keys = @crops.map { |crop| key(crop[:name]) }.to_set
    @varieties = rows("seed-variety-master") { |data| { name: data["seed_variety_name"].to_s.strip, seed_crop: data["seed_crop"].to_s.strip } }
      .select { |variety| crop_keys.include?(key(variety[:seed_crop])) }
    variety_keys = @varieties.map { |variety| [key(variety[:seed_crop]), key(variety[:name])] }.to_set
    @products = CropCatalogue.active_records("seed-product-master")
      .map { |record| product_payload(record) }
      .select { |product| variety_keys.include?([key(product[:seed_crop]), key(product[:seed_variety])]) }
  end

  attr_reader :crops

  def varieties(seed_crop: nil)
    @varieties.select { |variety| matches?(variety[:seed_crop], seed_crop) }
  end

  def products(seed_crop: nil, seed_variety: nil, fpo: nil)
    @products.select do |product|
      matches?(product[:seed_crop], seed_crop) && matches?(product[:seed_variety], seed_variety) &&
        (fpo.to_s.strip.blank? || product[:fpo].any? { |name| key(name) == key(fpo) })
    end
  end

  def product(id)
    @products.find { |product| product[:id].to_s == id.to_s.strip }
  end

  # Seed crop -> its varieties -> their products, in one call.
  def tree
    @crops.map do |crop|
      crop.merge(seed_varieties: varieties(seed_crop: crop[:name]).map do |variety|
        variety.except(:seed_crop).merge(seed_products: products(seed_crop: crop[:name], seed_variety: variety[:name]))
      end)
    end
  end

  def crop_name(id) = @crops.find { |row| row[:id].to_s == id.to_s.strip }&.dig(:name)
  def variety_name(id) = @varieties.find { |row| row[:id].to_s == id.to_s.strip }&.dig(:name)

  private

  def rows(slug)
    CropCatalogue.active_records(slug)
      .filter_map { |record| { id: record.id }.merge(yield(record.data)) if yield(record.data)[:name].present? }
      .uniq { |row| row.except(:id).transform_values { |value| key(value) } }
      .sort_by { |row| key(row[:name]) }
  end

  def product_payload(record)
    data = record.data
    # Shown to farmers only when ticked (saved as Active).
    show_amount = data["amount_status"].to_s == "Active"
    show_subsidy = data["subsidy_status"].to_s == "Active"
    {
      id: record.id,
      seed_crop: data["seed_crop"].to_s.strip,
      seed_variety: data["seed_variety"].to_s.strip,
      seed_brand_name: data["seed_brand_name"].to_s.strip,
      fpo: Array(data["fpo"]).map { |name| name.to_s.strip }.compact_blank,
      supplier_company_name: data["supplier_company_name"].to_s.strip,
      description: data["description"].to_s.strip.presence,
      photo_url: photo_url(data["product_photo_upload"]),
      show_amount: show_amount,
      amount: (number(data["amount"]) if show_amount),
      show_subsidy: show_subsidy,
      subsidy: (number(data["subsidy"]) if show_subsidy)
    }
  end

  def photo_url(value)
    path = Array(value).flatten.map(&:to_s).find(&:present?)
    return if path.blank?
    return path if path.start_with?("http://", "https://")

    "#{@base_url}#{path.start_with?("/") ? path : "/#{path}"}"
  end

  def number(value)
    text = value.to_s.strip
    return if text.blank?

    BigDecimal(text).to_s("F").sub(/\.0\z/, "")
  rescue ArgumentError
    nil
  end

  def matches?(value, wanted)
    return false if wanted.equal?(NO_MATCH)

    wanted.to_s.strip.blank? || key(value) == key(wanted)
  end

  def key(value)
    value.to_s.squish.downcase
  end
end
