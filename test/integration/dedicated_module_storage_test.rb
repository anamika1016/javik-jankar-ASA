require "test_helper"

class DedicatedModuleStorageTest < ActionDispatch::IntegrationTest
  setup do
    admin = User.create!(user_name: "dedicated_admin", password: "secret", first_name: "Admin", user_type: "admin", status: "Active")
    post login_path, params: {login: admin.user_name, password: "secret"}
  end

  def without_archive_queries
    queries = []
    listener = ->(*args) do
      sql = args.last[:sql]
      queries << sql if sql.match?(/\b(?:FROM|JOIN|INTO|UPDATE)\s+(?:public\.)?"?module_records\b/i)
    end
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { yield }
    assert_empty queries, "Active requests must not query the retained archive"
  end

  test "web create edit delete keep the existing form contract and write only dedicated storage" do
    archive_count = ModuleRecord.count
    without_archive_queries do
      post "/modules/project-master/records", params: {module_record: {project_name: "Original", status: "Active"}}
      assert_response :redirect
      record = ModuleEntry.where(module_slug: "project-master").sole
      assert_equal "Original", record.data["project_name"]
      assert_equal "module_record", record.model_name.param_key
      get edit_module_record_path("project-master", record)
      assert_response :success
      assert_select "form[action='#{module_record_path('project-master', record)}']", minimum: 1
      patch module_record_path("project-master", record), params: {module_record: {project_name: "Updated", status: "Active"}}
      assert_response :redirect
      assert_equal "Updated", record.reload.data["project_name"]
      delete module_record_path("project-master", record), as: :json
      assert_response :success
      refute ModuleEntry.exists?(record.id)
    end
    assert_equal archive_count, ModuleRecord.count
  end

  test "directory bulk insert derives columns and returns original IDs without source replay" do
    without_archive_queries do
      result = ModuleEntry.insert_all!([
        {module_slug: "block-master", data: {"block"=>"Block A", "state"=>"State", "status"=>"Active"}},
        {module_slug: "village-master", data: {"village"=>"Village A", "cd_block_name"=>"Block A", "status"=>"Active"}}
      ])
      assert_equal 2, result.rows.size
      assert_equal "Block A", LgBlock.find(result.rows[0][0]).block_name
      assert_equal "Village A", LgVillage.find(result.rows[1][0]).village_name
      assert_equal result.rows.flatten.sort, ModuleEntry.where(id: result.rows.flatten).pluck(:id).sort
    end
  end

  test "module identity in tokens and password updates remains compatible" do
    without_archive_queries do
      user = ModuleEntry.create!(module_slug: "new-user", data: {"user_name"=>"dedicated_login", "password"=>"Before", "status"=>"Active"})
      token = ApiAuthToken.encode(user)
      assert_equal "ModuleRecord", ApiAuthToken.decode(token)["record_type"]
      assert_equal user.id, ApiAuthToken.find_user(token).id
      ApiPasswordReset.update_password!(user, "After")
      assert_equal "After", user.reload.data["password"]
    end
  end

  test "dependency and module writes invalidate live bill snapshot stamps" do
    before = ModuleRecordReadVersion.read(dependencies: %w[afls target_mappings vrps users])
    without_archive_queries do
      ModuleEntry.create!(module_slug: "project-master", data: {"project_name"=>"Invalidates"})
      after = ModuleRecordReadVersion.read(dependencies: %w[afls target_mappings vrps users])
      refute_equal before, after
      User.create!(user_name: "dedicated_dependency", password: "secret", status: "Active")
      refute_equal after, ModuleRecordReadVersion.read(dependencies: %w[afls target_mappings vrps users])
    end
  end

  test "normal row locks reload and preserve nested data edits" do
    without_archive_queries do
      record = ModuleEntry.create!(module_slug: "training-form-edit-request", data: {"status"=>"Pending", "history"=>[]})
      record.with_lock { record.update!(data: record.data.merge("history"=>["Saved"])) }
      assert_equal ["Saved"], record.reload.data["history"]
      record.data["status"] = "Changed but unsaved"
      assert_raises(RuntimeError) { record.lock! }
    end
  end
end
