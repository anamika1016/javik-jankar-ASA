class JjExamController < ApplicationController
  skip_before_action :require_app_login
  layout "exam"

  before_action :set_attempt, only: %i[qr take submit result]

  def login
    @quizzes = active_quizzes
    @fixed_quiz = selected_active_quiz
    @quizzes = [@fixed_quiz] if @fixed_quiz
  end

  def create_session
    @quizzes = active_quizzes
    @quiz = selected_active_quiz
    @fixed_quiz = @quiz
    unless @quiz
      flash.now[:alert] = "Please select an active exam."
      render :login, status: :unprocessable_entity
      return
    end

    vrp = AppUserAuthenticator.authenticate_vrp(login: params[:login], password: params[:password])
    unless vrp
      flash.now[:alert] = "Invalid Jeevika Jankar user ID or password."
      render :login, status: :unprocessable_entity
      return
    end

    if (submitted_attempt = completed_attempt_for(@quiz, vrp))
      redirect_to jj_exam_result_path(submitted_attempt.access_token), notice: "This exam is already submitted for this Jeevika Jankar."
      return
    end

    attempt = reusable_attempt_for(@quiz, vrp) || @quiz.attempts.create!(
      vrp: vrp,
      login_ip: request.remote_ip,
      user_agent: request.user_agent.to_s.first(255)
    )
    redirect_to take_jj_exam_path(attempt.access_token)
  end

  def qr
    @take_url = take_jj_exam_url(@attempt.access_token)
    @qr_svg = SimpleQrCode.svg(@take_url, size: 280)
  rescue ArgumentError
    @qr_svg = nil
  end

  def take
    redirect_to jj_exam_result_path(@attempt.access_token) and return if @attempt.submitted?
    unless @attempt.quiz.active_for_exam?
      redirect_to jj_exam_login_path, alert: "This exam is not active right now."
      return
    end

    @attempt.start!
    if @attempt.expired_now?
      @attempt.grade!(answers_param, final_status: "expired")
      redirect_to jj_exam_result_path(@attempt.access_token), alert: "Time is over. Your saved answers were submitted automatically."
      return
    end

    @questions = @attempt.quiz.active_questions
    @remaining_seconds = @attempt.remaining_seconds
  end

  def submit
    redirect_to jj_exam_result_path(@attempt.access_token) and return if @attempt.submitted?

    @attempt.start!
    if @attempt.expired_now?
      @attempt.grade!(answers_param, final_status: "expired")
      redirect_to jj_exam_result_path(@attempt.access_token), alert: "Time is over. Your exam was submitted automatically."
      return
    end

    @attempt.grade!(answers_param)
    redirect_to jj_exam_result_path(@attempt.access_token), notice: "Exam submitted successfully."
  end

  def result
    @answers = @attempt.answers.includes(:question).order(:id)
  end

  private

  def active_quizzes
    JjQuiz.published.recent.select(&:active_for_exam?)
  end

  def selected_active_quiz
    quiz_id = params[:quiz_token].presence || params[:quiz_id].presence || params[:jj_quiz_id].presence
    return if quiz_id.blank?

    active_quizzes.find { |quiz| quiz.id.to_s == quiz_id.to_s }
  end

  def set_attempt
    @attempt = JjQuizAttempt.includes(:quiz, :vrp).find_by!(access_token: params[:token])
  end

  def completed_attempt_for(quiz, vrp)
    quiz.attempts.where(vrp: vrp, status: %w[submitted expired]).recent.first
  end

  def reusable_attempt_for(quiz, vrp)
    quiz.attempts.where(vrp: vrp, status: %w[qr_issued in_progress]).recent.first
  end

  def answers_param
    params.fetch(:answers, {}).to_unsafe_h
  end
end
