using Gharbaar.Api.Auth;
using Gharbaar.Api.Data;
using Npgsql;

namespace Gharbaar.Api.Account;

public sealed record ChangePasswordRequest(string? CurrentPassword, string? NewPassword);
public sealed record ProfileRequest(string? DisplayName, string? Currency);
public sealed record DeleteAccountRequest(string? Password);

// The signed-in person's own account: profile, password, and disabling the account.
public static class AccountEndpoints
{
    public static void MapAccountEndpoints(this WebApplication app)
    {
        var me = app.MapGroup("/me");
        me.MapGet("", GetProfile);
        me.MapPut("", UpdateProfile);
        me.MapPost("/password", ChangePassword);
        me.MapPost("/delete", DeleteAccount);
    }

    private static async Task<IResult> GetProfile(HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();

        await using var cmd = db.CreateCommand(
            @"select u.id, u.username, u.email, coalesce(p.display_name, ''), coalesce(p.currency, 'PKR')
              from users u
              left join user_profiles p on p.user_id = u.id
              where u.id = $1");
        cmd.Parameters.AddWithValue(me.Value);

        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            return Results.NotFound();

        return Results.Ok(new
        {
            id = reader.GetGuid(0),
            username = reader.IsDBNull(1) ? null : reader.GetString(1),
            email = reader.IsDBNull(2) ? null : reader.GetString(2),
            displayName = reader.GetString(3),
            currency = reader.GetString(4),
        });
    }

    // Changes only the fields that are sent. The username and email can't be changed (the database enforces that).
    private static async Task<IResult> UpdateProfile(
        ProfileRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();

        string? displayName = req.DisplayName?.Trim();
        string? currency = req.Currency?.Trim().ToUpperInvariant();
        if (displayName is not null && (displayName.Length is 0 or > 60))
            return Results.BadRequest(new { error = "Display name must be 1-60 characters." });
        if (currency is not null && !System.Text.RegularExpressions.Regex.IsMatch(currency, "^[A-Z]{3}$"))
            return Results.BadRequest(new { error = "Currency must be a 3-letter code, such as PKR." });

        await using var conn = await db.OpenConnectionAsync();
        await using var cmd = new NpgsqlCommand(
            @"insert into user_profiles (user_id, display_name, currency)
              values ($1, coalesce($2, ''), coalesce($3, 'PKR'))
              on conflict (user_id) do update
              set display_name = coalesce($2, user_profiles.display_name),
                  currency = coalesce($3, user_profiles.currency),
                  updated_at = now()", conn);
        cmd.Parameters.AddWithValue(me.Value);
        cmd.Parameters.AddWithValue((object?)displayName ?? DBNull.Value);
        cmd.Parameters.AddWithValue((object?)currency ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync();

        return Results.NoContent();
    }

    // Checks the current password, sets the new one, and signs out every device (they must sign in again).
    private static async Task<IResult> ChangePassword(
        ChangePasswordRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db, PasswordService passwords)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();
        if (string.IsNullOrEmpty(req.CurrentPassword))
            return Results.BadRequest(new { error = "Enter your current password." });
        if (!passwords.IsStrongEnough(req.NewPassword))
            return Results.BadRequest(new { error = "New password must be at least 8 characters." });

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();

        var stored = await Sql.Scalar(conn, tx, "select password_hash from users where id = $1 for update", me.Value) as string;
        if (stored is null || !passwords.Verify(stored, req.CurrentPassword))
            return Results.Json(new { error = "Current password is wrong." }, statusCode: StatusCodes.Status401Unauthorized);

        await Sql.Exec(conn, tx, "update users set password_hash = $2 where id = $1", me.Value, passwords.Hash(req.NewPassword!));
        await Sql.Exec(conn, tx, "update refresh_tokens set revoked_at = now() where user_id = $1 and revoked_at is null", me.Value);
        await tx.CommitAsync();

        return Results.NoContent();
    }

    // Disables the login and leaves every household. The username stays reserved and the history is kept,
    // because the budget records point to this person.
    private static async Task<IResult> DeleteAccount(
        DeleteAccountRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db, PasswordService passwords)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();
        if (string.IsNullOrEmpty(req.Password))
            return Results.BadRequest(new { error = "Enter your password to delete the account." });

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();

        var stored = await Sql.Scalar(conn, tx, "select password_hash from users where id = $1 for update", me.Value) as string;
        if (stored is null || !passwords.Verify(stored, req.Password))
            return Results.Json(new { error = "Password is wrong." }, statusCode: StatusCodes.Status401Unauthorized);

        await Sql.Exec(conn, tx, "update users set password_hash = null where id = $1", me.Value);
        await Sql.Exec(conn, tx, "update refresh_tokens set revoked_at = now() where user_id = $1 and revoked_at is null", me.Value);
        await Sql.Exec(conn, tx,
            "update household_members set left_at = now() where user_id = $1 and left_at is null", me.Value);
        await tx.CommitAsync();

        return Results.NoContent();
    }
}
