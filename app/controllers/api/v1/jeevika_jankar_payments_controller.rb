# frozen_string_literal: true

module Api
  module V1
    class JeevikaJankarPaymentsController < BaseController
      BILL_SLUG = "jeevika-jankar-bill-process".freeze

      def bills
        records = bill_records.select { |record| calculator.send(:jeevika_jankar_bill_record_visible?, record) }
        all_rows = records.map { |record| bill_payload_for(record) }
        rows = filter_month(all_rows)

        render json: {
          success: true,
          message: "Jeevika Jankar bill list fetched successfully.",
          months: month_options(all_rows),
          bills: rows,
          count: rows.size
        }, status: :ok
      end

      def bill
        record = visible_bill
        return bill_not_found unless record

        render json: {
          success: true,
          message: "Jeevika Jankar bill details fetched successfully.",
          bill: bill_detail_payload(record)
        }, status: :ok
      end

      def send_bill_for_approval
        record = visible_bill
        return bill_not_found unless record

        step = approval_steps(record).first
        return approval_error("Please create Jeevika Jankar Bill approval channel first.") unless step

        sequence = approval_sequence(step)
        save_bill_action!(record, "Sent for Approval", step) do
          update_bill_status!(record, "Pending at #{step.data["approver_approved_by"]}", sequence)
        end
        render_bill_action(record, "Jeevika Jankar bill sent for approval.")
      end

      def approve_bill
        process_bill_approval("Approved")
      end

      def reject_bill
        process_bill_approval("Rejected")
      end

      def return_bill
        process_bill_approval("Returned")
      end

      def payments
        return payment_access_denied unless payment_list_user?

        months = calculator.send(:jeevika_bill_payment_month_options, bill_records)
        month = selected_month.presence || months.first
        records = bill_records.select do |record|
          calculator.send(:jeevika_bill_final_approved?, record) &&
            (month.blank? || same_text?(record.data["bill_month"], month))
        end
        rows = records.map { |record| payment_payload_for(record) }

        render json: {
          success: true,
          message: "Jeevika Jankar payment list fetched successfully.",
          months: months,
          selected_month: month,
          export_url: payment_export_url(month),
          payments: rows,
          count: rows.size
        }, status: :ok
      end

      def export_payments
        return payment_access_denied unless payment_list_user?

        month = selected_month
        records = bill_records.select do |record|
          calculator.send(:jeevika_bill_final_approved?, record) &&
            (month.blank? || same_text?(record.data["bill_month"], month))
        end
        rows = records.map { |record| payment_payload_for(record) }
        headers = ["Bill ID", "Jeevika Jankar", "Financial Year", "Bill Month", "Activity Groups", "Activity Names", "Target", "Achievement", "Amount", "Status"]
        data_rows = rows.map do |row|
          [row[:bill_id], row[:name], row[:financial_year], row[:bill_month], row[:activity_groups], row[:activity_names], row[:target], row[:achievement], row[:amount], row[:status]]
        end
        file = XlsxExporter.generate(headers: headers, rows: data_rows, sheet_name: "Payment List")

        send_data file,
          filename: "jeevika-jankar-payments-#{month.presence || 'all'}-#{Date.current}.xlsx",
          type: XlsxExporter::MIME_TYPE,
          disposition: "attachment"
      end

      def download_bill
        record = visible_bill
        return bill_not_found unless record

        send_data bill_download_html(bill_detail_payload(record)),
          filename: "jeevika-jankar-bill-#{record.id}.html",
          type: "text/html; charset=utf-8",
          disposition: "attachment"
      end

      def payment_details
        return payment_access_denied unless payment_list_user?

        rows = calculator.send(:jeevika_payment_selectable_rows, bill_records)
        approval_dates = calculator.send(:jeevika_payment_bill_date_options, bill_records)
        rows = rows.select { |row| row[:approval_date].to_s == params[:approval_date].to_s } if params[:approval_date].present?

        render json: {
          success: true,
          message: "Jeevika Jankar unpaid payment details fetched successfully.",
          approval_dates: approval_dates,
          selected_approval_date: params[:approval_date],
          transaction_types: ModulesController::JEEVIKA_PAYMENT_TRANSACTION_TYPES,
          payment_amount_per_bill: ModulesController::JEEVIKA_JANKAR_BILL_FIXED_TOTAL,
          selectable_bills: rows,
          count: rows.size
        }, status: :ok
      end

      def completed_payments
        return payment_access_denied unless payment_list_user?

        all_rows = calculator.send(:jeevika_completed_payment_rows).map { |row| completed_payment_payload(row) }
        months = calculator.send(:jeevika_completed_payment_month_options, all_rows)
        month = selected_month.presence || months.first
        rows = all_rows
        rows = rows.select { |row| same_text?(row[:bill_month], month) } if month.present?
        dates = calculator.send(:jeevika_completed_payment_date_options, all_rows, month)
        rows = rows.select { |row| row[:approval_date].to_s == params[:approval_date].to_s } if params[:approval_date].present?

        render json: {
          success: true,
          message: "Jeevika Jankar completed payment list fetched successfully.",
          months: months,
          approval_dates: dates,
          selected_month: month,
          selected_approval_date: params[:approval_date],
          completed_payments: rows,
          count: rows.size
        }, status: :ok
      end

      private

      def calculator
        @calculator ||= ModulesController.new.tap do |controller|
          controller.instance_variable_set(:@current_app_user, current_api_user_payload)
        end
      end

      def visible_bill
        record = ModuleRecord.find_by(id: params[:id], module_slug: BILL_SLUG)
        return unless record && calculator.send(:jeevika_jankar_bill_record_visible?, record)

        record
      end

      def bill_not_found
        render json: { success: false, message: "Jeevika Jankar bill not found or not accessible." }, status: :not_found
      end

      def approval_error(message, status = :unprocessable_entity)
        render json: { success: false, message: message }, status: status
      end

      def process_bill_approval(action)
        record = visible_bill
        return bill_not_found unless record

        step = calculator.send(:jeevika_bill_current_approval_step, record)
        return approval_error("Approval channel not found.") unless step
        return approval_error("This bill is not pending for your approval.", :forbidden) unless calculator.send(:jeevika_bill_current_approver?, record)
        return approval_error("Please enter remarks.") if params[:remarks].to_s.strip.blank?

        save_bill_action!(record, action, step) do
          sequence = approval_sequence(step)
          if %w[Rejected Returned].include?(action)
            update_bill_status!(record, action, sequence)
          else
            next_step = approval_steps(record).find { |candidate| approval_sequence(candidate) > sequence }
            if next_step
              update_bill_status!(record, "Pending at #{next_step.data["approver_approved_by"]}", approval_sequence(next_step))
            else
              update_bill_status!(record, "Final Approved", sequence)
            end
          end
        end

        render_bill_action(record, "Bill #{action.downcase} successfully.")
      end

      def save_bill_action!(record, action, step)
        ModuleRecord.transaction do
          create_bill_history!(record, action, step)
          yield
        end
        reset_calculator_caches!
      end

      def create_bill_history!(record, action, step)
        ModuleRecord.create!(
          module_slug: "jeevika-jankar-bill-approval-history",
          data: {
            "bill_id" => record.id.to_s,
            "action" => action,
            "approval_level" => step.data["approval_level"],
            "approver" => step.data["approver_approved_by"],
            "remarks" => params[:remarks].to_s.strip,
            "action_by" => current_api_user_payload["name"].presence || current_api_user_payload["username"].to_s,
            "action_at" => Time.current.iso8601
          }
        )
      end

      def update_bill_status!(record, status, sequence)
        record.update!(data: record.data.merge("status" => status, "approval_current_sequence" => sequence.to_s))
      end

      def render_bill_action(record, message)
        record.reload
        render json: { success: true, message: message, bill: bill_detail_payload(record) }, status: :ok
      end

      def approval_steps(record)
        calculator.send(:jeevika_bill_approval_steps, record)
      end

      def approval_sequence(step)
        calculator.send(:approval_sequence_from_level, step.data["approval_level"])
      end

      def reset_calculator_caches!
        @calculator = nil
      end

      def bill_detail_payload(record)
        data = record.data
        summary = calculator.send(:jeevika_bill_summary, record)
        items = calculator.send(:jeevika_bill_detail_rows, record)
        status = calculator.send(:jeevika_bill_status_label, record)
        current_step = calculator.send(:jeevika_bill_current_approval_step, record)
        history = calculator.send(:jeevika_bill_approval_history, record)
        current_approver = calculator.send(:jeevika_bill_current_approver?, record)
        vrp_label = data["select_vrp_name"].presence || calculator.send(:jeevika_jankar_vrp_label, data["select_vrp"])

        {
          id: record.id,
          summary: {
            to: summary[:to].presence || "-",
            fco: summary[:fco].presence || "-",
            bill_id: record.id,
            vrp_id: data["select_vrp"],
            vrp_name: calculator.send(:jeevika_jankar_display_name, vrp_label).presence || "-",
            financial_year: data["financial_year"].presence || "-",
            bill_month: data["bill_month"].presence || "-",
            projects: summary[:projects].presence || "-",
            activity_groups: summary[:activity_groups].presence || "-",
            total_amount: summary[:total_amount],
            remarks: data["remarks"].presence || "-",
            deduction_amount: summary[:deduction_amount],
            total_payable: summary[:total_payable],
            status: status,
            status_class: calculator.send(:jeevika_bill_status_class, record),
            record_state: data["record_state"].presence || "Active"
          },
          activities: items.map.with_index { |item, index| bill_activity_payload(item, index) },
          farmers: bill_farmer_payloads(items),
          time_slots: calculator.send(:jeevika_bill_time_slot_rows, record),
          descriptions: calculator.send(:jeevika_bill_description_rows, record),
          bank_details: calculator.send(:jeevika_bill_bank_rows, record),
          attachments: bill_attachment_payloads(record),
          prepared_by: calculator.send(:jeevika_bill_prepared_by, record),
          approved_by: calculator.send(:jeevika_bill_approved_by_rows, record),
          approval: {
            current_approver: current_approver,
            current_step_id: current_step&.id,
            steps: approval_step_payloads(record, history, current_step),
            history: history.map { |entry| approval_history_payload(entry) },
            actions: {
              can_send_for_approval: status.to_s.downcase.include?("submitted") && approval_steps(record).any?,
              can_approve: current_approver && status.to_s.include?("Pending"),
              can_reject: current_approver && status.to_s.include?("Pending"),
              can_return: current_approver && status.to_s.include?("Pending")
            }
          }
        }
      end

      def bill_activity_payload(item, index)
        {
          serial_number: index + 1,
          ics: item["ics"].presence || "-",
          village: item["village"].presence || "-",
          main_activity: item["main_activity"].presence || "-",
          sub_activity: item["activity"].presence || "-",
          target: item["target_quantity"].presence || "0",
          achievement: item["achievement_count"].presence || "0",
          pending: item["pending_count"].presence || "0",
          rate: item["rate"].presence || "0.00",
          total: item["amount"].presence || "0.00"
        }
      end

      def bill_farmer_payloads(items)
        items.flat_map do |item|
          Array(item["farmer_details"]).filter_map do |farmer|
            next unless farmer.respond_to?(:[])

            {
              id: farmer["id"],
              name: farmer["name"].presence || "-",
              mobile_no: farmer["mobile_no"].presence || "-",
              village: item["village"].presence || "-",
              main_activity: farmer["training_topic"].presence || item["main_activity"].presence || "-",
              sub_activity: farmer["training_subject"].presence || item["activity"].presence || "-",
              training_date: farmer["training_date"].presence || "-"
            }
          end
        end
      end

      def bill_attachment_payloads(record)
        calculator.send(:jeevika_bill_attachment_rows, record).map do |label, attachment|
          {
            label: label,
            attached: attachment&.attached? || false,
            filename: attachment&.attached? ? attachment.filename.to_s : nil,
            url: attachment&.attached? ? attachment_url(attachment) : nil
          }
        end
      end

      def approval_step_payloads(record, history, current_step)
        approval_steps(record).map do |step|
          sequence = approval_sequence(step)
          closing = history.find do |entry|
            approval_level_sequence(entry.data["approval_level"]) == sequence &&
              %w[Approved Rejected Returned].include?(entry.data["action"])
          end
          action = closing&.data&.[]("action")
          state = if %w[Rejected Returned].include?(action)
            "rejected"
          elsif closing
            "approved"
          elsif current_step&.id == step.id
            "current"
          else
            "pending"
          end

          {
            id: step.id,
            sequence: sequence,
            approval_level: step.data["approval_level"],
            approver: step.data["approver_approved_by"],
            state: state,
            action: action,
            action_at: closing&.data&.[]("action_at"),
            remarks: closing&.data&.[]("remarks"),
            action_by: closing&.data&.[]("action_by")
          }
        end
      end

      def approval_level_sequence(level)
        calculator.send(:approval_sequence_from_level, level)
      end

      def approval_history_payload(entry)
        entry.data.slice("action", "approval_level", "approver", "remarks", "action_by", "action_at")
          .merge("id" => entry.id)
      end

      def bill_records
        @bill_records ||= ModuleRecord.where(module_slug: BILL_SLUG).order(created_at: :desc, id: :desc).to_a
      end

      def payment_list_user?
        calculator.send(:jeevika_jankar_payment_list_user?)
      end

      def payment_access_denied
        render json: { success: false, message: "You are not allowed to access payment records." }, status: :forbidden
      end

      def selected_month
        params[:month].presence || params[:payment_month].presence
      end

      def filter_month(rows)
        return rows if selected_month.blank?

        rows.select { |row| same_text?(row[:bill_month], selected_month) }
      end

      def month_options(rows)
        rows.filter_map { |row| row[:bill_month].to_s.strip.presence }
          .reject { |month| month == "-" }.uniq
      end

      def bill_payload_for(record)
        data = record.data
        summary = calculator.send(:jeevika_bill_summary, record)
        history = calculator.send(:jeevika_bill_approval_history, record)
        vrp_label = data["select_vrp_name"].presence || calculator.send(:jeevika_jankar_vrp_label, data["select_vrp"])

        {
          id: record.id,
          bill_id: record.id,
          vrp_id: data["select_vrp"],
          name: calculator.send(:jeevika_jankar_display_name, vrp_label),
          financial_year: data["financial_year"].presence || "-",
          bill_month: data["bill_month"].presence || "-",
          activity_groups: summary[:activity_groups].presence || "-",
          activity_names: summary[:activity_names].presence || "-",
          target: data["total_target"].presence || "0",
          achievement: data["total_achievement"].presence || "0",
          amount: calculator.send(:jeevika_jankar_bill_total_payment, record),
          status: calculator.send(:jeevika_bill_status_label, record),
          status_class: calculator.send(:jeevika_bill_status_class, record),
          record_state: data["record_state"].presence || "Active",
          current_approver: calculator.send(:jeevika_bill_current_approver?, record),
          approval_remarks: calculator.send(:bill_approval_remarks_text, history)
        }
      end

      def payment_payload_for(record)
        bank_row = calculator.send(:jeevika_bill_bank_rows, record).first || {}
        vrp = calculator.send(:jeevika_bill_vrp, record)
        payload = bill_payload_for(record).merge(
          bank_name: bank_row[:bank_name].presence || "-",
          ifsc_code: bank_row[:ifsc_code].presence || "-",
          account_number: bank_row[:account_number].presence || "-"
        )
        attachment = vrp&.bank_passbook_upload
        payload[:passbook_url] = attachment_url(attachment) if attachment&.attached?
        payload[:download_bill_url] = "#{request.base_url}/api/v1/jeevika-jankar-bills/#{record.id}/download"
        payload
      end

      def payment_export_url(month)
        url = "#{request.base_url}/api/v1/jeevika-jankar-payments/export"
        month.present? ? "#{url}?month=#{ERB::Util.url_encode(month)}" : url
      end

      def bill_download_html(detail)
        summary = detail[:summary]
        activities = detail[:activities].map do |row|
          values = [row[:serial_number], row[:ics], row[:village], row[:main_activity], row[:sub_activity], row[:target], row[:achievement], row[:pending], row[:rate], row[:total]]
          "<tr>#{values.map { |value| "<td>#{h(value)}</td>" }.join}</tr>"
        end.join
        farmers = detail[:farmers].map do |row|
          values = [row[:name], row[:mobile_no], row[:village], row[:main_activity], row[:sub_activity], row[:training_date]]
          "<tr>#{values.map { |value| "<td>#{h(value)}</td>" }.join}</tr>"
        end.join

        <<~HTML
          <!doctype html><html><head><meta charset="utf-8"><title>Bill #{h(summary[:bill_id])}</title>
          <style>body{font-family:Arial,sans-serif;margin:28px;color:#172026}h1{color:#2f6f3e}table{width:100%;border-collapse:collapse;margin:18px 0;font-size:12px}th,td{border:1px solid #ccd6cc;padding:7px;text-align:left}.summary{display:grid;grid-template-columns:repeat(2,1fr);gap:8px}.box{border:1px solid #ccd6cc;padding:10px}</style></head><body>
          <h1>Jeevika Jankar Bill</h1><div class="summary">
          <div class="box"><b>Bill ID:</b> #{h(summary[:bill_id])}</div><div class="box"><b>VRP:</b> #{h(summary[:vrp_name])}</div>
          <div class="box"><b>FCO:</b> #{h(summary[:fco])}</div><div class="box"><b>Month:</b> #{h(summary[:bill_month])}</div>
          <div class="box"><b>Financial Year:</b> #{h(summary[:financial_year])}</div><div class="box"><b>Status:</b> #{h(summary[:status])}</div>
          <div class="box"><b>Total Amount:</b> #{h(summary[:total_amount])}</div><div class="box"><b>Total Payable:</b> #{h(summary[:total_payable])}</div></div>
          <h2>Activities</h2><table><thead><tr><th>#</th><th>ICS</th><th>Village</th><th>Main Activity</th><th>Sub Activity</th><th>Target</th><th>Achievement</th><th>Pending</th><th>Rate</th><th>Total</th></tr></thead><tbody>#{activities}</tbody></table>
          <h2>Farmers</h2><table><thead><tr><th>Farmer</th><th>Mobile</th><th>Village</th><th>Main Activity</th><th>Sub Activity</th><th>Training Date</th></tr></thead><tbody>#{farmers}</tbody></table>
          </body></html>
        HTML
      end

      def h(value)
        ERB::Util.html_escape(value.to_s)
      end

      def completed_payment_payload(row)
        row.merge(
          transaction_file: public_file_url(row[:transaction_file]),
          excel_file: public_file_url(row[:excel_file])
        )
      end

      def attachment_url(attachment)
        Rails.application.routes.url_helpers.rails_blob_url(attachment, host: request.base_url)
      end

      def public_file_url(value)
        return if value.blank?
        return value if value.to_s.match?(/\Ahttps?:\/\//i)

        "#{request.base_url}#{value.to_s.start_with?("/") ? value : "/#{value}"}"
      end

      def same_text?(left, right)
        left.to_s.strip.casecmp(right.to_s.strip).zero?
      end
    end
  end
end
