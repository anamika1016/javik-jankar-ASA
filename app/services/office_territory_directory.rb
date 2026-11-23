require "net/http"
require "uri"

# One Office List source for Target Mapping and dashboard master populations.
class OfficeTerritoryDirectory
  URL = "https://asa.ploughmanagro.com/api/get_office_detail_list".freeze

  SNAPSHOTS = ImmutableCatalogueStore.new(size: 16.megabytes)

  def self.items
    snapshot[:items]
  end

  def self.revision
    snapshot[:revision]
  end

  def self.snapshot
    return { items: [], revision: "disabled" } if Rails.application.config.x.office_directory_http_enabled == false
    DashboardCacheFill.synchronize("office-list-api-items-v4") do
      SNAPSHOTS.fetch("office-list-api-items-v4", expires_in: 10.minutes, skip_nil: true) do
        items = Rails.cache.fetch("office-list-api-items-v4", expires_in: 10.minutes, skip_nil: true) do
          fetch(URL).presence
        end
        { items: items, revision: Digest::SHA256.hexdigest(items.to_json) } if items.present?
      end
    end || { items: [], revision: "unavailable" }
  end

  def self.fetch(url)
    uri = URI(url)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 8) do |http|
      http.get(uri.request_uri)
    end
    return [] unless response.is_a?(Net::HTTPSuccess)
    Array(JSON.parse(response.body)["result"]).select { |item| item.is_a?(Hash) }
  rescue StandardError => error
    Rails.logger.warn("Unable to load Office List: #{error.class} - #{error.message}")
    []
  end

  def self.blocks_for(items, fco_id, fco_name = nil)
    fco_id = fco_id.to_s.strip
    selected_name = fco_name.presence || fco_id
    offices = items.select { |office| office["id"].to_s.strip == fco_id }
    if offices.empty? && !fco_id.match?(/\A\d+\z/)
      offices = items.select { |office| office["name"].to_s.strip.casecmp?(selected_name) }
    end

    territory_blocks = lambda do |rows|
      Array(rows).flat_map { |office| Array(office["territory_zones"]) }
        .flat_map { |zone| Array(zone["block"]) }
    end
    blocks = territory_blocks.call(offices)
    return blocks if blocks.any?

    children = items.select do |office|
      if fco_id.match?(/\A\d+\z/)
        office.dig("parent", "id").to_s.strip == fco_id
      else
        office.dig("parent", "name").to_s.strip.casecmp?(selected_name)
      end
    end
    fpc_blocks = territory_blocks.call(children.reject { |office| office["name"].to_s.match?(/\s*-\s*TO\s*\z/i) })
    fpc_blocks.presence || territory_blocks.call(children)
  end
end
