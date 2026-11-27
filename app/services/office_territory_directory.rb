require "net/http"
require "uri"
require "timeout"

# One Office List source for Target Mapping and dashboard master populations.
class OfficeTerritoryDirectory
  URL = "https://asa.ploughmanagro.com/api/get_office_detail_list".freeze
  FALLBACK_URL = "http://144.76.19.201:3003/api/get_office_detail_list".freeze
  URLS = [URL, FALLBACK_URL].freeze
  CACHE_KEY = "office-list-api-items-v4".freeze
  STALE_CACHE_KEY = "office-list-api-items-v4-stale".freeze
  UNAVAILABLE_CACHE_KEY = "office-list-api-items-v4-unavailable".freeze
  FRESH_FOR = 10.minutes
  STALE_FOR = 24.hours
  # A remote Office API outage must never make every dashboard navigation wait
  # for both endpoint timeouts.  Keep a very short negative cache; the next
  # request is instant, and a recovered endpoint is retried shortly after.
  # The live API itself normally needs several seconds to return its large
  # office hierarchy, so this is deliberately longer than a connect timeout.
  UNAVAILABLE_FOR = 30.seconds

  SNAPSHOTS = ImmutableCatalogueStore.new(size: 16.megabytes)

  def self.items
    snapshot[:items]
  end

  def self.revision
    snapshot[:revision]
  end

  # Dashboard navigation must never wait for a network call. It can use the
  # most recent known Office List (fresh or stale); the Office List screen
  # continues to call +items+ and refresh the source when necessary.
  def self.cached_items
    cached_snapshot[:items]
  end

  def self.cached_revision
    cached_snapshot[:revision]
  end

  def self.cached_snapshot
    return { items: [], revision: "disabled" } if Rails.application.config.x.office_directory_http_enabled == false

    snapshot = SNAPSHOTS.read(CACHE_KEY)
    return snapshot if snapshot.present?

    items = Rails.cache.read(CACHE_KEY).presence || Rails.cache.read(STALE_CACHE_KEY).presence
    return unavailable_snapshot if items.blank?

    { items: items, revision: Digest::SHA256.hexdigest(items.to_json) }
  end

  def self.snapshot
    return { items: [], revision: "disabled" } if Rails.application.config.x.office_directory_http_enabled == false
    return unavailable_snapshot if SNAPSHOTS.read(UNAVAILABLE_CACHE_KEY)

    DashboardCacheFill.synchronize(CACHE_KEY) do
      # Another request may have populated the negative cache while this one
      # was waiting for the first remote attempt to finish.
      next unavailable_snapshot if SNAPSHOTS.read(UNAVAILABLE_CACHE_KEY)

      SNAPSHOTS.fetch(CACHE_KEY, expires_in: FRESH_FOR, skip_nil: true) do
        # A warm cache returns immediately. On a cold/expired cache, the live
        # endpoint gets a deliberately short chance; an outage falls back to
        # the last good snapshot instead of holding the Turbo frame on
        # “Loading offices…” for many seconds.
        items = Rails.cache.read(CACHE_KEY).presence || fetch_current_snapshot.presence
        if items.present?
          Rails.cache.write(CACHE_KEY, items, expires_in: FRESH_FOR)
          Rails.cache.write(STALE_CACHE_KEY, items, expires_in: STALE_FOR)
          SNAPSHOTS.delete(UNAVAILABLE_CACHE_KEY)
        else
          items = Rails.cache.read(STALE_CACHE_KEY).presence
        end
        if items.present?
          { items: items, revision: Digest::SHA256.hexdigest(items.to_json) }
        else
          SNAPSHOTS.write(UNAVAILABLE_CACHE_KEY, true, expires_in: UNAVAILABLE_FOR)
          nil
        end
      end
    end || unavailable_snapshot
  end

  def self.unavailable_snapshot
    { items: [], revision: "unavailable" }
  end
  private_class_method :unavailable_snapshot

  def self.fetch(url)
    uri = URI(url)
    # DNS/connect failures must not leave a Turbo frame loading indefinitely.
    # The outer timeout also covers a resolver that does not honour Net::HTTP's
    # connect timeout; the fallback keeps the office directory available when
    # the public hostname has a transient DNS issue.
    response = Timeout.timeout(15) do
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 12) do |http|
        http.get(uri.request_uri)
      end
    end
    return [] unless response.is_a?(Net::HTTPSuccess)
    Array(JSON.parse(response.body)["result"]).select { |item| item.is_a?(Hash) }
  rescue StandardError => error
    Rails.logger.warn("Unable to load Office List: #{error.class} - #{error.message}")
    []
  end

  def self.fetch_current_snapshot
    # Both endpoints have the same bounded timeout. Start the fallback while
    # the primary is in flight so two network failures do not add six seconds
    # to the first dashboard request. Always prefer the primary result.
    fallback = Thread.new { fetch(FALLBACK_URL) }
    fallback.report_on_exception = false
    primary = fetch(URL)
    return primary if primary.present?

    fallback.value.presence || []
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
