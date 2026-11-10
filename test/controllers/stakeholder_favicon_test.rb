require "test_helper"

class StakeholderFaviconTest < ActiveSupport::TestCase
  def helper_with_cache(cache, stakeholder)
    helper = Object.new.extend(ApplicationHelper)
    helper.define_singleton_method(:branding_cache) { cache }
    helper.define_singleton_method(:current_app_user) { { "stakeholder" => stakeholder } }
    helper
  end

  test "master logo overrides profile logo and live tuple revision invalidates warm branding cache" do
    cache = ActiveSupport::Cache::MemoryStore.new
    master = ModuleRecord.create!(module_slug: "stakeholder-master", data: {
      "stakeholder_name_in_english" => "Favicon ASA", "logo_upload" => "/uploads/master-before.png", "status" => "Active" })
    ModuleRecord.create!(module_slug: "stakeholder-profile", data: {
      "stakeholder_name" => "Favicon ASA", "logo_upload" => "/uploads/profile.png", "status" => "Active" })
    assert_equal "/uploads/master-before.png", helper_with_cache(cache, "Favicon ASA").app_stakeholder_logo
    master.update_columns(data: master.data.merge("logo_upload" => "/uploads/master-after.png"))
    assert_equal "/uploads/master-after.png", helper_with_cache(cache, "Favicon ASA").app_stakeholder_logo
    master.update_columns(data: master.data.merge("status" => "Inactive"))
    assert_equal "/uploads/profile.png", helper_with_cache(cache, "Favicon ASA").app_stakeholder_logo
    master.destroy!
    assert_equal "/uploads/profile.png", helper_with_cache(cache, "Favicon ASA").app_stakeholder_logo
  end

  test "favicon HTML follows the configured master logo after an edit" do
    session = ActionDispatch::Integration::Session.new(Rails.application)
    logo = ModuleRecord.create!(module_slug: "stakeholder-master", data: {
      "stakeholder_name_in_english" => "Favicon Render", "logo_upload" => "/uploads/favicon-render.png" })
    session.get('/login')
    assert_equal 200, session.response.status
    document = Nokogiri::HTML(session.response.body)
    assert_equal [logo.data["logo_upload"]], document.css('link[rel="icon"]').map { |node| node['href'] }
    assert_equal [logo.data["logo_upload"]], document.css('link[rel="apple-touch-icon"]').map { |node| node['href'] }
    logo.update_columns(data: logo.data.merge("logo_upload" => "/uploads/favicon-new.png"))
    session.get('/login')
    document = Nokogiri::HTML(session.response.body)
    assert_equal ["/uploads/favicon-new.png"], document.css('link[rel="icon"]').map { |node| node['href'] }
  end
end
