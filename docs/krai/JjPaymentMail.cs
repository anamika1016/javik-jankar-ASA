// JjPaymentMail.cs - Jeevika Jankar Payment Notification ka HTML mail body.
//
// krai team ke liye: is file ko App_Code mein rakhein (ya project mein jodein).
// jj_payment_notify.aspx ke code-behind mein, jahan abhi mail ka body banta hai,
// wahan ye likhein:
//
//     mail.Subject         = Request["subject"];
//     mail.SubjectEncoding = System.Text.Encoding.UTF8;
//     mail.Body            = JjPaymentMail.BuildHtml(Request.QueryString);
//     mail.BodyEncoding    = System.Text.Encoding.UTF8;
//     mail.IsBodyHtml      = true;
//     mail.To.Add(Request["to_email"]);
//
// Baaki sab (notification ID, SMTP, "sent successfully" wala jawab) waisa hi rahe.
// test_mode aur actual_email ko ignore karein: mail hamesha to_email par jaye.
//
// Har value HtmlEncode hoti hai, isliye naam ya UTR mein <, >, & aaye to bhi
// mail nahi tootegi. Khali value ki jagah "-" dikhta hai.

using System;
using System.Collections.Specialized;
using System.Text.RegularExpressions;
using System.Web;

public static class JjPaymentMail
{
    // Template mein aane wale parameters: amount, approval_date, bill_id, bill_month, financial_year, jj_id, mobile_no, name, transaction_date, transaction_id, transaction_type, updated_by, updated_on
    public static string BuildHtml(NameValueCollection values)
    {
        return Regex.Replace(Template, @"\{\{(\w+)\}\}", match =>
        {
            string value = values[match.Groups[1].Value];
            return HttpUtility.HtmlEncode(string.IsNullOrWhiteSpace(value) ? "-" : value.Trim());
        });
    }

    private const string Template = @"<!DOCTYPE html>
<html lang=""hi"">
  <head>
    <meta charset=""utf-8"">
    <meta name=""viewport"" content=""width=device-width, initial-scale=1"">
    <title>Jeevika Jankar Payment Notification</title>
  </head>
  <body style=""margin:0;padding:0;background:#eef3ef;font-family:Arial,Helvetica,sans-serif;color:#1f2d26;"">
    <table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"" border=""0"" style=""background:#eef3ef;"">
      <tr>
        <td align=""center"" style=""padding:28px 12px;"">
          <table role=""presentation"" width=""600"" cellpadding=""0"" cellspacing=""0"" border=""0"" style=""width:100%;max-width:600px;background:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #d8e4dc;"">

            <!-- Header -->
            <tr>
              <td style=""background:#1f6b3a;padding:26px 28px;"">
                <table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"" border=""0"">
                  <tr>
                    <td style=""color:#cfe8d6;font-size:12px;letter-spacing:1.5px;font-weight:bold;text-transform:uppercase;"">
                      Action for Social Advancement (ASA)
                    </td>
                  </tr>
                  <tr>
                    <td style=""color:#ffffff;font-size:22px;font-weight:bold;padding-top:6px;line-height:1.3;"">
                      Jeevika Jankar Payment Notification
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

            <!-- Greeting -->
            <tr>
              <td style=""padding:26px 28px 8px;font-size:15px;line-height:1.6;"">
                Namaste <strong>{{name}}</strong>,
              </td>
            </tr>

            <!-- Amount card -->
            <tr>
              <td style=""padding:12px 28px 6px;"">
                <table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"" border=""0"" style=""background:#e9f6ee;border:1px solid #bfe3cb;border-radius:10px;"">
                  <tr>
                    <td style=""padding:18px 20px;"">
                      <div style=""font-size:12px;color:#4d6b58;text-transform:uppercase;letter-spacing:1px;font-weight:bold;"">Payment Amount</div>
                      <div style=""font-size:30px;color:#16733b;font-weight:bold;padding-top:4px;"">&#8377; {{amount}}</div>
                    </td>
                    <td align=""right"" style=""padding:18px 20px;"">
                      <span style=""display:inline-block;background:#16733b;color:#ffffff;font-size:12px;font-weight:bold;padding:6px 14px;border-radius:20px;"">PAID</span>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

