require "test_helper"

class NavigationProgressAssetsTest < ActionDispatch::IntegrationTest
  test "application pages resolve the compiled progress module and completed-page CSS" do
    user = User.create!(user_name: "navigation_assets_admin", first_name: "Admin", password: "secret", user_type: "admin", status: "Active")
    post login_path, params: { login: user.user_name, password: "secret" }
    get dashboard_path
    assert_response :success
    assert_select 'meta[name="turbo-cache-control"][content="no-preview"]', count: 1
    assert css_select("script[type='module']").any? { |script| script.text.include?('import "navigation_progress"') },
           "Progress cleanup must boot independently of the application module graph"
    imports = JSON.parse(css_select("script[type='importmap']").first.text).fetch("imports")
    stylesheet_path = URI(css_select("link[rel=stylesheet]").first["href"]).path
    progress_path = URI(imports.fetch("navigation_progress")).path
    get progress_path
    assert_response :success
    assert_includes response.body, "hideVisitProgressBar"
    assert_includes response.body, "turbo:submit-end"
    get stylesheet_path
    assert_response :success
    # The progress element may still be created by Turbo, but it must never be
    # visible on any page (including the dashboard).
    assert_includes response.body, ".turbo-progress-bar {\n  display: none !important;\n}"
  end
end
