class JjQuizQuestionsController < ApplicationController
  before_action :require_admin_user!
  before_action :set_quiz
  before_action :set_question, only: %i[edit update destroy]

  def new
    @question = @quiz.questions.new(position: @quiz.questions.maximum(:position).to_i + 1, marks: 1)
  end

  def create
    @question = @quiz.questions.new(question_params)
    if @question.save
      redirect_to jj_quiz_path(@quiz), notice: "Question added successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @question.update(question_params)
      redirect_to jj_quiz_path(@quiz), notice: "Question updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @question.destroy
      redirect_to jj_quiz_path(@quiz), notice: "Question deleted successfully."
    else
      redirect_to jj_quiz_path(@quiz), alert: @question.errors.full_messages.to_sentence
    end
  end

  private

  def set_quiz
    @quiz = JjQuiz.find(params[:jj_quiz_id])
  end

  def set_question
    @question = @quiz.questions.find(params[:id])
  end

  def question_params
    params.require(:jj_quiz_question).permit(:question_text, :option_a, :option_b, :option_c, :option_d, :correct_option, :marks, :position, :status)
  end

  def require_admin_user!
    return if current_app_user&.dig("user_type").to_s.casecmp("admin").zero?

    redirect_to dashboard_path, alert: "Only admin can manage JJ exam questions."
  end
end
