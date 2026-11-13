using System.Net;
using System.Net.Mail;

namespace Gharbaar.Api.Mail;

// Email settings. Email is optional: with no Host or From, invites are still saved and no mail is sent.
public sealed record SmtpOptions(string? Host, int Port, string? User, string? PasswordFile, string? From);

public sealed class Mailer(SmtpOptions options, ILogger<Mailer> log)
{
    public bool Enabled => !string.IsNullOrWhiteSpace(options.Host) && !string.IsNullOrWhiteSpace(options.From);

    // Returns true if the mail server accepted the message. A failure is logged, not thrown,
    // so an invite is never lost because the mail server is down.
    public async Task<bool> TrySendAsync(string to, string subject, string body)
    {
        if (!Enabled)
            return false;

        try
        {
            using var message = new MailMessage(options.From!, to, subject, body);
            using var client = new SmtpClient(options.Host!, options.Port) { EnableSsl = true };
            if (!string.IsNullOrWhiteSpace(options.User))
                client.Credentials = new NetworkCredential(options.User, ReadPassword());

            await client.SendMailAsync(message);
            return true;
        }
        catch (Exception ex)
        {
            log.LogWarning(ex, "Could not send an invite email");
            return false;
        }
    }

    private string ReadPassword() =>
        !string.IsNullOrEmpty(options.PasswordFile) && File.Exists(options.PasswordFile)
            ? File.ReadAllText(options.PasswordFile).Trim()
            : "";
}
