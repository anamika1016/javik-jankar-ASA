module Api
  module V1
    # News and videos for the signed-in farmer: items published to their own
    # state plus items published to all states, newest first.
    class FarmerFeedController < ActionController::API
      MAX_ITEMS = 100

      def news
        return unless (login = authenticate_farmer!)

        render json: {
          success: true,
          state: login.state_name,
          news: feed(FarmerNewsItem, login).map { |item| news_payload(item) }
        }, status: :ok
      end

      def videos
        return unless (login = authenticate_farmer!)

        render json: {
          success: true,
          state: login.state_name,
          videos: feed(FarmerVideo, login).map { |video| video_payload(video) }
        }, status: :ok
      end

      private

      # One indexed query per request; nothing is loaded per item.
      def feed(model, login)
        model.active.for_state(login.state_id).newest_first.limit(MAX_ITEMS).to_a
      end

      def authenticate_farmer!
        login = FarmerApiToken.find_login(bearer_token)
        return login if login

        render json: { success: false, message: "Unauthorized. Please login again." },
          status: :unauthorized
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
          for_all_states: item.all_states?,
          published_at: item.published_at
        }
      end

      def video_payload(video)
        {
          id: video.id,
          title: video.title,
          description: video.description,
          video_url: absolute_url(video.playback_url),
          thumbnail_url: absolute_url(video.thumbnail_path),
          duration: video.duration_label,
          uploaded: video.uploaded?,
          state: video.state_label,
          for_all_states: video.all_states?,
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
