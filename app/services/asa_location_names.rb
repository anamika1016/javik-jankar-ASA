require "net/http"
require "uri"
require "json"

# Turns the numeric ids the ASA register returns into place names.
#
# farmer_details_by_identifier answers with state_id / district_id / block_id /
# village_id and no names at all, so a login row had nothing to show under
# village or district. The register's own master endpoints are the matching
# source: resolving against the LG directory instead would be guesswork,
# because those are LGD codes and these are ASA's own ids.
#
# Read-only, and cached: these masters change rarely, so a login does not pay
# for them more than once a day.
class AsaLocationNames
  BASE = "https://asa.ploughmanagro.com/api".freeze
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 8
  CACHE_TTL = 12.hours

  class << self
    def state(state_id)
      lookup(:state, "state_all", {}, state_id)
    end

    # Districts and villages are only listable under their parent, so the
    # parent id has to be known. The register sends both on the land row.
    def district(district_id, state_id:)
      return if state_id.blank?

      lookup(:district, "district_all", { state_id: state_id }, district_id)
    end

    def block(block_id, district_id:)
      return if district_id.blank?

      lookup(:block, "block_all", {}, block_id) ||
        lookup(:block, "block_all", { district_id: district_id }, block_id)
    end

    def village(village_id, block_id:)
      return if block_id.blank?

      lookup(:village, "vill_all", { block_id: block_id }, village_id)
    end

    # Everything a land row can tell us, in as few calls as possible.
    def for_land_row(row)
      row = (row || {}).with_indifferent_access
      state_id = row[:state_id]
      district_id = row[:district_id]
      block_id = row[:block_id]

      {
        state_name: state(state_id),
        district_name: district(district_id, state_id: state_id),
        block_name: block(block_id, district_id: district_id),
        village_name: village(row[:village_id], block_id: block_id)
      }.compact
    end

    private

    def lookup(kind, path, params, wanted_id)
      wanted = wanted_id.to_s.strip
      return if wanted.blank? || wanted == "0"

      index(kind, path, params)[wanted]
    end

    def index(kind, path, params)
      key = ["asa-location-names-v1", kind, params.sort.to_h].flatten.join(":")
      Rails.cache.fetch(key, expires_in: CACHE_TTL) { fetch_index(path, params) } || {}
    end

    def fetch_index(path, params)
      uri = URI("#{BASE}/#{path}")
      uri.query = URI.encode_www_form(params) if params.present?

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |http| http.get(uri.request_uri) }
      return {} unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      rows = payload["result"]
      return {} unless rows.is_a?(Array)

      rows.each_with_object({}) do |row, names|
        id = row["id"].to_s.strip
        name = row["name"].to_s.strip
        names[id] = name if id.present? && name.present?
      end
    rescue StandardError => error
      Rails.logger.warn("ASA location names (#{path}) failed: #{error.class} - #{error.message}")
      {}
    end
  end
end
