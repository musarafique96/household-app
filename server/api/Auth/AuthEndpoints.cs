using System.Text.RegularExpressions;
using Npgsql;

namespace Gharbaar.Api.Auth;

public sealed record SignUpRequest(string? Username, string? Password);
public sealed record SignInRequest(string? Login, string? Password);

public static partial class AuthEndpoints
{
    [GeneratedRegex("^[a-z0-9_.]{3,30}$")]
    private static partial Regex UsernamePattern();

    public static void MapAuthEndpoints(this WebApplication app)
    {
        var auth = app.MapGroup("/auth");
        auth.MapPost("/signup", SignUp);
        auth.MapPost("/signin", SignIn);
    }

    private static async Task<IResult> SignUp(
        SignUpRequest req, NpgsqlDataSource db, PasswordService passwords)
    {
        var username = (req.Username ?? string.Empty).Trim().ToLowerInvariant();
        if (!UsernamePattern().IsMatch(username))
            return Results.BadRequest(new { error = "Username must be 3-30 characters: letters, numbers, dot or underscore." });
        if (!passwords.IsStrongEnough(req.Password))
            return Results.BadRequest(new { error = "Password must be at least 8 characters." });

        var userId = Guid.NewGuid();
        var passwordHash = passwords.Hash(req.Password!);

        try
        {
            await using var conn = await db.OpenConnectionAsync();
            await using var tx = await conn.BeginTransactionAsync();

            await using (var insertUser = new NpgsqlCommand(
                "insert into users (id, username, password_hash) values ($1, $2, $3)", conn, tx))
            {
                insertUser.Parameters.AddWithValue(userId);
                insertUser.Parameters.AddWithValue(username);
                insertUser.Parameters.AddWithValue(passwordHash);
                await insertUser.ExecuteNonQueryAsync();
            }

            await using (var insertProfile = new NpgsqlCommand(
                "insert into user_profiles (user_id, display_name) values ($1, $2)", conn, tx))
            {
                insertProfile.Parameters.AddWithValue(userId);
                insertProfile.Parameters.AddWithValue(username);
                await insertProfile.ExecuteNonQueryAsync();
            }

            await tx.CommitAsync();
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return Results.Conflict(new { error = "That username is already taken." });
        }

        return Results.Json(new { id = userId, username }, statusCode: StatusCodes.Status201Created);
    }

    private static async Task<IResult> SignIn(
        SignInRequest req, NpgsqlDataSource db, PasswordService passwords, TokenService tokens)
    {
        var invalid = Results.Json(
            new { error = "Invalid username or password." },
            statusCode: StatusCodes.Status401Unauthorized);

        var login = (req.Login ?? string.Empty).Trim().ToLowerInvariant();
        if (login.Length == 0 || string.IsNullOrEmpty(req.Password))
            return invalid;

        await using var cmd = db.CreateCommand(
            "select id, password_hash from users where username = $1 or lower(email) = $1 or phone = $1 limit 1");
        cmd.Parameters.AddWithValue(login);

        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            // Do the same work as a real check so timing does not reveal whether the account exists.
            passwords.Hash(req.Password);
            return invalid;
        }

        var userId = reader.GetGuid(0);
        var storedHash = reader.IsDBNull(1) ? null : reader.GetString(1);
        if (storedHash is null || !passwords.Verify(storedHash, req.Password))
            return invalid;

        return Results.Ok(new
        {
            accessToken = tokens.Create(userId),
            tokenType = "Bearer",
            expiresInSeconds = 900,
        });
    }
}
