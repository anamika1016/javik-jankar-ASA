class LgDirectoryImportJob < ApplicationJob
  queue_as :default

  def perform(blob_id, status_id)
    blob = ActiveStorage::Blob.find(blob_id)
    status_record = ModuleRecord.find(status_id)

    blob.open do |tempfile|
      upload = Struct.new(:path, :original_filename).new(tempfile.path, blob.filename.to_s)
      result = LgDirectoryImporter.import(upload)
      status_record.update!(data: status_record.data.merge(
        "status" => "Completed",
        "imported" => result[:imported],
        "counts" => result[:counts],
        "completed_at" => Time.current.iso8601
      ))
    end
  rescue StandardError => error
    status_record&.update!(data: status_record.data.merge(
      "status" => "Failed",
      "error" => error.message,
      "completed_at" => Time.current.iso8601
    ))
    Rails.logger.error("LG Directory import failed: #{error.class}: #{error.message}")
  ensure
    blob&.purge
  end
end
