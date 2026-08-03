module Api
  module V1
    class SidebarMenusController < BaseController
      include ApplicationHelper

      def index
        render json: {
          success: true,
          message: "Sidebar menu access fetched successfully.",
          user: current_api_user_payload,
          sidebar_sections: sidebar_sections.map { |section| section_payload(section) }
        }, status: :ok
      end

      private

      def current_app_user
        current_api_user_payload
      end

      def section_payload(section)
        {
          title: section[:title],
          icon: section[:icon],
          menus: section[:links].map { |link| menu_payload(link) }
        }
      end

      def menu_payload(link)
        label, type, target = link
        {
          name: label,
          key: sidebar_access_key(link),
          type: type.to_s,
          target: target.to_s
        }
      end
    end
  end
end
