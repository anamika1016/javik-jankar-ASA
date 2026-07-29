class LgDirectoryImportJob < ApplicationJob
  queue_as :default

  def perform(file_path)
    return unless file_path.present? && File.exist?(file_path)

    begin
      result = LgDirectoryImporter.import_path(file_path)
      Rails.logger.info("LG Directory import finished: #{result[:imported]} records created, skipped=#{result[:skipped].size}")
    rescue StandardError => e
      Rails.logger.error("LG Directory import failed for #{file_path}: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}")
      raise
    ensure
      File.delete(file_path) if file_path.present? && File.exist?(file_path)
    end
  end
end
