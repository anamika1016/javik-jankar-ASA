require "digest"
require "fileutils"

# Read-mostly form catalogues already shared by all viewers. One atomic file
# slot per catalogue/source key (the final key element is its live revision)
# lets Puma workers reuse the expensive fill without accumulating old versions.
class SharedCatalogueCache
  # Capture this at class load (production eager-loads at boot), not after a
  # later deploy has replaced files underneath an already running worker.
  CODE_NAMESPACE = begin
    digest = Digest::SHA256.new
    %w[
      Gemfile.lock app/controllers/application_controller.rb
      app/controllers/modules_controller.rb app/controllers/users_controller.rb
      app/controllers/vrps_controller.rb app/models/module_record.rb app/models/module_entry.rb
      app/services/catalogue_read_cache.rb app/services/shared_catalogue_cache.rb
      app/services/module_record_read_query.rb
      app/services/module_record_read_version.rb
      app/services/module_field_options_cache.rb
      app/services/immutable_catalogue_store.rb
    ].each { |path| digest << File.binread(Rails.root.join(path)) }
    digest.hexdigest.freeze
  end

  def self.default
    @default ||= new(Rails.root.join("tmp/cache/shared-form-catalogues"))
  end

  def initialize(directory)
    @directory = directory.to_s
    @store = ActiveSupport::Cache::FileStore.new(@directory)
  end

  def read(key)
    entry = @store.read(slot(key))
    entry[:value] if entry.is_a?(Hash) && entry[:key] == key && entry[:code] == code_namespace
  rescue StandardError => error
    Rails.logger.warn("Shared catalogue cache read unavailable: #{error.class}")
    nil
  end

  def write(key, value, expires_in:)
    @store.write(slot(key), { key: key, code: code_namespace, value: value }, expires_in: expires_in)
  rescue StandardError => error
    Rails.logger.warn("Shared catalogue cache write unavailable: #{error.class}")
    false
  end

  def synchronize(key)
    # Only failures acquiring the optional cache lock fall back. Exceptions
    # from the actual builder must propagate, never run the builder twice.
    begin
      FileUtils.mkdir_p(@directory)
      file = File.open(File.join(@directory, "#{slot(key)}.lock"), File::RDWR | File::CREAT, 0o600)
      file.flock(File::LOCK_EX)
    rescue SystemCallError, IOError => error
      file&.close
      Rails.logger.warn("Shared catalogue lock unavailable: #{error.class}")
      return yield
    end
    begin
      yield
    ensure
      file.close # Closing releases the flock, including after builder errors.
    end
  end

  private

  def code_namespace
    CODE_NAMESPACE
  end

  def slot(key)
    database = ModuleEntry.connection_pool.db_config.configuration_hash.slice(:host, :port, :database)
    Digest::SHA256.hexdigest(Marshal.dump([Rails.env.to_s, database, Array(key)[0...-1]]))
  end
end
