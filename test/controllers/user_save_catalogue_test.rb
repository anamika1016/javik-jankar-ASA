require "test_helper"

class UserSaveCatalogueTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "catalogue_save_admin", first_name: "Admin", password: "secret", user_type: "admin", status: "Active")
    @user = User.create!(user_name: "catalogue_save_user", first_name: "Original", password: "secret")
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Save Test State" })
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  test "successful create and update skip form catalogue queries" do
    queries = []
    capture = ->(*args) do
      sql = args.last[:sql].to_s
      # Username uniqueness still checks legacy accounts; that is a write
      # validation, independent of loading the form's catalogue.
      queries << sql if sql.include?('"module_records"') && sql.start_with?("SELECT") && !sql.start_with?("SELECT 1 AS one")
    end
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") do
      post users_path, params: { user: { user_name: "catalogue_created", password: "secret", confirmed_password: "secret" } }
      assert_redirected_to users_path
      patch user_path(@user), params: { user: { first_name: "Changed", password: "secret", confirmed_password: "secret" } }
      assert_redirected_to users_path
    end
    assert_empty queries
    assert_equal "Changed", @user.reload.first_name
  end

  test "password mismatch and model validation errors retain location options" do
    [true, false].each do |update|
      [{ user_name: "valid", password: "secret", confirmed_password: "wrong" },
       { user_name: "", password: "secret", confirmed_password: "secret" }].each do |attributes|
        if update
          patch user_path(@user), params: { user: attributes }
        else
          post users_path, params: { user: attributes }
        end
        assert_response :unprocessable_entity
        assert_select "[data-location-level='state'] option", text: "Save Test State", count: 1
      end
    end
  end
end
