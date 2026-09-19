require "test_helper"

class JjQuizAttemptTest < ActiveSupport::TestCase
  test "grades selected answers and treats unanswered questions as incorrect" do
    quiz = create_quiz(passing_marks: 1)
    first = create_question(quiz, question_text: "2+2?", option_a: "3", option_b: "4", correct_option: "B", position: 1)
    second = create_question(quiz, question_text: "Soil health?", option_a: "Low", option_b: "High", correct_option: "B", position: 2)
    third = create_question(quiz, question_text: "Skipped?", option_a: "No", option_b: "Yes", correct_option: "A", position: 3)
    attempt = quiz.attempts.create!(vrp: create_vrp)

    attempt.grade!({ first.id.to_s => "B", second.id.to_s => "A" })

    assert_equal "submitted", attempt.reload.status
    assert_equal BigDecimal("1.0"), attempt.score
    assert_equal BigDecimal("3.0"), attempt.total_marks
    assert_equal BigDecimal("33.33"), attempt.percentage
    assert attempt.passed?
    assert_equal 3, attempt.answers.count
    assert_equal 1, attempt.correct_answers_count
    assert_equal 1, attempt.wrong_answers_count
    assert_equal 1, attempt.skipped_answers_count
    assert_equal 3, attempt.total_questions_count
    assert_nil attempt.answers.find_by(question: third).selected_option
    assert_match(/\A\d+m \d{2}s\z/, attempt.time_taken_label)
  end

  test "expired auto-submit can still grade answers posted by the timer" do
    quiz = create_quiz(passing_marks: 1)
    question = create_question(quiz, question_text: "Correct option?", option_a: "No", option_b: "Yes", correct_option: "B")
    attempt = quiz.attempts.create!(vrp: create_vrp)

    attempt.grade!({ question.id.to_s => "B" }, final_status: "expired")

    assert_equal "expired", attempt.reload.status
    assert_equal BigDecimal("1.0"), attempt.score
    assert attempt.passed?
  end

  test "attempt expiry respects quiz end time before duration" do
    quiz = create_quiz(duration_minutes: 60, ends_at: 10.minutes.from_now)
    create_question(quiz)
    attempt = quiz.attempts.create!(vrp: create_vrp)

    attempt.start!

    assert_in_delta quiz.ends_at.to_f, attempt.reload.expires_at.to_f, 1
    assert_in_delta 10.minutes.to_i, attempt.remaining_seconds, 2
  end

  private

  def create_quiz(attributes = {})
    JjQuiz.create!({
      title: "JJ Quiz #{SecureRandom.hex(4)}",
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
      name: "Test JJ",
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
