class JjQuizAttempt < ApplicationRecord
  STATUSES = %w[qr_issued in_progress submitted expired].freeze

  belongs_to :quiz, class_name: "JjQuiz", foreign_key: :jj_quiz_id
  belongs_to :vrp
  has_many :answers, class_name: "JjQuizAnswer", dependent: :destroy

  before_validation :ensure_access_token
  before_validation :default_status

  validates :access_token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def submitted?
    status == "submitted" || status == "expired"
  end

  def start!
    return if submitted?

    now = Time.current
    duration_expires_at = now + quiz.duration_minutes.minutes
    allowed_expires_at = [expires_at, duration_expires_at, quiz.ends_at].compact.min
    update!(
      started_at: started_at || now,
      expires_at: allowed_expires_at,
      status: "in_progress"
    )
  end

  def expired_now?
    expiry_time.present? && Time.current > expiry_time
  end

  def remaining_seconds
    return 0 if expiry_time.blank?

    [expiry_time.to_i - Time.current.to_i, 0].max
  end

  def correct_answers_count
    answer_records.count(&:correct?)
  end

  def wrong_answers_count
    answer_records.count { |answer| answer.selected_option.present? && !answer.correct? }
  end

  def skipped_answers_count
    answer_records.count { |answer| answer.selected_option.blank? }
  end

  def total_questions_count
    answer_records.size.positive? ? answer_records.size : quiz.active_questions.count
  end

  def time_taken_seconds
    return if started_at.blank? || submitted_at.blank?

    [(submitted_at - started_at).round, 0].max
  end

  def time_taken_label
    seconds = time_taken_seconds
    return "-" if seconds.blank?

    minutes = seconds / 60
    remaining = seconds % 60
    "#{minutes}m #{remaining.to_s.rjust(2, "0")}s"
  end

  def grade!(selected_by_question_id, final_status: "submitted")
    start! unless started_at

    transaction do
      answers.destroy_all
      total = 0.to_d
      score_value = 0.to_d

      quiz.active_questions.each do |question|
        selected = selected_by_question_id[question.id.to_s].to_s.upcase.first
        selected = nil unless JjQuizQuestion::OPTIONS.include?(selected)
        correct = selected.present? && selected == question.correct_option
        marks_awarded = correct ? question.marks : 0
        total += question.marks
        score_value += marks_awarded

        answers.create!(
          question: question,
          selected_option: selected,
          correct_option: question.correct_option,
          correct: correct,
          marks_awarded: marks_awarded,
          question_snapshot: question.snapshot
        )
      end

      update!(
        status: final_status,
        submitted_at: Time.current,
        score: score_value,
        total_marks: total,
        percentage: total.positive? ? ((score_value / total) * 100).round(2) : 0,
        passed: score_value >= quiz.passing_score
      )
    end
  end

  def expire!
    transaction do
      answers.destroy_all
      total = quiz.active_questions.sum(:marks)
      update!(
        status: "expired",
        submitted_at: Time.current,
        score: 0,
        total_marks: total,
        percentage: 0,
        passed: false
      )
    end
  end

  private

  def ensure_access_token
    self.access_token ||= SecureRandom.urlsafe_base64(24)
  end

  def default_status
    self.status = "qr_issued" if status.blank?
  end

  def answer_records
    answers.loaded? ? answers.target : (@answer_records ||= answers.to_a)
  end

  def expiry_time
    [expires_at, quiz.ends_at].compact.min
  end
end
