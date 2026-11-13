using Gharbaar.Api.Auth;
using Gharbaar.Api.Data;
using Gharbaar.Api.Mail;
using Npgsql;

namespace Gharbaar.Api.Households;

public sealed record CreateHouseholdRequest(string? Name);
public sealed record InviteRequest(string? TargetType, string? TargetValue);
public sealed record GrantRequest(bool? CanView, bool? CanEdit);
public sealed record RenameRequest(string? Name);

public static class HouseholdEndpoints
{
    private static readonly string[] Modules = { "budget" };

    public static void MapHouseholdEndpoints(this WebApplication app)
    {
        var households = app.MapGroup("/households");
        households.MapPost("", CreateHousehold);
        households.MapGet("", ListHouseholds);
        households.MapGet("/{householdId:guid}/members", ListMembers);
        households.MapPost("/{householdId:guid}/invites", Invite);
        households.MapPut("/{householdId:guid}/members/{userId:guid}/permissions/{module}", GrantPermission);
        households.MapPut("/{householdId:guid}", RenameHousehold);
        households.MapGet("/{householdId:guid}/invites", SentInvites);
        households.MapDelete("/{householdId:guid}/members/{userId:guid}", RemoveMember);

        var invites = app.MapGroup("/invites");
        invites.MapGet("/mine", MyInvites);
        invites.MapPost("/{inviteId:guid}/accept", (Guid inviteId, HttpContext http, JwtOptions jwt, NpgsqlDataSource db) =>
            Respond(inviteId, accept: true, http, jwt, db));
        invites.MapPost("/{inviteId:guid}/reject", (Guid inviteId, HttpContext http, JwtOptions jwt, NpgsqlDataSource db) =>
            Respond(inviteId, accept: false, http, jwt, db));
    }

    // The creator becomes the head. A household must always keep at least one head (enforced in the database).
    private static async Task<IResult> CreateHousehold(
        CreateHouseholdRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();

        var name = (req.Name ?? "").Trim();
        if (name.Length is 0 or > 80)
            return Results.BadRequest(new { error = "Household name must be 1-80 characters." });

        var id = Guid.NewGuid();
        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await Sql.Exec(conn, tx, "insert into households (id, name, created_by) values ($1,$2,$3)", id, name, me.Value);
        await Sql.Exec(conn, tx, "insert into household_members (household_id, user_id, role) values ($1,$2,'head')", id, me.Value);
        await tx.CommitAsync();

        return Results.Json(new { id, name, role = "head" }, statusCode: StatusCodes.Status201Created);
    }

