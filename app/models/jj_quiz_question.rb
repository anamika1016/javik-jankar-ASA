class JjQuizQuestion < ApplicationRecord
  OPTIONS = %w[A B C D].freeze
  HEADER_LABELS = {
    question_text: "Question",
    option_a: "Option A",
    option_b: "Option B",
    option_c: "Option C",
    option_d: "Option D",
    correct_option: "Correct Option",
    marks: "Marks",
    position: "Position",
    status: "Status"
  }.freeze
  QUESTION_TEMPLATE_COLUMNS = %i[question_text option_a option_b option_c option_d correct_option].freeze

  belongs_to :quiz, class_name: "JjQuiz", foreign_key: :jj_quiz_id, inverse_of: :questions
  has_many :answers, class_name: "JjQuizAnswer", dependent: :restrict_with_error

  before_validation :normalize_correct_option
  before_validation :default_marks
  before_validation :default_position
  before_validation :default_status

  validates :question_text, :option_a, :option_b, :correct_option, presence: true
  validates :correct_option, inclusion: { in: OPTIONS }
  validates :marks, numericality: { greater_than: 0 }
  validates :position, numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(:position, :id) }

  def self.template_headers
    QUESTION_TEMPLATE_COLUMNS.map { |column| HEADER_LABELS[column] }
  end

  def self.template_rows
    [
      ["What is the main objective of organic farming?", "Increasing chemical use", "Improving soil health and safe production", "Only packaging", "None", "B"],
      ["What can be used as proof of training attendance?", "Photo", "Farmer list", "Both A and B", "None", "C"]
    ]
  end

  def option_label(option)
    public_send("option_#{option.to_s.downcase}").presence
  end

  def snapshot
    {
      question_text: question_text,
      option_a: option_a,
      option_b: option_b,
      option_c: option_c,
      option_d: option_d,
      correct_option: correct_option,
      marks: marks.to_s,
      position: position
    }
  end

  private

  def normalize_correct_option
    self.correct_option = correct_option.to_s.strip.upcase.first
  end

  def default_marks
    self.marks ||= 1
  end

  def default_position
    self.position ||= (quiz&.questions&.maximum(:position).to_i + 1)
  end

  def default_status
    self.status = "active" if status.blank?
  end
end
