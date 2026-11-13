using System.Net;
using Gharbaar.Api.Auth;
using Gharbaar.Api.Budget;
using Gharbaar.Api.Households;
using Gharbaar.Api.Mail;
using Microsoft.AspNetCore.HttpOverrides;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

var jwtKey = builder.Configuration["Jwt:Key"]
    ?? throw new InvalidOperationException("Jwt:Key is not set (environment variable Jwt__Key).");
if (jwtKey.Length < 32)
    throw new InvalidOperationException("Jwt:Key must be at least 32 characters.");

builder.Services.AddSingleton(NpgsqlDataSource.Create(BuildConnectionString(builder.Configuration)));
builder.Services.AddSingleton(new JwtOptions(
    jwtKey,
    builder.Configuration["Jwt:Issuer"] ?? "gharbaar",
    TimeSpan.FromMinutes(15)));
builder.Services.AddSingleton(new GoogleOptions(
    builder.Configuration["Google:ClientId"]
    ?? throw new InvalidOperationException("Google:ClientId is not set (environment variable Google__ClientId).")));
builder.Services.AddSingleton<TokenService>();
builder.Services.AddSingleton<PasswordService>();

// Email is optional. With no Smtp:Host or Smtp:From, invites are still created and no email is sent.
builder.Services.AddSingleton(new SmtpOptions(
    builder.Configuration["Smtp:Host"],
    int.TryParse(builder.Configuration["Smtp:Port"], out var smtpPort) ? smtpPort : 587,
    builder.Configuration["Smtp:User"],
    builder.Configuration["Smtp:PasswordFile"],
    builder.Configuration["Smtp:From"]));
builder.Services.AddSingleton<Mailer>();

// Caddy is the only proxy in front of this API. The client address is read from X-Forwarded-For
// only when the request comes from a trusted proxy (TrustedProxies__0 is set to Caddy's address).
var trustedProxies = builder.Configuration.GetSection("TrustedProxies").Get<string[]>()
    ?? new[] { "127.0.0.1", "::1" };
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownProxies.Clear();
    foreach (var proxy in trustedProxies)
    {
        options.KnownProxies.Add(IPAddress.Parse(proxy));
    }
});

var app = builder.Build();

app.UseForwardedHeaders();
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapAuthEndpoints();
app.MapHouseholdEndpoints();
app.MapBudgetEndpoints();

app.Run();

static string BuildConnectionString(IConfiguration config)
{
    var passwordFile = config["Db:PasswordFile"];
    var password = !string.IsNullOrWhiteSpace(passwordFile)
        ? File.ReadAllText(passwordFile).Trim()
        : config["Db:Password"] ?? throw new InvalidOperationException("Set Db:PasswordFile or Db:Password.");

    return new NpgsqlConnectionStringBuilder
    {
        Host = config["Db:Host"] ?? "localhost",
        Database = config["Db:Name"] ?? "gharbaar",
        Username = config["Db:User"] ?? "gharbaar",
        Password = password,
    }.ConnectionString;
}