    private static async Task<IResult> ListHouseholds(HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();

        await using var cmd = db.CreateCommand(
            @"select h.id, h.name, m.role
              from households h
              join household_members m on m.household_id = h.id and m.left_at is null
              where m.user_id = $1 and h.deleted_at is null
              order by h.created_at");
        cmd.Parameters.AddWithValue(me.Value);

        var list = new List<object>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
            list.Add(new { id = reader.GetGuid(0), name = reader.GetString(1), role = reader.GetString(2) });
        return Results.Ok(list);
    }

    private static async Task<IResult> ListMembers(
        Guid householdId, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();
        if (await Access.RoleAsync(db, householdId, me.Value) is null) return Results.NotFound();

        await using var cmd = db.CreateCommand(
            @"select m.user_id, coalesce(p.display_name, ''), m.role
              from household_members m
              left join user_profiles p on p.user_id = m.user_id
              where m.household_id = $1 and m.left_at is null
              order by m.joined_at");
        cmd.Parameters.AddWithValue(householdId);

        var list = new List<object>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
            list.Add(new { userId = reader.GetGuid(0), displayName = reader.GetString(1), role = reader.GetString(2) });
        return Results.Ok(list);
    }

    // Only a head can invite. The invite names a username or a Gmail address, and the invited person accepts
    // by signing in as that account. Phone invites wait until phone sign-in exists.
    private static async Task<IResult> Invite(
        Guid householdId, InviteRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db, Mailer mailer)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();
        if (await Access.RoleAsync(db, householdId, me.Value) != "head")
            return Forbidden("Only a head can invite people.");

        var type = (req.TargetType ?? "").Trim().ToLowerInvariant();
        var value = (req.TargetValue ?? "").Trim().ToLowerInvariant();
        if (type == "phone")
            return Results.BadRequest(new { error = "Phone invites will be available when phone sign-in is added." });
        if (type is not ("username" or "gmail") || value.Length is 0)
            return Results.BadRequest(new { error = "Invite a username or a Gmail address." });
        if (type == "gmail" && !value.Contains('@'))
            return Results.BadRequest(new { error = "That Gmail address does not look valid." });

        var inviteId = Guid.NewGuid();
        await using (var conn = await db.OpenConnectionAsync())
        await using (var tx = await conn.BeginTransactionAsync())
        {
            try
            {
                await Sql.Exec(conn, tx,
                    "insert into invites (id, household_id, invited_by, target_type, target_value) values ($1,$2,$3,$4,$5)",
                    inviteId, householdId, me.Value, type, value);
            }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
            {
                return Results.Conflict(new { error = "That person already has a pending invite to this household." });
            }
            await tx.CommitAsync();
        }

        // Email is a notice only. The invite already exists, so it works even when no email is sent.
        var recipient = type == "gmail" ? value : await EmailForUsername(db, value);
        var emailed = false;
        if (recipient is not null)
        {
            var (householdName, inviterName) = await NamesFor(db, householdId, me.Value);
            emailed = await mailer.TrySendAsync(
                recipient,
                $"You're invited to {householdName} on Gharbaar",
                $"{inviterName} invited you to join \"{householdName}\" on Gharbaar.\n\n" +
                $"Open the app and sign in as {value} to accept or decline the invite.");
        }

        return Results.Json(
            new { id = inviteId, targetType = type, targetValue = value, status = "pending", emailed },
            statusCode: StatusCodes.Status201Created);
    }

    private static async Task<IResult> MyInvites(HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();

        await using var cmd = db.CreateCommand(
            @"select i.id, h.name, i.target_type, i.target_value, i.created_at
              from invites i
              join households h on h.id = i.household_id
              join users u on u.id = $1
              where i.status = 'pending'
                and ((i.target_type = 'username' and u.username = i.target_value)
                  or (i.target_type = 'gmail' and lower(u.email) = i.target_value))
              order by i.created_at");
        cmd.Parameters.AddWithValue(me.Value);

        var list = new List<object>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                id = reader.GetGuid(0),
                householdName = reader.GetString(1),
                targetType = reader.GetString(2),
                targetValue = reader.GetString(3),
                createdAt = reader.GetDateTime(4),
            });
        }
        return Results.Ok(list);
    }

    private static async Task<IResult> Respond(
        Guid inviteId, bool accept, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();

        // Only the account the invite names can answer it. The row is locked so it can't be answered twice.
        Guid householdId;
        await using (var find = new NpgsqlCommand(
            @"select i.household_id
              from invites i
              join users u on u.id = $2
              where i.id = $1 and i.status = 'pending'
                and ((i.target_type = 'username' and u.username = i.target_value)
                  or (i.target_type = 'gmail' and lower(u.email) = i.target_value))
              for update of i", conn, tx))
        {
            find.Parameters.AddWithValue(inviteId);
            find.Parameters.AddWithValue(me.Value);
            if (await find.ExecuteScalarAsync() is not Guid found)
                return Results.NotFound(new { error = "Invite not found." });
            householdId = found;
        }

        if (accept)
        {
            try
            {
                await Sql.Exec(conn, tx,
                    "insert into household_members (household_id, user_id, role) values ($1,$2,'member')",
                    householdId, me.Value);
            }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
            {
                return Results.Conflict(new { error = "You are already a member of this household." });
            }
        }

        var status = accept ? "approved" : "rejected";
        await Sql.Exec(conn, tx,
            "update invites set status = $2, responded_at = now() where id = $1", inviteId, status);
        await tx.CommitAsync();

        return Results.Ok(new { householdId, status });
    }

    // A head grants a member view or edit rights for a module. Edit rights include view.
    private static async Task<IResult> GrantPermission(
        Guid householdId, Guid userId, string module, GrantRequest req,
        HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();
        if (await Access.RoleAsync(db, householdId, me.Value) != "head")
            return Forbidden("Only a head can change permissions.");
        if (!Modules.Contains(module))
            return Results.BadRequest(new { error = "Unknown module." });
        if (await Access.RoleAsync(db, householdId, userId) is null)
            return Results.BadRequest(new { error = "That person is not an active member." });

        var edit = req.CanEdit ?? false;
        var view = (req.CanView ?? false) || edit;

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await Sql.Exec(conn, tx,
            @"insert into member_permissions (household_id, user_id, module, can_view, can_edit, granted_by)
              values ($1,$2,$3,$4,$5,$6)
              on conflict (household_id, user_id, module)
              do update set can_view = excluded.can_view, can_edit = excluded.can_edit, granted_by = excluded.granted_by",
            householdId, userId, module, view, edit, me.Value);
        await tx.CommitAsync();

        return Results.Ok(new { userId, module, canView = view, canEdit = edit });
    }

    private static async Task<string?> EmailForUsername(NpgsqlDataSource db, string username)
    {
        await using var cmd = db.CreateCommand("select email from users where username = $1");
        cmd.Parameters.AddWithValue(username);
        return await cmd.ExecuteScalarAsync() as string;
    }

    private static async Task<(string HouseholdName, string InviterName)> NamesFor(
        NpgsqlDataSource db, Guid householdId, Guid inviterId)
    {
        await using var cmd = db.CreateCommand(
            @"select h.name, coalesce(p.display_name, '')
              from households h
              left join user_profiles p on p.user_id = $2
              where h.id = $1");
        cmd.Parameters.AddWithValue(householdId);
        cmd.Parameters.AddWithValue(inviterId);

        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            return ("a household", "Someone");

        var inviter = reader.GetString(1);
        return (reader.GetString(0), inviter.Length > 0 ? inviter : "Someone");
    }

    // Invites a head has sent to this household, newest first.
    private static async Task<IResult> SentInvites(Guid householdId, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();
        if (await Access.RoleAsync(db, householdId, me.Value) != "head")
            return Forbidden("Only a head can see sent invites.");

        await using var cmd = db.CreateCommand(
            @"select id, target_type, target_value, status, created_at
              from invites where household_id = $1 order by created_at desc limit 200");
        cmd.Parameters.AddWithValue(householdId);

        var list = new List<object>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                id = reader.GetGuid(0),
                targetType = reader.GetString(1),
                targetValue = reader.GetString(2),
                status = reader.GetString(3),
                createdAt = reader.GetDateTime(4),
            });
        }
        return Results.Ok(list);
    }

    private static async Task<IResult> RenameHousehold(
        Guid householdId, RenameRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();
        if (await Access.RoleAsync(db, householdId, me.Value) != "head")
            return Forbidden("Only a head can rename the household.");

        var name = (req.Name ?? "").Trim();
        if (name.Length is 0 or > 80)
            return Results.BadRequest(new { error = "Household name must be 1-80 characters." });

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await Sql.Exec(conn, tx, "update households set name = $2 where id = $1 and deleted_at is null", householdId, name);
        await tx.CommitAsync();
        return Results.Ok(new { id = householdId, name });
    }

    // A head removes someone, or any member removes themselves (leaving). The last head can't leave,
    // because the database requires every household to keep one.
    private static async Task<IResult> RemoveMember(
        Guid householdId, Guid userId, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return Results.Unauthorized();

        var myRole = await Access.RoleAsync(db, householdId, me.Value);
        if (myRole is null) return Results.NotFound();
        if (userId != me.Value && myRole != "head")
            return Forbidden("Only a head can remove other members.");
        if (await Access.RoleAsync(db, householdId, userId) is null)
            return Results.NotFound(new { error = "That person is not an active member." });

        try
        {
            await using var conn = await db.OpenConnectionAsync();
            await using var tx = await conn.BeginTransactionAsync();
            await Sql.Exec(conn, tx,
                "update household_members set left_at = now(), removed_by = $3 where household_id = $1 and user_id = $2 and left_at is null",
                householdId, userId, me.Value);
            await tx.CommitAsync();
        }
        catch (PostgresException ex) when (ex.MessageText.Contains("at least one head"))
        {
            return Results.Conflict(new { error = "Make someone else the head before you leave." });
        }

        return Results.NoContent();
    }

    private static IResult Forbidden(string message) =>
        Results.Json(new { error = message }, statusCode: StatusCodes.Status403Forbidden);
}
