require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module VrpApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Asia/Kolkata"

    # Writable views, shared ID sequences and transactional version triggers
    # are part of the storage contract and must survive fresh DB/test restores.
    config.active_record.schema_format = :sql

    # The app ships long option lists - the User Registration form alone sends a
    # 529 kB location map plus a 1,761-option village select, 1.1 MB of HTML -
    # and markup of that shape gzips about eighteen times, down to 63 kB. This
    # used to be limited to /api, so every page of the website was served
    # uncompressed and paid the full size on each load.
    #
    # Selected by response content type rather than by path: text, JSON,
    # JavaScript and SVG compress well, while the spreadsheet and file downloads
    # elsewhere in the app are already compressed containers and are left alone.
    # Nothing in the app streams a response, so there is nothing for the
    # middleware's buffering to hold open.
    compressible_response = %r{\A(?:text/|application/(?:json|javascript|xml|xhtml\+xml)|image/svg\+xml)}
    config.middleware.use Rack::Deflater,
      if: ->(_env, _status, headers, _body) {
        # Rack 3 downcases header names; be tolerant of either spelling.
        content_type = headers["content-type"] || headers["Content-Type"]
        content_type.to_s.match?(compressible_response)
      }
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
