require "test_helper"

class JjExamControllerTest < ActionDispatch::IntegrationTest
  test "admin QR start link opens login for the selected exam" do
    quiz = create_quiz(title: "WhatsApp QR Exam")
    create_question(quiz)

    get start_jj_exam_path(quiz)

    assert_response :success
    assert_includes response.body, "WhatsApp QR Exam"
    assert_select "input[name=?][value=?]", "jj_quiz_id", quiz.id.to_s
    assert_not_includes response.body, "Scan QR to start exam"
  end

  test "direct public login asks candidate to scan admin QR first" do
    get jj_exam_login_path

    assert_response :success
    assert_includes response.body, "Scan QR to start exam"
    assert_select "input[name=?]", "jj_quiz_id", count: 0
  end

  private

  def create_quiz(attributes = {})
    JjQuiz.create!({
      title: "JJ Exam",
      duration_minutes: 30,
      status: "published"
    }.merge(attributes))
  end

  def create_question(quiz, attributes = {})
    quiz.questions.create!({
      question_text: "Question?",
      option_a: "A",
      option_b: "B",
      correct_option: "A",
      marks: 1,
      position: 1
    }.merge(attributes))
  end
end
