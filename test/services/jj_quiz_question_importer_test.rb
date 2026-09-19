require "test_helper"
require "tempfile"

class JjQuizQuestionImporterTest < ActiveSupport::TestCase
  test "imports xlsx questions and accepts correct answer text" do
    quiz = JjQuiz.create!(title: "Import Quiz", duration_minutes: 20)
    file = build_xlsx_upload([
      ["Plant health?", "Red", "Green", "Blue", "Yellow", "Green"]
    ])

    result = JjQuizQuestionImporter.import(file: file, quiz: quiz)
    question = quiz.questions.first

    assert_equal 1, result[:imported]
    assert_empty result[:skipped]
    assert_equal "Plant health?", question.question_text
    assert_equal "B", question.correct_option
    assert_equal BigDecimal("1.0"), question.marks
    assert_equal 1, question.position
    assert_equal "active", question.status
  ensure
    file&.close!
  end

  test "assigns sequential positions for imported questions" do
    quiz = JjQuiz.create!(title: "Position Import Quiz", duration_minutes: 20)
    file = build_xlsx_upload([
      ["First question?", "A", "B", "C", "D", "A"],
      ["Second question?", "A", "B", "C", "D", "B"],
      ["Third question?", "A", "B", "C", "D", "C"]
    ])

    result = JjQuizQuestionImporter.import(file: file, quiz: quiz)

    assert_equal 3, result[:imported]
    assert_equal [1, 2, 3], quiz.questions.order(:id).pluck(:position)
  ensure
    file&.close!
  end

  test "question template only exposes question fields" do
    assert_equal ["Question", "Option A", "Option B", "Option C", "Option D", "Correct Option"], JjQuizQuestion.template_headers
    assert_not_includes JjQuizQuestion.template_headers, "Marks"
    assert_not_includes JjQuizQuestion.template_headers, "Position"
    assert_not_includes JjQuizQuestion.template_headers, "Status"
  end

  test "ignores legacy marks position and status columns during import" do
    quiz = JjQuiz.create!(title: "Legacy Import Quiz", duration_minutes: 20)
    file = build_xlsx_upload(
      [
        ["Legacy question?", "A", "B", "C", "D", "B", "9", "12", "inactive"]
      ],
      headers: JjQuizQuestion.template_headers + ["Marks", "Position", "Status"]
    )

    result = JjQuizQuestionImporter.import(file: file, quiz: quiz)
    question = quiz.questions.first

    assert_equal 1, result[:imported]
    assert_equal BigDecimal("1.0"), question.marks
    assert_equal 1, question.position
    assert_equal "active", question.status
  ensure
    file&.close!
  end

  private

  def build_xlsx_upload(rows, headers: JjQuizQuestion.template_headers)
    data = XlsxExporter.generate(
      headers: headers,
      rows: rows,
      sheet_name: "Questions"
    )
    tempfile = Tempfile.new(["jj-quiz-questions", ".xlsx"])
    tempfile.binmode
    tempfile.write(data)
    tempfile.flush
    UploadedFile.new(tempfile.path, "questions.xlsx", tempfile)
  end

  UploadedFile = Struct.new(:path, :original_filename, :tempfile) do
    def close!
      tempfile.close!
    end
  end
end
