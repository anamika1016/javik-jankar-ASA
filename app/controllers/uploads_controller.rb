class UploadsController < ApplicationController
  MODULE_RECORD_UPLOAD_ROOT = Rails.root.join("public", "uploads", "module_records").freeze
  MODULE_UPLOAD_FALLBACK_ORIGIN = ENV.fetch(
    "MODULE_UPLOAD_BASE_URL",
    "https://krai.ploughmanagro.com"
  ).delete_suffix("/").freeze

  def module_record
    requested_filename = params[:filename].to_s
    safe_filename = File.basename(requested_filename)

    return head :not_found if safe_filename.blank? || safe_filename != requested_filename

    file_path = MODULE_RECORD_UPLOAD_ROOT.join(safe_filename).cleanpath
    return head :not_found unless file_path.dirname == MODULE_RECORD_UPLOAD_ROOT
    unless file_path.file?
      return redirect_to(
        "#{MODULE_UPLOAD_FALLBACK_ORIGIN}/uploads/module_records/#{ERB::Util.url_encode(safe_filename)}",
        allow_other_host: true
      ) if Rails.env.development? && MODULE_UPLOAD_FALLBACK_ORIGIN.present?

      return head :not_found
    end

    send_file file_path,
      type: Rack::Mime.mime_type(file_path.extname, "application/octet-stream"),
      disposition: params[:download].present? ? "attachment" : "inline"
  end
end
