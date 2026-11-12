namespace :jeevika_payment_mail do
  # Sends ONE sample payment update mail, built from the latest already-saved
  # payment, to the given address. Nothing is saved and no SMS is sent.
  #   bin/rails "jeevika_payment_mail:test[s.saxena@asabhopal.org]"
  desc "Send one sample Jeevika Jankar payment update mail to an address"
  task :test, [:to] => :environment do |_task, args|
    to = args[:to].to_s.strip
    abort "Usage: bin/rails \"jeevika_payment_mail:test[name@example.org]\"" if to.blank?
    if ENV["SMTP_PASSWORD"].blank? && !JeevikaPaymentMailRelay.enabled?
      abort "Na JJ_PAYMENT_MAIL_RELAY_URL (krai) set hai, na SMTP_PASSWORD - koi ek environment me set karein."
    end

    payment = ModuleRecord.where(module_slug: ModulesController::JEEVIKA_JANKAR_PAYMENT_DETAIL_SLUG)
      .order(created_at: :desc, id: :desc).first
    item = Array(payment&.data&.[]("payment_items")).find { |entry| entry.respond_to?(:[]) }
    abort "Koi saved payment nahi mili jisse sample mail bane." unless item

    vrp = Vrp.find_by(id: item["jeevika_jankar_id"])
    details = {
      bill_id: item["bill_id"].to_s,
      jj_id: item["jeevika_jankar_id"].to_s,
      jj_email: vrp&.email.to_s,
      name: item["jeevika_jankar_name"].presence || vrp&.name.to_s,
      mobile_no: vrp&.mobile_no.to_s,
      financial_year: item["financial_year"].to_s,
      bill_month: item["bill_month"].to_s,
      approval_date_label: (Date.parse(item["approval_date"].to_s).strftime("%d/%m/%Y") rescue item["approval_date"].to_s),
      amount: item["amount"].to_s,
      transaction_id: payment.data["transaction_id"].to_s,
      transaction_type: payment.data["transaction_type"].to_s,
      transaction_date_label: (Date.parse(payment.data["transaction_date"].to_s).strftime("%d/%m/%Y") rescue payment.data["transaction_date"].to_s),
      updated_at_label: payment.created_at.in_time_zone.strftime("%d/%m/%Y %I:%M %p"),
      updated_by: payment.data["created_by_username"].to_s
    }

    ENV["PAYMENT_MAIL_TEST_TO"] = to
    if JeevikaPaymentMailRelay.enabled?
      JeevikaPaymentMailRelay.deliver!(to, details)
      via = "krai (#{JeevikaPaymentMailRelay.url})"
    else
      JeevikaPaymentMailer.payment_updated(to, details).deliver_now
      via = "SMTP"
    end
    puts "Test mail bheja gaya via #{via}: #{to} (sample: #{details[:name]}, #{details[:bill_month]} #{details[:financial_year]}, Rs. #{details[:amount]})"
  end
end
