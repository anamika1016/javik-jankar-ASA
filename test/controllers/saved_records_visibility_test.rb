require "test_helper"

# show renders the Saved Records table for every entry screen except new-user,
# the entry-only slugs and the other-target forms. The controller decides
# separately whether to load @records, and the two lists had drifted apart:
# Add Jeevika Jankar Type and Training Topic Mapping rendered the table but
# were never given any records, so they always read "No records saved yet."
class SavedRecordsVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "saved_admin", password: "secret",
      first_name: "Adm", user_type: "admin", status: "Active")
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  def page(slug)
    get module_path(slug)
    assert_response :success
    response.body
  end

  test "Add Jeevika Jankar Type shows a saved type" do
    ModuleRecord.create!(module_slug: "add-vrp-type", data: {
      "jeevika_jankar_type_name" => "SAVED_JJ_TYPE", "status" => "Active"
    })

    body = page("add-vrp-type")

    assert_includes body, "SAVED_JJ_TYPE",
      "the saved type was not listed under Saved Records"
    assert_not_includes body, "No records saved yet."
  end

  test "Training Topic Mapping shows a saved mapping" do
    ModuleRecord.create!(module_slug: "training-topic-mapping", data: {
      "training_topic" => "SAVED_TOPIC_ROW", "status" => "Active"
    })

    body = page("training-topic-mapping")

    assert_includes body, "SAVED_TOPIC_ROW",
      "the saved mapping was not listed under Saved Records"
  end

  test "an entry screen with nothing saved still says so" do
    body = page("add-vrp-type")

    assert_includes body, "No records saved yet."
  end

  # The screens that deliberately do not load records keep that behaviour:
  # their rows live on their own list pages, so loading them here is wasted.
  test "the other-target form still renders no Saved Records table" do
    ModuleRecord.create!(module_slug: "other-target", data: {
      "month" => "October", "status" => "Active"
    })

    body = page("other-target")

    assert_not_includes body, "Saved Records",
      "other-target rows belong to other-target-list, not this form"
  end

  test "the training entry form still renders no Saved Records table" do
    body = page("training-form")

    assert_not_includes body, "Saved Records"
  end
end
