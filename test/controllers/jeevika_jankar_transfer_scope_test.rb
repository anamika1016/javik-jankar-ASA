require "test_helper"

# The Jeevika Jankar Transfer lookup runs inside module_cluster_visible_vrps,
# which almost every module list touches. A helper missing there took down the
# whole page, so these guard that path.
class JeevikaJankarTransferScopeTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "transfer_admin", password: "secret",
                          first_name: "Adm", user_type: "admin", status: "Active")
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "bill_month" => "September", "select_vrp" => "1",
      "select_vrp_name" => "TRANSFER_BILL_JJ",
      "status" => "Submitted (Not sent for approval)"
    })
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "September", "gram_name" => "TRANSFER_TRAINING_ROW"
    })
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  test "the bill list renders while the transfer lookup runs" do
    get module_path("jeevika-jankar-bill-list")
    assert_response :success
    assert_includes response.body, "TRANSFER_BILL_JJ"
  end

  test "the training form list renders while the transfer lookup runs" do
    get module_path("training-form-list")
    assert_response :success
    assert_includes response.body, "TRANSFER_TRAINING_ROW"
  end

  test "a transfer record still routes by label once a cluster label matches" do
    get module_path("jeevika-jankar-transfer")
    assert_response :success
  end

  # The transfer match has to ignore the role in brackets, like the rest of the app.
  test "approver labels drop the bracketed role before matching" do
    controller = ModulesController.new
    assert_equal "akash mandal",
      controller.send(:normalize_approver_label, "Akash Mandal (FCO-C Turekela)")
    assert_equal "akash mandal",
      controller.send(:normalize_approver_label, "  Akash Mandal  ")
    assert_equal "", controller.send(:normalize_approver_label, nil)
  end
end
