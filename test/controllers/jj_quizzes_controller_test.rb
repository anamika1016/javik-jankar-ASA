require "test_helper"
require "rexml/document"
require "stringio"
require "zip"

class JjQuizzesControllerTest < ActionDispatch::IntegrationTest
  test "index shows active window progress with admin open results and delete actions" do
    admin = create_admin_user
    running_quiz = create_quiz(title: "Running Window Exam", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    ended_quiz = create_quiz(title: "Ended Window Exam", starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    create_question(running_quiz)
    create_question(ended_quiz)

    post login_path, params: { login: admin.user_name, password: "secret" }
    get jj_quizzes_path

    assert_response :success
    assert_includes response.body, "Active Window"
    assert_includes response.body, "Exam State"
    assert_includes response.body, "Running"
    assert_includes response.body, "Ended"
    assert_includes response.body, running_quiz.start_time_label
    assert_includes response.body, ended_quiz.end_time_label
    assert_select "a", text: "Open", minimum: 2
    assert_select "a", text: "Results", minimum: 2
    assert_select "a", text: "Download Sheet", count: 0
    assert_select "a", text: "Answers", count: 0
    assert_select "button", text: "Delete", minimum: 2
  end

  test "show renders admin QR sharing actions" do
    admin = create_admin_user
    quiz = create_quiz(title: "Shareable JJ Exam", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create_question(quiz)

    post login_path, params: { login: admin.user_name, password: "secret" }
    get jj_quiz_path(quiz)

    assert_response :success
    assert_includes response.body, "Share Exam QR"
    assert_includes response.body, "Copy QR"
    assert_includes response.body, "Share Link on WhatsApp"
    assert_includes response.body, start_jj_exam_url(quiz)
    assert_includes response.body, "Start Time"
    assert_includes response.body, quiz.start_time_label
    assert_includes response.body, "End Time"
    assert_includes response.body, quiz.end_time_label
    assert_includes response.body, "Download Answer Sheet"
    assert_not_includes response.body, ">Answer Sheets<"
    assert_not_includes response.body, ">Answers<"
    assert_select "button", text: "Delete"
    assert_not_includes response.body, "JJ Exam Login"
  end

  test "show renders direct link and qr for scheduled exam without bypassing schedule" do
    admin = create_admin_user
    quiz = create_quiz(title: "Future JJ Exam", starts_at: 1.day.from_now, ends_at: 2.days.from_now)
    create_question(quiz)

    post login_path, params: { login: admin.user_name, password: "secret" }
    get jj_quiz_path(quiz)

    assert_response :success
    assert_includes response.body, "Share Exam QR"
    assert_includes response.body, "Open Exam Link"
    assert_includes response.body, "Share Link on WhatsApp"
    assert_includes response.body, "Copy QR"
    assert_includes response.body, "Copy Link"
    assert_includes response.body, "Scheduled"
    assert_includes response.body, "will start on"
    assert_not_includes response.body, "Activate Exam Now"
    assert_includes response.body, "jj-qr-svg"
    assert_includes response.body, start_jj_exam_url(quiz)
  end

  test "question format download only contains question columns" do
    admin = create_admin_user

    post login_path, params: { login: admin.user_name, password: "secret" }
    get question_template_jj_quizzes_path

    assert_response :success
    rows = xlsx_rows(response.body)
    headers = rows.first
    assert_equal ["Question", "Option A", "Option B", "Option C", "Option D", "Correct Option"], headers
    assert_not_includes headers, "Marks"
    assert_not_includes headers, "Position"
    assert_not_includes headers, "Status"
    assert_includes rows.flatten, "What is the main objective of organic farming?"
    assert_not rows.flatten.any? { |cell| cell.to_s.include?("kya") || cell.to_s.include?("Koi nahi") }
  end

  test "attempt review page and export show each selected answer" do
    admin = create_admin_user
    quiz = create_quiz(title: "Answer Sheet Exam")
    first_question = create_question(
      quiz,
      question_text: "Which practice improves soil health?",
      option_a: "Burn crop residue",
      option_b: "Use compost",
      option_c: "Skip irrigation",
      option_d: "None",
      correct_option: "B",
      position: 1
    )
    second_question = create_question(
      quiz,
      question_text: "What confirms training attendance?",
      option_a: "Photo with farmer list",
      option_b: "Blank page",
      option_c: "No record",
      option_d: "None",
      correct_option: "A",
      position: 2
    )
    vrp = create_vrp(name: "Answer Sheet JJ", user_name: "answer_sheet_jj_#{SecureRandom.hex(4)}")
    attempt = quiz.attempts.create!(vrp: vrp)
    attempt.grade!({ first_question.id.to_s => "A", second_question.id.to_s => "A" })

    post login_path, params: { login: admin.user_name, password: "secret" }
    get answers_jj_quiz_path(quiz)

    assert_response :success
    assert_includes response.body, "Attempt Review"
    assert_includes response.body, "Download Sheet"
    assert_includes response.body, "Answer Sheet JJ"
    assert_includes response.body, "Which practice improves soil health?"
    assert_includes response.body, "Burn crop residue"
    assert_includes response.body, "Use compost"
    assert_includes response.body, "Wrong"
    assert_includes response.body, "Correct"
    assert_select ".jj-option-line.selected", minimum: 2
    assert_select ".jj-option-line.selected", text: /Burn crop residue/
    assert_select "button", text: "Delete Attempt"

    get export_answers_jj_quiz_path(quiz)

    assert_response :success
    rows = xlsx_rows(response.body)
    assert_equal "Selected Option", rows.first[13]
    assert_equal "Selected Answer", rows.first[14]
    assert rows.any? { |row| row[8] == "Which practice improves soil health?" && row[13] == "A" && row[14] == "Burn crop residue" && row[19] == "Wrong" }
    assert rows.any? { |row| row[8] == "What confirms training attendance?" && row[13] == "A" && row[14] == "Photo with farmer list" && row[19] == "Correct" }
  end

  test "admin can delete an attempt so the JJ can take the exam again" do
    admin = create_admin_user
    quiz = create_quiz(title: "Retake Exam", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    question = create_question(quiz, correct_option: "B", option_a: "Wrong", option_b: "Right")
    vrp = create_vrp(name: "Retake JJ", user_name: "retake_jj_#{SecureRandom.hex(4)}")
    attempt = quiz.attempts.create!(vrp: vrp)
    attempt.grade!({ question.id.to_s => "B" })

    post login_path, params: { login: admin.user_name, password: "secret" }
    get results_jj_quiz_path(quiz)

    assert_response :success
    assert_select "a[href='#{answers_jj_quiz_path(quiz, attempt_id: attempt.id)}']", text: "Open"
    assert_select "button", text: "Delete Attempt"

    assert_difference -> { JjQuizAttempt.count }, -1 do
      delete delete_attempt_jj_quiz_path(quiz, attempt)
    end

    assert_redirected_to results_jj_quiz_path(quiz)
    assert_empty quiz.attempts.where(vrp: vrp)

    assert_difference -> { JjQuizAttempt.count }, 1 do
      post jj_exam_login_path, params: { jj_quiz_id: quiz.id, login: vrp.user_name, password: "secret" }
    end

    fresh_attempt = quiz.attempts.where(vrp: vrp).recent.first
    assert_redirected_to take_jj_exam_path(fresh_attempt.access_token)
    assert_equal "qr_issued", fresh_attempt.status
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

  def create_vrp(attributes = {})
    Vrp.create!({
      name: "Exam JJ",
      father_husband_name: "Test Father",
      gender: :male,
      date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current,
      aadhar_no: "123456789012",
      account_no: "1234567890",
      bank_name: "Test Bank",
      branch: "Test Branch",
      ifsc_code: "TEST0123456",
      address: "Test Address",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      email: "jj_#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1,
      office_detail_id: 0,
      to_office_detail_id: 0,
      vrp_type_ids: [1],
      gram_panchayat_ids: [1],
      village_ids: [1],
      is_active: true,
      is_deleted: false,
      user_name: "jj_exam_#{SecureRandom.hex(4)}",
      password: "secret"
    }.merge(attributes))
  end

  def xlsx_rows(body)
    rows = []
    Zip::File.open_buffer(StringIO.new(body)) do |zip|
      sheet = REXML::Document.new(zip.read("xl/worksheets/sheet1.xml"))
      rows = REXML::XPath.match(sheet, "//*[local-name()='row']").map do |row|
        REXML::XPath.match(row, "*[local-name()='c']").map do |cell|
          REXML::XPath.match(cell, ".//*[local-name()='t']").map(&:text).join
        end
      end
    end
    rows
  end
end
