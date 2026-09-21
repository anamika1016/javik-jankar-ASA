class JjQuizzesController < ApplicationController
  before_action :require_admin_user!
  before_action :set_quiz, only: %i[show edit update destroy publish archive import_questions results export_results answers export_answers destroy_attempt]
  helper_method :attempt_answer_rows, :answer_option_text, :answer_result_label, :answer_result_class, :attempt_vrp_label

  def index
    @quizzes = JjQuiz.recent.includes(:questions, :attempts)
  end

  def show
    @question = @quiz.questions.new(position: @quiz.questions.maximum(:position).to_i + 1, marks: 1)
    @questions = @quiz.questions.ordered
    @attempts = @quiz.attempts.includes(:vrp, :answers).recent.limit(10)
    @exam_start_url = start_jj_exam_url(@quiz)
    @exam_start_qr_svg = SimpleQrCode.svg(@exam_start_url, size: 220) if @quiz.shareable_for_exam?
    @exam_share_text = "Jeevika Jankar Exam: #{@quiz.title}\nScan this QR/link, login with JJ User ID and password, then start the exam:\n#{@exam_start_url}"
    @whatsapp_share_url = "https://wa.me/?text=#{ERB::Util.url_encode(@exam_share_text)}"
  end

  def new
    @quiz = JjQuiz.new(duration_minutes: 30, status: "draft")
  end

  def create
    @quiz = JjQuiz.new(quiz_params)
    assign_creator(@quiz)

    if @quiz.save
      redirect_to jj_quiz_path(@quiz), notice: "JJ exam created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @quiz.update(quiz_params)
      redirect_to jj_quiz_path(@quiz), notice: "JJ exam updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @quiz.destroy
      redirect_to jj_quizzes_path, notice: "JJ exam deleted successfully."
    else
      redirect_to jj_quiz_path(@quiz), alert: @quiz.errors.full_messages.to_sentence
    end
  end

  def publish
    if @quiz.active_questions.exists?
      @quiz.update!(status: "published")
      redirect_to jj_quiz_path(@quiz), notice: "JJ exam published. Candidate QR is ready for admin sharing."
    else
      redirect_to jj_quiz_path(@quiz), alert: "Add at least one active question before publishing."
    end
  end

  def archive
    @quiz.update!(status: "archived")
    redirect_to jj_quiz_path(@quiz), notice: "JJ exam archived."
  end

  def question_template
    send_data XlsxExporter.generate(
      headers: JjQuizQuestion.template_headers,
      rows: JjQuizQuestion.template_rows,
      sheet_name: "Questions"
    ),
      filename: "jj_exam_question_format.xlsx",
      type: XlsxExporter::MIME_TYPE,
      disposition: "attachment"
  end

  def import_questions
    result = JjQuizQuestionImporter.import(file: params[:file], quiz: @quiz)
    notice = "#{result[:imported]} questions imported successfully."
    alert = result[:skipped].first(5).join(" | ").presence
    redirect_to jj_quiz_path(@quiz), notice: notice, alert: alert
  rescue ArgumentError => error
    redirect_to jj_quiz_path(@quiz), alert: error.message
  end

  def results
    @attempts = @quiz.attempts.includes(:vrp, :answers).recent
  end

  def export_results
    attempts = @quiz.attempts.includes(:vrp, :answers).recent
    send_xlsx(
      headers: result_headers,
      rows: attempts.map { |attempt| result_row(attempt) },
      filename: "jj-exam-results-#{@quiz.id}-#{Date.current}.xlsx",
      sheet_name: "JJ Exam Results"
    )
  end

  def answers
    @attempts = answer_attempt_scope
  end

  def export_answers
    attempts = answer_attempt_scope
    send_xlsx(
      headers: answer_sheet_headers,
      rows: attempts.flat_map { |attempt| answer_sheet_rows(attempt) },
      filename: "jj-exam-answer-sheets-#{@quiz.id}-#{Date.current}.xlsx",
      sheet_name: "JJ Answer Sheets"
    )
  end

  def destroy_attempt
    attempt = @quiz.attempts.includes(:vrp).find(params[:attempt_id])
    label = attempt_vrp_label(attempt)
    attempt.destroy!
    redirect_back fallback_location: results_jj_quiz_path(@quiz), notice: "#{label} attempt deleted successfully. Candidate can take the exam again while the exam window is active."
  rescue ActiveRecord::RecordNotDestroyed => error
    redirect_back fallback_location: results_jj_quiz_path(@quiz), alert: error.record.errors.full_messages.to_sentence.presence || "Attempt could not be deleted."
  end

  private

  def set_quiz
    @quiz = JjQuiz.find(params[:id])
  end

  def quiz_params
    params.require(:jj_quiz).permit(:title, :description, :duration_minutes, :passing_marks, :status, :starts_at, :ends_at).merge(allow_retake: false)
  end

  def assign_creator(quiz)
    quiz.created_by_type = current_app_user&.dig("record_type")
    quiz.created_by_id = current_app_user&.dig("id")
  end

  def require_admin_user!
    return if current_app_user&.dig("user_type").to_s.casecmp("admin").zero?

    redirect_to dashboard_path, alert: "Only admin can manage JJ exams."
  end

  def result_headers
    ["Attempt ID", "Exam", "JJ Record ID", "JJ User ID", "JJ Name", "Mobile", "Status", "Score", "Total Marks", "Percentage", "Correct", "Wrong", "Skipped", "Questions", "Passed", "Started At", "Submitted At", "Time Taken"]
  end

  def result_row(attempt)
    [
      attempt.id,
      @quiz.title,
      attempt.vrp_id,
      attempt.vrp&.user_name,
      attempt.vrp&.name,
      attempt.vrp&.mobile_no,
      attempt.status,
      attempt.score,
      attempt.total_marks,
      attempt.percentage,
      attempt.correct_answers_count,
      attempt.wrong_answers_count,
      attempt.skipped_answers_count,
      attempt.total_questions_count,
      attempt.passed? ? "Yes" : "No",
      attempt.started_at,
      attempt.submitted_at,
      attempt.time_taken_label
    ]
  end

  def answer_attempt_scope
    scope = @quiz.attempts.includes(:vrp, answers: :question).recent
    scope = scope.where(id: params[:attempt_id]) if params[:attempt_id].present?
    scope
  end

  def attempt_answer_rows(attempt)
    attempt.answers.sort_by { |answer| [answer_position(answer), answer.id] }
  end

  def answer_position(answer)
    snapshot = answer.question_snapshot.to_h
    (snapshot["position"].presence || answer.question&.position || answer.id).to_i
  end

  def answer_question_text(answer)
    answer.question_snapshot.to_h["question_text"].presence || answer.question&.question_text.to_s
  end

  def answer_option_text(answer, option)
    option = option.to_s.upcase
    return "" unless JjQuizQuestion::OPTIONS.include?(option)

    answer.question_snapshot.to_h["option_#{option.downcase}"].presence || answer.question&.option_label(option).to_s
  end

  def answer_result_label(answer)
    return "Skipped" if answer.selected_option.blank?

    answer.correct? ? "Correct" : "Wrong"
  end

  def answer_result_class(answer)
    return "scheduled" if answer.selected_option.blank?

    answer.correct? ? "active" : "inactive"
  end

  def attempt_vrp_label(attempt)
    [attempt.vrp&.user_name, attempt.vrp&.name].compact_blank.join(" - ").presence || "Jeevika Jankar ##{attempt.vrp_id}"
  end

  def answer_sheet_headers
    [
      "Attempt ID",
      "Exam",
      "JJ Record ID",
      "JJ User ID",
      "JJ Name",
      "Mobile",
      "Attempt Status",
      "Question No",
      "Question",
      "Option A",
      "Option B",
      "Option C",
      "Option D",
      "Selected Option",
      "Selected Answer",
      "Correct Option",
      "Correct Answer",
      "Marks Awarded",
      "Question Marks",
      "Answer Result",
      "Started At",
      "Submitted At"
    ]
  end

  def answer_sheet_rows(attempt)
    rows = attempt_answer_rows(attempt).map.with_index(1) do |answer, serial|
      [
        attempt.id,
        @quiz.title,
        attempt.vrp_id,
        attempt.vrp&.user_name,
        attempt.vrp&.name,
        attempt.vrp&.mobile_no,
        attempt.status,
        serial,
        answer_question_text(answer),
        answer_option_text(answer, "A"),
        answer_option_text(answer, "B"),
        answer_option_text(answer, "C"),
        answer_option_text(answer, "D"),
        answer.selected_option.presence || "-",
        answer_option_text(answer, answer.selected_option),
        answer.correct_option,
        answer_option_text(answer, answer.correct_option),
        answer.marks_awarded,
        answer.question_snapshot.to_h["marks"].presence || answer.question&.marks,
        answer_result_label(answer),
        attempt.started_at,
        attempt.submitted_at
      ]
    end

    return rows if rows.any?

    [[
      attempt.id,
      @quiz.title,
      attempt.vrp_id,
      attempt.vrp&.user_name,
      attempt.vrp&.name,
      attempt.vrp&.mobile_no,
      attempt.status,
      nil,
      "No answers captured",
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      attempt.started_at,
      attempt.submitted_at
    ]]
  end
end
