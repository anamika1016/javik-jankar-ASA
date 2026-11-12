# Mail sent to a Jeevika Jankar when their bill payment is updated on
# "Jeevika Jankar Payment List Detail" (screen save or Excel upload).
#
# Who receives it is decided by .recipient_for:
#   PAYMENT_MAIL_TEST_TO=a@b.org   every mail goes only to that address (testing)
#   PAYMENT_MAIL_ENABLED=true      mail goes to the Jeevika Jankar's own email
#   neither set                    no mail is sent
class JeevikaPaymentMailer < ApplicationMailer
  layout false

  # Same subject on every payment mail, by SMTP or through krai, with the
  # Jeevika Jankar's name in front.
  SUBJECT = "Jeevika Jankar Payment Notification".freeze

  def self.subject_for(details)
    [details[:name].presence, SUBJECT].compact.join(" - ")
  end

  # The mail text, the same in every mail (a test mail looks like a real one).
  def self.message_for(details)
    "Aapke #{details[:bill_month]} #{details[:financial_year]} ke bill ki Rs. #{details[:amount]} ki payment " \
      "#{details[:transaction_date_label]} ko #{details[:transaction_type]} dwara aapke bank khate mein bhej di gayi hai. " \
      "Transaction ID / UTR: #{details[:transaction_id].presence || '-'}."
  end

  def self.test_recipient
    ENV["PAYMENT_MAIL_TEST_TO"].to_s.strip.presence
  end

  def self.enabled?
    test_recipient.present? || ENV["PAYMENT_MAIL_ENABLED"].to_s.strip.casecmp("true").zero?
  end

  def self.recipient_for(jj_email)
    return test_recipient if test_recipient.present?
    return nil unless enabled?

    jj_email.to_s.strip.presence
  end

  def self.from_address
    ENV["MAIL_FROM"].presence || ENV["SMTP_USERNAME"].presence || "notification@asabhopal.org"
  end

  # details: hash built by ModulesController#jeevika_payment_mail_details
  def payment_updated(recipient, details)
    @details = details
    mail(to: recipient, from: self.class.from_address, subject: self.class.subject_for(details))
  end
end
