module Api
  module V1
    # News and videos for the signed-in farmer: items published to their own
    # state plus items published to all states, newest first.
    class FarmerFeedController < ActionController::API
      MAX_ITEMS = 100

      def news
        return unless (login = authenticate_farmer!)

        items = feed(FarmerNewsItem, login)
        render json: {
          success: true,
          state: login.state_name,
          state_id: login.state_id,
          count: items.size,
          news: items.map { |item| news_payload(item) }
        }, status: :ok
      end

      def videos
        return unless (login = authenticate_farmer!)

        items = feed(FarmerVideo, login)
        render json: {
          success: true,
          state: login.state_name,
          state_id: login.state_id,
          count: items.size,
          videos: items.map { |video| video_payload(video) }
        }, status: :ok
      end

      private

      # One indexed query per request; nothing is loaded per item.
      def feed(model, login)
        model.active.for_state(login.state_id).newest_first.limit(MAX_ITEMS).to_a
      end

      def authenticate_farmer!
        token = bearer_token
        # A bare "Unauthorized" sends the app developer hunting. Say which of
        # the three things actually went wrong: nothing sent, the wrong family
        # of token, or a farmer token that has expired.
        if token.blank?
          return render_unauthorized(
            "missing_token",
            "Authorization header is missing. Send 'Authorization: Bearer <token>' using " \
            "the token returned by /api/v1/farmer/login/otp/verify."
          )
        end

        login = FarmerApiToken.find_login(token)
        return login if login

        if ApiAuthToken.decode(token)
          return render_unauthorized(
            "wrong_token_type",
            "This is a staff or Jeevika Jankar token. The farmer feed needs the token from " \
            "/api/v1/farmer/login/otp/verify."
          )
        end

        render_unauthorized("invalid_token", "Session expired. Please login again.")
      end

      def render_unauthorized(error, message)
        render json: { success: false, error: error, message: message }, status: :unauthorized
        nil
      end

      def news_payload(item)
        {
          id: item.id,
          title: item.title,
          body: item.body,
          link_url: item.link_url,
          image_url: absolute_url(item.image_path),
          state: item.state_label,
          state_id: item.state_id,
          for_all_states: item.all_states?,
          published_by: item.created_by,
          published_at: item.published_at
        }
      end

      def video_payload(video)
        {
          id: video.id,
          title: video.title,
          description: video.description,
          video_url: absolute_url(video.playback_url),
          # What a player can open directly: the file, or a YouTube embed.
          # Without this the app has to parse YouTube URLs itself.
          embed_url: absolute_url(video.embed_url),
          source_type: video.source_type,
          youtube_id: video.youtube_id,
          thumbnail_url: absolute_url(video.thumbnail_path),
          duration: video.duration_label,
          uploaded: video.uploaded?,
          state: video.state_label,
          state_id: video.state_id,
          for_all_states: video.all_states?,
          published_by: video.created_by,
          published_at: video.published_at
        }
      end

      # Uploads are stored as site-relative paths; the app needs a full URL.
      def absolute_url(path)
        value = path.to_s.strip
        return if value.blank?
        return value if value.match?(%r{\Ahttps?://})

        "#{request.base_url}#{value.start_with?('/') ? value : "/#{value}"}"
      end

      def bearer_token
        header = request.headers["Authorization"].to_s
        return header.delete_prefix("Bearer ").strip if header.start_with?("Bearer ")

        params[:token].presence
      end
    end
  end
end
