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
    published? &&
      (starts_at.blank? || starts_at <= Time.current) &&
      (ends_at.blank? || ends_at >= Time.current) &&
      active_questions.exists?
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
