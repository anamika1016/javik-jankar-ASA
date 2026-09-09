class TrainingEditApprovalsController < ApplicationController
  def index
    @revisions = ModuleRecord.where(module_slug: TrainingEditApproval::SLUG).order(id: :desc).select do |revision|
      TrainingEditApproval.assign_configured_channel!(revision)
      TrainingEditApproval.visible?(revision, current_app_user)
    end
  end

  def show
    @revision = ModuleRecord.where(module_slug: TrainingEditApproval::SLUG).find(params[:id])
    TrainingEditApproval.assign_configured_channel!(@revision)
    head :forbidden unless TrainingEditApproval.visible?(@revision, current_app_user)
  end

  def update
    revision = ModuleRecord.where(module_slug: TrainingEditApproval::SLUG).find(params[:id])
    remarks = params[:remarks].presence || "Updated from Training Form List."
    TrainingEditApproval.decide!(revision: revision, actor: current_app_user, decision: params[:decision], remarks: remarks)
    redirect_to approval_return_path(revision), notice: "Training edit request updated."
  rescue TrainingEditApproval::InvalidTransition => error
    redirect_to approval_return_path(revision), alert: error.message
  end

  private

  def approval_return_path(revision)
    return module_path("training-form-list") if params[:return_to] == "training_form_list"

    if params[:return_to] == "training_form_edit"
      record_id = revision.data["record_id"]
      return edit_module_record_path("training-form", record_id) if record_id.present?
    end

    training_edit_approval_path(params[:id])
  end
end
