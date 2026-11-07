require "test_helper"

class MutationGetRedirectTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "mutation_admin", first_name: "Admin", password: "secret", user_type: "admin", status: "Active")
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  test "user deletion preserves the deletion and notice then navigates with GET" do
    user = User.create!(user_name: "mutation_delete_user", first_name: "Delete User", password: "secret", status: "Active")
    assert_difference("User.count", -1) { delete user_path(user) }
    assert_response :see_other
    assert_redirected_to users_path
    follow_redirect!
    assert_equal "GET", request.request_method
    assert_response :success
    assert_includes response.body, "User deleted successfully."
  end

  test "farmer deletion preserves list filters and follows with GET" do
    farmer = Afl.create!(farmer_name: "Mutation Farmer", fco_id: "F")
    assert_difference("Afl.count", -1) { delete afl_path(farmer), params: { q: "Keep", page: "2", fcoc: "Office", fco_id: ["F"] } }
    assert_response :see_other
    assert_redirected_to afls_path(q: "Keep", page: "2", fcoc: "Office", fco_id: ["F"])
    follow_redirect!
    assert_equal "GET", request.request_method
    assert_response :success
  end
end
