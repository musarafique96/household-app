using Gharbaar.Api.Auth;
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
builder.Services.AddSingleton<TokenService>();
builder.Services.AddSingleton<PasswordService>();

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapAuthEndpoints();

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
