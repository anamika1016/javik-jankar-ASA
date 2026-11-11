# Web side of the farmer feed: list, publish, toggle and delete, shared by
# news and videos because the two screens differ only in their fields.
module FarmerBroadcastAdmin
  extend ActiveSupport::Concern

  PER_PAGE = 50
  VIDEO_EXTENSIONS = %w[.mp4 .mov .m4v .webm .3gp].freeze
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp .gif].freeze

  included do
    helper_method :broadcast_state_options
  end

  def index
    @state_filter = params[:state].to_s.strip
    @page = [params[:page].to_i, 1].max

    scope = broadcast_model.newest_first
    scope = scope.where(state_id: @state_filter == "all" ? nil : @state_filter) if @state_filter.present?

    @total_count = scope.count
    @total_pages = [(@total_count / PER_PAGE.to_f).ceil, 1].max
    @records = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @record = broadcast_model.new
  end

  def create
    @upload_errors = []
    @record = broadcast_model.new(build_attributes)
    # store_upload runs while building the attributes, before @record exists,
    # so its complaints are collected and attached once it does.
    @upload_errors.each { |message| @record.errors.add(:base, message) }

    if @upload_errors.empty? && @record.save
      redirect_to broadcast_index_path, notice: "#{broadcast_label} published."
    else
      @state_filter = ""
      @page = 1
      scope = broadcast_model.newest_first
      @total_count = scope.count
      @total_pages = [(@total_count / PER_PAGE.to_f).ceil, 1].max
      @records = scope.limit(PER_PAGE).to_a
      render :index, status: :unprocessable_entity
    end
  end

  def toggle_status
    record = broadcast_model.find(params[:id])
    record.update!(status: record.active? ? "Inactive" : "Active")
    redirect_to broadcast_index_path, notice: "#{broadcast_label} is now #{record.status}."
  end

  def destroy
    broadcast_model.find(params[:id]).destroy!
    redirect_to broadcast_index_path, notice: "#{broadcast_label} deleted."
  end

  private

  # "all" in the form means every state, which is stored as no state at all.
  def selected_state_id
    value = params.dig(record_param_key, :state_id).to_s.strip
    value == "all" ? nil : value.presence
  end

  def common_attributes
    {
      title: params.dig(record_param_key, :title).to_s.strip,
      state_id: selected_state_id,
      status: "Active",
      published_at: parse_published_at,
      # The session payload spells these "name" and "username"; reading
      # "user_name" here left every post with no author.
      created_by: current_app_user&.dig("name").presence || current_app_user&.dig("username")
    }
  end

  def parse_published_at
    raw = params.dig(record_param_key, :published_at).to_s.strip
    return Time.current if raw.blank?

    Time.zone.parse(raw) || Time.current
  end

  # Stored under public/uploads so the app can fetch it over plain HTTP, the
  # same place the module forms put their attachments.
  def store_upload(upload, allowed_extensions)
    return if upload.blank? || !upload.respond_to?(:original_filename)

    extension = File.extname(upload.original_filename.to_s).downcase
    unless allowed_extensions.include?(extension)
      (@upload_errors ||= []) << "Allowed file types: #{allowed_extensions.join(', ')}"
      return
    end

    dir = Rails.root.join("public", "uploads", "farmer_feed")
    FileUtils.mkdir_p(dir)
    basename = File.basename(upload.original_filename.to_s, extension).parameterize.presence || "file"
    filename = "#{Time.current.to_i}-#{SecureRandom.hex(4)}-#{basename}#{extension}"

    if upload.respond_to?(:tempfile) && upload.tempfile
      upload.tempfile.rewind
      IO.copy_stream(upload.tempfile, dir.join(filename))
    else
      File.binwrite(dir.join(filename), upload.read)
    end
    "/uploads/farmer_feed/#{filename}"
  end

  def broadcast_state_options
    @broadcast_state_options ||= AsaLocationNames.state_options
  end
end
