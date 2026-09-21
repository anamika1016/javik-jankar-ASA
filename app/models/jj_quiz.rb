class JjQuiz < ApplicationRecord
  STATUSES = %w[draft published archived].freeze

  has_many :questions, class_name: "JjQuizQuestion", dependent: :destroy
  has_many :attempts, class_name: "JjQuizAttempt", dependent: :restrict_with_error

  validates :title, presence: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 240 }
  validates :status, inclusion: { in: STATUSES }
  validates :passing_marks, numericality: { greater_than_or_equal_to: 0, allow_blank: true }
  validate :ends_after_starts

  scope :recent, -> { order(updated_at: :desc, id: :desc) }
  scope :published, -> { where(status: "published") }

  def active_for_exam?
    shareable_for_exam? &&
      (starts_at.blank? || starts_at <= Time.current) &&
      (ends_at.blank? || ends_at >= Time.current)
  end

  def shareable_for_exam?
    published? &&
      active_questions.exists?
  end

  def inactive_for_exam_reason
    return "This exam is draft or archived. Publish it before sharing." unless published?
    return "Add at least one active question before sharing this exam." unless active_questions.exists?
    return "Exam will start on #{starts_at.strftime('%d/%m/%Y at %I:%M %p')}." if starts_at.present? && starts_at > Time.current
    return "Exam ended on #{ends_at.strftime('%d/%m/%Y at %I:%M %p')}." if ends_at.present? && ends_at < Time.current

    nil
  end

  def exam_window_label
    return "Not Ready" unless shareable_for_exam?
    return "Scheduled" if starts_at.present? && starts_at > Time.current
    return "Ended" if ends_at.present? && ends_at < Time.current

    "Active"
  end

  def published?
    status == "published"
  end

  def archived?
    status == "archived"
  end

  def active_questions
    questions.active.ordered
  end

  def total_marks
    active_questions.sum(:marks)
  end

  def display_title
    normalized_title = title.to_s.strip.sub(/\ADemo\s+/i, "").gsub(/\bJJ\b/i, "Jeevika Jankar").squish
    normalized_title.presence || "Jeevika Jankar Exam"
  end

  def passing_score
    passing_marks.presence || total_marks
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after start date")
  end
end
