require "test_helper"

class JjQuizTest < ActiveSupport::TestCase
  test "shareable check reuses preloaded questions without changing active status behavior" do
    quiz = JjQuiz.create!(title: "Preloaded exam", duration_minutes: 20, status: "published")
    quiz.questions.create!(question_text: "Inactive", option_a: "A", option_b: "B", correct_option: "A", status: "inactive")
    quiz.questions.create!(question_text: "Active", option_a: "A", option_b: "B", correct_option: "A", status: "active")
    loaded = JjQuiz.includes(:questions).find(quiz.id)

    queries = []
    subscriber = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].start_with?("SELECT")
    end
    result = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { loaded.shareable_for_exam? }

    assert result
    assert_empty queries
    assert JjQuiz.find(quiz.id).shareable_for_exam?
  end
end
