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

  test "scheduled exam link opens but blocks login before start time" do
    quiz = create_quiz(title: "Scheduled JJ Exam", starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
    create_question(quiz)
    vrp = create_vrp

    get start_jj_exam_path(quiz)

    assert_response :success
    assert_includes response.body, "Scheduled JJ Exam"
    assert_includes response.body, "Scheduled"
    assert_includes response.body, "se start hoga."
    assert_select "input[name=?]", "login", count: 0

    assert_no_difference -> { JjQuizAttempt.count } do
      post jj_exam_login_path, params: { jj_quiz_id: quiz.id, login: vrp.user_name, password: "secret" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "se start hoga."
  end

  test "ended exam link opens but blocks login after end time" do
    quiz = create_quiz(title: "Ended JJ Exam", starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    create_question(quiz)
    vrp = create_vrp

    get start_jj_exam_path(quiz)

    assert_response :success
    assert_includes response.body, "Ended JJ Exam"
    assert_includes response.body, "Ended"
    assert_includes response.body, "end ho chuka hai."
    assert_select "input[name=?]", "login", count: 0

    assert_no_difference -> { JjQuizAttempt.count } do
      post jj_exam_login_path, params: { jj_quiz_id: quiz.id, login: vrp.user_name, password: "secret" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "end ho chuka hai."
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
      mobile_no: "9876543210",
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
end
