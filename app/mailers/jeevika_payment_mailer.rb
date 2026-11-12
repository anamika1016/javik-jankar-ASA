# Mail sent to a Jeevika Jankar when their bill payment is updated on
# "Jeevika Jankar Payment List Detail" (screen save or Excel upload).
#
# Who receives it is decided by .recipient_for:
#   PAYMENT_MAIL_TEST_TO=a@b.org   every mail goes only to that address (testing)
#   PAYMENT_MAIL_ENABLED=true      mail goes to the Jeevika Jankar's own email
#   neither set                    no mail is sent
class JeevikaPaymentMailer < ApplicationMailer
  layout false

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
    @test_mode = self.class.test_recipient.present?
    subject = "Payment Update: #{details[:bill_month]} #{details[:financial_year]} - Rs. #{details[:amount]}"
    subject = "[TEST] #{subject} (#{details[:name]})" if @test_mode

    mail(to: recipient, from: self.class.from_address, subject: subject)
  end
end
