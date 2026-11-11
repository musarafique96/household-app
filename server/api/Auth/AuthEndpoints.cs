using System.Text.RegularExpressions;
using Npgsql;

namespace Gharbaar.Api.Auth;

public sealed record SignUpRequest(string? Username, string? Password);
public sealed record SignInRequest(string? Login, string? Password, string? Device = null);
public sealed record RefreshRequest(string? RefreshToken);

public static partial class AuthEndpoints
{
    [GeneratedRegex("^[a-z0-9_.]{3,30}$")]
    private static partial Regex UsernamePattern();

    public static void MapAuthEndpoints(this WebApplication app)
    {
        var auth = app.MapGroup("/auth");
        auth.MapPost("/signup", SignUp);
        auth.MapPost("/signin", SignIn);
        auth.MapPost("/refresh", Refresh);
        auth.MapPost("/signout", SignOut);
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

        Guid userId;
        {
            await using var cmd = db.CreateCommand(
                "select id, password_hash from users where username = $1 or lower(email) = $1 limit 1");
            cmd.Parameters.AddWithValue(login);

            await using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
            {
                // Do the same work as a real check so timing does not reveal whether the account exists.
                passwords.Hash(req.Password);
                return invalid;
            }

            userId = reader.GetGuid(0);
            var storedHash = reader.IsDBNull(1) ? null : reader.GetString(1);
            if (storedHash is null || !passwords.Verify(storedHash, req.Password))
                return invalid;
        }

        await using var conn = await db.OpenConnectionAsync();
        var refreshToken = await InsertRefreshToken(conn, null, userId, req.Device);
        return TokenResponse(tokens, userId, refreshToken);
    }

    private static async Task<IResult> Refresh(
        RefreshRequest req, NpgsqlDataSource db, TokenService tokens)
    {
        var invalid = Results.Json(
            new { error = "Your session has ended. Please sign in again." },
            statusCode: StatusCodes.Status401Unauthorized);

        if (string.IsNullOrEmpty(req.RefreshToken))
            return invalid;

        var hash = RefreshTokens.Hash(req.RefreshToken);

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();

        Guid userId;
        string? device;
        {
            await using var find = new NpgsqlCommand(
                "select user_id, revoked_at, expires_at, device from refresh_tokens where token_hash = $1 for update",
                conn, tx);
            find.Parameters.AddWithValue(hash);

            await using var reader = await find.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
                return invalid;

            userId = reader.GetGuid(0);
            var revoked = !reader.IsDBNull(1);
            var expiresAt = reader.GetFieldValue<DateTimeOffset>(2);
            device = reader.IsDBNull(3) ? null : reader.GetString(3);

            if (revoked)
            {
                // A revoked token was used again. Someone may have copied it, so end every session for this user.
                await reader.CloseAsync();
                await using var revokeAll = new NpgsqlCommand(
                    "update refresh_tokens set revoked_at = now() where user_id = $1 and revoked_at is null", conn, tx);
                revokeAll.Parameters.AddWithValue(userId);
                await revokeAll.ExecuteNonQueryAsync();
                await tx.CommitAsync();
                return invalid;
            }

            if (expiresAt <= DateTimeOffset.UtcNow)
                return invalid;
        }

        // Rotate: retire the used token and issue a new one.
        await using (var retire = new NpgsqlCommand(
            "update refresh_tokens set revoked_at = now() where token_hash = $1", conn, tx))
        {
            retire.Parameters.AddWithValue(hash);
            await retire.ExecuteNonQueryAsync();
        }

        var newToken = await InsertRefreshToken(conn, tx, userId, device);
        await tx.CommitAsync();
        return TokenResponse(tokens, userId, newToken);
    }

    private static async Task<IResult> SignOut(RefreshRequest req, NpgsqlDataSource db)
    {
        // Always 204, so the response does not reveal whether a token was valid.
        if (!string.IsNullOrEmpty(req.RefreshToken))
        {
            await using var cmd = db.CreateCommand(
                "update refresh_tokens set revoked_at = now() where token_hash = $1 and revoked_at is null");
            cmd.Parameters.AddWithValue(RefreshTokens.Hash(req.RefreshToken));
            await cmd.ExecuteNonQueryAsync();
        }

        return Results.NoContent();
    }

    private static async Task<string> InsertRefreshToken(
        NpgsqlConnection conn, NpgsqlTransaction? tx, Guid userId, string? device)
    {
        var raw = RefreshTokens.NewToken();
        var deviceName = string.IsNullOrWhiteSpace(device)
            ? null
            : device.Trim()[..Math.Min(device.Trim().Length, 100)];

        await using var cmd = new NpgsqlCommand(
            "insert into refresh_tokens (user_id, token_hash, device, expires_at) values ($1, $2, $3, $4)", conn, tx);
        cmd.Parameters.AddWithValue(userId);
        cmd.Parameters.AddWithValue(RefreshTokens.Hash(raw));
        cmd.Parameters.AddWithValue((object?)deviceName ?? DBNull.Value);
        cmd.Parameters.AddWithValue(DateTimeOffset.UtcNow.Add(RefreshTokens.Lifetime));
        await cmd.ExecuteNonQueryAsync();

        return raw;
    }

    private static IResult TokenResponse(TokenService tokens, Guid userId, string refreshToken) =>
        Results.Ok(new
        {
            accessToken = tokens.Create(userId),
            refreshToken,
            tokenType = "Bearer",
            expiresInSeconds = 900,
        });
}
