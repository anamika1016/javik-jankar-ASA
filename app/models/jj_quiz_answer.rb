class JjQuizAnswer < ApplicationRecord
  belongs_to :attempt, class_name: "JjQuizAttempt", foreign_key: :jj_quiz_attempt_id
  belongs_to :question, class_name: "JjQuizQuestion", foreign_key: :jj_quiz_question_id
end
