class CreateJjExamModule < ActiveRecord::Migration[8.1]
  def change
    create_table :jj_quizzes do |t|
      t.string :title, null: false
      t.text :description
      t.integer :duration_minutes, null: false, default: 30
      t.decimal :passing_marks, precision: 8, scale: 2
      t.string :status, null: false, default: "draft"
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :allow_retake, null: false, default: false
      t.string :created_by_type
      t.bigint :created_by_id

      t.timestamps
    end

    add_index :jj_quizzes, :status
    add_index :jj_quizzes, [:created_by_type, :created_by_id]

    create_table :jj_quiz_questions do |t|
      t.references :jj_quiz, null: false, foreign_key: true
      t.text :question_text, null: false
      t.string :option_a, null: false
      t.string :option_b, null: false
      t.string :option_c
      t.string :option_d
      t.string :correct_option, null: false
      t.decimal :marks, precision: 8, scale: 2, null: false, default: 1
      t.integer :position, null: false, default: 1
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :jj_quiz_questions, [:jj_quiz_id, :position]
    add_index :jj_quiz_questions, :status

    create_table :jj_quiz_attempts do |t|
      t.references :jj_quiz, null: false, foreign_key: true
      t.references :vrp, null: false, foreign_key: true
      t.string :access_token, null: false
      t.string :status, null: false, default: "qr_issued"
      t.datetime :started_at
      t.datetime :expires_at
      t.datetime :submitted_at
      t.decimal :score, precision: 10, scale: 2, null: false, default: 0
      t.decimal :total_marks, precision: 10, scale: 2, null: false, default: 0
      t.decimal :percentage, precision: 7, scale: 2, null: false, default: 0
      t.boolean :passed, null: false, default: false
      t.string :login_ip
      t.string :user_agent

      t.timestamps
    end

    add_index :jj_quiz_attempts, :access_token, unique: true
    add_index :jj_quiz_attempts, [:jj_quiz_id, :vrp_id]
    add_index :jj_quiz_attempts, :status

    create_table :jj_quiz_answers do |t|
      t.references :jj_quiz_attempt, null: false, foreign_key: true
      t.references :jj_quiz_question, null: false, foreign_key: true
      t.string :selected_option
      t.string :correct_option, null: false
      t.boolean :correct, null: false, default: false
      t.decimal :marks_awarded, precision: 8, scale: 2, null: false, default: 0
      t.jsonb :question_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :jj_quiz_answers, [:jj_quiz_attempt_id, :jj_quiz_question_id], unique: true, name: "idx_jj_answers_on_attempt_and_question"
  end
end
