require "test_helper"
require "rexml/document"
require "stringio"
require "zip"

class JjQuizzesControllerTest < ActionDispatch::IntegrationTest
  test "show renders admin QR sharing actions" do
    admin = create_admin_user
    quiz = create_quiz(title: "Shareable JJ Exam")
    create_question(quiz)

    post login_path, params: { login: admin.user_name, password: "secret" }
    get jj_quiz_path(quiz)

    assert_response :success
    assert_includes response.body, "Share Exam QR"
    assert_includes response.body, "Share on WhatsApp"
    assert_includes response.body, start_jj_exam_url(quiz)
  end

  test "question format download only contains question columns" do
    admin = create_admin_user

    post login_path, params: { login: admin.user_name, password: "secret" }
    get question_template_jj_quizzes_path

    assert_response :success
    headers = xlsx_first_row(response.body)
    assert_equal ["Question", "Option A", "Option B", "Option C", "Option D", "Correct Option"], headers
    assert_not_includes headers, "Marks"
    assert_not_includes headers, "Position"
    assert_not_includes headers, "Status"
  end

  private

  def create_admin_user(attributes = {})
    User.create!({
      first_name: "Exam",
      last_name: "Admin",
      user_name: "exam_admin_#{SecureRandom.hex(3)}",
      email: "exam_admin_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_type: "admin",
      status: "Active"
    }.merge(attributes))
  end

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

  def xlsx_first_row(body)
    headers = []
    Zip::File.open_buffer(StringIO.new(body)) do |zip|
      sheet = REXML::Document.new(zip.read("xl/worksheets/sheet1.xml"))
      row = REXML::XPath.first(sheet, "//*[local-name()='row']")
      headers = REXML::XPath.match(row, "*[local-name()='c']").map do |cell|
        REXML::XPath.match(cell, ".//*[local-name()='t']").map(&:text).join
      end
    end
    headers
  end
end