            <!-- Payment details table -->
            <tr>
              <td style=""padding:18px 28px 6px;"">
                <div style=""font-size:14px;font-weight:bold;color:#1f6b3a;padding-bottom:8px;"">Payment Details</div>
                <table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"" border=""0"" style=""border:1px solid #dfe8e2;border-radius:8px;border-collapse:separate;font-size:14px;"">
                  <tr style=""background:#f6faf7;"">
                    <td style=""padding:11px 14px;color:#5b6b63;width:45%;border-bottom:1px solid #e6ede9;"">Transaction ID / UTR</td>
                    <td style=""padding:11px 14px;font-weight:bold;border-bottom:1px solid #e6ede9;"">{{transaction_id}}</td>
                  </tr>
                  <tr>
                    <td style=""padding:11px 14px;color:#5b6b63;border-bottom:1px solid #e6ede9;"">Transaction Type</td>
                    <td style=""padding:11px 14px;font-weight:bold;border-bottom:1px solid #e6ede9;"">{{transaction_type}}</td>
                  </tr>
                  <tr style=""background:#f6faf7;"">
                    <td style=""padding:11px 14px;color:#5b6b63;border-bottom:1px solid #e6ede9;"">Transaction Date</td>
                    <td style=""padding:11px 14px;font-weight:bold;border-bottom:1px solid #e6ede9;"">{{transaction_date}}</td>
                  </tr>
                  <tr>
                    <td style=""padding:11px 14px;color:#5b6b63;border-bottom:1px solid #e6ede9;"">Bill Month</td>
                    <td style=""padding:11px 14px;font-weight:bold;border-bottom:1px solid #e6ede9;"">{{bill_month}} {{financial_year}}</td>
                  </tr>
                  <tr style=""background:#f6faf7;"">
                    <td style=""padding:11px 14px;color:#5b6b63;border-bottom:1px solid #e6ede9;"">Bill ID</td>
                    <td style=""padding:11px 14px;font-weight:bold;border-bottom:1px solid #e6ede9;"">{{bill_id}}</td>
                  </tr>
                  <tr>
                    <td style=""padding:11px 14px;color:#5b6b63;"">Approval Date</td>
                    <td style=""padding:11px 14px;font-weight:bold;"">{{approval_date}}</td>
                  </tr>
                </table>
              </td>
            </tr>

            <!-- Jeevika Jankar details table -->
            <tr>
              <td style=""padding:18px 28px 6px;"">
                <div style=""font-size:14px;font-weight:bold;color:#1f6b3a;padding-bottom:8px;"">Jeevika Jankar Details</div>
                <table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"" border=""0"" style=""border:1px solid #dfe8e2;border-radius:8px;border-collapse:separate;font-size:14px;"">
                  <tr style=""background:#f6faf7;"">
                    <td style=""padding:11px 14px;color:#5b6b63;width:45%;border-bottom:1px solid #e6ede9;"">Jeevika Jankar ID</td>
                    <td style=""padding:11px 14px;font-weight:bold;border-bottom:1px solid #e6ede9;"">{{jj_id}}</td>
                  </tr>
                  <tr>
                    <td style=""padding:11px 14px;color:#5b6b63;border-bottom:1px solid #e6ede9;"">Name</td>
                    <td style=""padding:11px 14px;font-weight:bold;border-bottom:1px solid #e6ede9;"">{{name}}</td>
                  </tr>
                  <tr style=""background:#f6faf7;"">
                    <td style=""padding:11px 14px;color:#5b6b63;"">Mobile Number</td>
                    <td style=""padding:11px 14px;font-weight:bold;"">{{mobile_no}}</td>
                  </tr>
                </table>
              </td>
            </tr>

            <!-- Update info -->
            <tr>
              <td style=""padding:14px 28px 4px;font-size:12px;color:#7a8a82;"">
                Payment updated on {{updated_on}} by {{updated_by}}
              </td>
            </tr>

            <!-- Footer -->
            <tr>
              <td style=""padding:18px 28px 26px;"">
                <table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"" border=""0"" style=""border-top:1px solid #e6ede9;"">
                  <tr>
                    <td style=""padding-top:16px;font-size:13px;color:#5b6b63;line-height:1.6;"">
                      Payment se judi kisi bhi jaankari ke liye apne Cluster Coordinator se sampark karein.<br><br>
                      Regards,<br>
                      <strong style=""color:#1f2d26;"">ASA Jeevika Jankar System</strong><br>
                      Action for Social Advancement
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

          </table>
          <div style=""font-size:11px;color:#8a9a92;padding-top:14px;"">Ye mail automatic bheja gaya hai, kripya iska reply na karein.</div>
        </td>
      </tr>
    </table>
  </body>
</html>
";
}
