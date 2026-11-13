using System.Text.Json;
using System.Text.Json.Nodes;
using Gharbaar.Api.Auth;
using Gharbaar.Api.Data;
using Npgsql;

namespace Gharbaar.Api.Budget;

public sealed record CategoryRequest(string? Name, decimal? MonthlyLimit, int? Version);
public sealed record ExpenseRequest(Guid? CategoryId, decimal? Amount, string? ExpenseDate, string? Note, int? Version);
public sealed record ResolveRequest(string? Keep);
public sealed record SyncItem(string? Entity, Guid? EntityId, string? Operation, int? BaseVersion, JsonElement? Data);

// Budget categories and expenses for a household.
// Every write checks the caller's rights, changes a version number, and writes a change_log row in the same transaction.
// Edits send the version the phone last saw. If that is out of date, the server refuses the edit (409) or,
// for sync, keeps the phone's change in sync_conflicts for someone to review.
public static class BudgetEndpoints
{
    private const string Module = "budget";

    public static void MapBudgetEndpoints(this WebApplication app)
    {
        var h = app.MapGroup("/households/{householdId:guid}");

        h.MapGet("/categories", ListCategories);
        h.MapPost("/categories", CreateCategory);
        h.MapPut("/categories/{id:guid}", UpdateCategory);
        h.MapDelete("/categories/{id:guid}", DeleteCategory);

        h.MapGet("/expenses", ListExpenses);
        h.MapPost("/expenses", CreateExpense);
        h.MapPut("/expenses/{id:guid}", UpdateExpense);
        h.MapDelete("/expenses/{id:guid}", DeleteExpense);

        h.MapGet("/changes", Changes);
        h.MapPost("/sync", Sync);
        h.MapGet("/conflicts", ListConflicts);
        h.MapPost("/conflicts/{id:guid}/resolve", ResolveConflict);
    }

    // ---- Categories ----

    private static async Task<IResult> ListCategories(
        Guid householdId, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (_, error) = await Authorize(http, jwt, db, householdId, edit: false);
        if (error is not null) return error;

        await using var cmd = db.CreateCommand(
            "select id, name, monthly_limit, version from budget_categories where household_id = $1 and deleted_at is null order by name");
        cmd.Parameters.AddWithValue(householdId);

        var list = new List<object>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                id = reader.GetGuid(0),
                name = reader.GetString(1),
                monthlyLimit = reader.GetDecimal(2),
                version = reader.GetInt32(3),
            });
        }
        return Results.Ok(list);
    }

    private static async Task<IResult> CreateCategory(
        Guid householdId, CategoryRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (me, error) = await Authorize(http, jwt, db, householdId, edit: true);
        if (error is not null) return error;
        if (!ValidCategory(req.Name, req.MonthlyLimit, out var name, out var limit))
            return Results.BadRequest(new { error = "Name must be 1-60 characters and the monthly limit above zero." });

        var id = Guid.NewGuid();
        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await Sql.Exec(conn, tx,
            "insert into budget_categories (id, household_id, name, monthly_limit, created_by) values ($1,$2,$3,$4,$5)",
            id, householdId, name, limit, me!.Value);
        await Sql.LogChange(conn, tx, householdId, "budget_category", id, "create",
            CategoryPayload(id, 1, name, limit), me.Value);
        await tx.CommitAsync();

        return Results.Json(new { id, version = 1 }, statusCode: StatusCodes.Status201Created);
    }

    private static async Task<IResult> UpdateCategory(
        Guid householdId, Guid id, CategoryRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (me, error) = await Authorize(http, jwt, db, householdId, edit: true);
        if (error is not null) return error;
        if (!ValidCategory(req.Name, req.MonthlyLimit, out var name, out var limit))
            return Results.BadRequest(new { error = "Name must be 1-60 characters and the monthly limit above zero." });
        if (req.Version is null)
            return Results.BadRequest(new { error = "Send the version you are editing." });

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        var result = await Sql.Scalar(conn, tx,
            @"update budget_categories
              set name = $1, monthly_limit = $2, version = version + 1, updated_at = now()
              where id = $3 and household_id = $4 and version = $5 and deleted_at is null
              returning version",
            name, limit, id, householdId, req.Version.Value);
        if (result is null)
            return Results.Conflict(new { error = "This category was changed or deleted elsewhere. Refresh and try again." });

        var version = Convert.ToInt32(result);
        await Sql.LogChange(conn, tx, householdId, "budget_category", id, "update",
            CategoryPayload(id, version, name, limit), me!.Value);
        await tx.CommitAsync();

        return Results.Ok(new { id, version });
    }

    private static async Task<IResult> DeleteCategory(
        Guid householdId, Guid id, int? version, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (me, error) = await Authorize(http, jwt, db, householdId, edit: true);
        if (error is not null) return error;
        if (version is null)
            return Results.BadRequest(new { error = "Send the version you are deleting, as ?version=N." });

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        var result = await Sql.Scalar(conn, tx,
            @"update budget_categories
              set deleted_at = now(), version = version + 1, updated_at = now()
              where id = $1 and household_id = $2 and version = $3 and deleted_at is null
              returning version",
            id, householdId, version.Value);
        if (result is null)
            return Results.Conflict(new { error = "This category was changed or deleted elsewhere. Refresh and try again." });

        var newVersion = Convert.ToInt32(result);
        await Sql.LogChange(conn, tx, householdId, "budget_category", id, "delete",
            new { id, version = newVersion, deleted = true }, me!.Value);
        await tx.CommitAsync();

        return Results.Ok(new { id, version = newVersion });
    }

    // ---- Expenses ----

    private static async Task<IResult> ListExpenses(
        Guid householdId, string? from, string? to, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (_, error) = await Authorize(http, jwt, db, householdId, edit: false);
        if (error is not null) return error;

        // Optional date range, as yyyy-MM-dd. Without it, the newest 500 expenses are returned.
        var fromDate = ParseDate(from) ?? DateOnly.MinValue;
        var toDate = ParseDate(to) ?? DateOnly.MaxValue;

        await using var cmd = db.CreateCommand(
            @"select id, category_id, amount, expense_date, note, version
              from expenses
              where household_id = $1 and deleted_at is null
                and expense_date between $2 and $3
              order by expense_date desc, created_at desc
              limit 500");
        cmd.Parameters.AddWithValue(householdId);
        cmd.Parameters.AddWithValue(fromDate);
        cmd.Parameters.AddWithValue(toDate);

        var list = new List<object>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                id = reader.GetGuid(0),
                categoryId = reader.IsDBNull(1) ? null : (Guid?)reader.GetGuid(1),
                amount = reader.GetDecimal(2),
                expenseDate = reader.GetFieldValue<DateOnly>(3).ToString("yyyy-MM-dd"),
                note = reader.IsDBNull(4) ? null : reader.GetString(4),
                version = reader.GetInt32(5),
            });
        }
        return Results.Ok(list);
    }

    private static async Task<IResult> CreateExpense(
        Guid householdId, ExpenseRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (me, error) = await Authorize(http, jwt, db, householdId, edit: true);
        if (error is not null) return error;
        if (!ValidExpense(req.Amount, req.ExpenseDate, out var amount, out var date))
            return Results.BadRequest(new { error = "Amount must be above zero and the date must be yyyy-MM-dd." });

        var id = Guid.NewGuid();
        var note = Clean(req.Note);
        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        if (!await CategoryExists(conn, tx, householdId, req.CategoryId))
            return Results.BadRequest(new { error = "That category does not exist in this household." });

        await Sql.Exec(conn, tx,
            "insert into expenses (id, household_id, category_id, amount, expense_date, note, created_by) values ($1,$2,$3,$4,$5,$6,$7)",
            id, householdId, req.CategoryId, amount, date, note, me!.Value);
        await Sql.LogChange(conn, tx, householdId, "expense", id, "create",
            ExpensePayload(id, 1, req.CategoryId, amount, date, note), me.Value);
        await tx.CommitAsync();

        return Results.Json(new { id, version = 1 }, statusCode: StatusCodes.Status201Created);
    }

    private static async Task<IResult> UpdateExpense(
        Guid householdId, Guid id, ExpenseRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (me, error) = await Authorize(http, jwt, db, householdId, edit: true);
        if (error is not null) return error;
        if (!ValidExpense(req.Amount, req.ExpenseDate, out var amount, out var date))
            return Results.BadRequest(new { error = "Amount must be above zero and the date must be yyyy-MM-dd." });
        if (req.Version is null)
            return Results.BadRequest(new { error = "Send the version you are editing." });

        var note = Clean(req.Note);
        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        if (!await CategoryExists(conn, tx, householdId, req.CategoryId))
            return Results.BadRequest(new { error = "That category does not exist in this household." });

        var result = await Sql.Scalar(conn, tx,
            @"update expenses
              set category_id = $1, amount = $2, expense_date = $3, note = $4, version = version + 1, updated_at = now()
              where id = $5 and household_id = $6 and version = $7 and deleted_at is null
              returning version",
            req.CategoryId, amount, date, note, id, householdId, req.Version.Value);
        if (result is null)
            return Results.Conflict(new { error = "This expense was changed or deleted elsewhere. Refresh and try again." });

        var version = Convert.ToInt32(result);
        await Sql.LogChange(conn, tx, householdId, "expense", id, "update",
            ExpensePayload(id, version, req.CategoryId, amount, date, note), me!.Value);
        await tx.CommitAsync();

        return Results.Ok(new { id, version });
    }

    private static async Task<IResult> DeleteExpense(
        Guid householdId, Guid id, int? version, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (me, error) = await Authorize(http, jwt, db, householdId, edit: true);
        if (error is not null) return error;
        if (version is null)
            return Results.BadRequest(new { error = "Send the version you are deleting, as ?version=N." });

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        var result = await Sql.Scalar(conn, tx,
            @"update expenses
              set deleted_at = now(), version = version + 1, updated_at = now()
              where id = $1 and household_id = $2 and version = $3 and deleted_at is null
              returning version",
            id, householdId, version.Value);
        if (result is null)
            return Results.Conflict(new { error = "This expense was changed or deleted elsewhere. Refresh and try again." });

        var newVersion = Convert.ToInt32(result);
        await Sql.LogChange(conn, tx, householdId, "expense", id, "delete",
            new { id, version = newVersion, deleted = true }, me!.Value);
        await tx.CommitAsync();

        return Results.Ok(new { id, version = newVersion });
    }

    // ---- Change feed for the phone ----

    // The phone asks for changes after the last id it saw. The server returns them in order, with a next id to ask from.
    private static async Task<IResult> Changes(
        Guid householdId, long? after, int? limit, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (_, error) = await Authorize(http, jwt, db, householdId, edit: false);
        if (error is not null) return error;

        var since = after ?? 0;
        var max = Math.Clamp(limit ?? 200, 1, 500);

        await using var cmd = db.CreateCommand(
            @"select id, entity, entity_id, operation, payload::text, created_at
              from change_log
              where household_id = $1 and id > $2
              order by id
              limit $3");
        cmd.Parameters.AddWithValue(householdId);
        cmd.Parameters.AddWithValue(since);
        cmd.Parameters.AddWithValue(max);

        var list = new List<object>();
        var last = since;
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            last = reader.GetInt64(0);
            list.Add(new
            {
                id = last,
                entity = reader.GetString(1),
                entityId = reader.GetGuid(2),
                operation = reader.GetString(3),
                payload = reader.IsDBNull(4) ? null : JsonNode.Parse(reader.GetString(4)),
                createdAt = reader.GetDateTime(5),
            });
        }
        return Results.Ok(new { changes = list, nextAfter = last });
    }

    // ---- Sync push and conflicts ----

    // The phone sends its offline changes. Each one is applied only if the server still has the version the phone started from.
    // Otherwise it is kept in sync_conflicts, so nothing the phone wrote is lost.
    private static async Task<IResult> Sync(
        Guid householdId, List<SyncItem>? items, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (me, error) = await Authorize(http, jwt, db, householdId, edit: true);
        if (error is not null) return error;
        if (items is null || items.Count is 0 or > 200)
            return Results.BadRequest(new { error = "Send between 1 and 200 changes." });

        var results = new List<object>();
        foreach (var item in items)
        {
            var outcome = await ApplySyncItem(db, householdId, me!.Value, item);
            results.Add(new { entityId = item.EntityId, outcome });
        }
        return Results.Ok(new { results });
    }

    private static async Task<string> ApplySyncItem(NpgsqlDataSource db, Guid householdId, Guid actor, SyncItem item)
    {
        if (item.EntityId is not Guid id) return "invalid";
        var isExpense = item.Entity == "expense";
        if (!isExpense && item.Entity != "budget_category") return "invalid";
        var op = item.Operation;
        if (op is not ("create" or "update" or "delete")) return "invalid";
        if (op != "delete" && item.Data is not { ValueKind: JsonValueKind.Object }) return "invalid";
        if (op != "create" && item.BaseVersion is null) return "invalid";

        var table = isExpense ? "expenses" : "budget_categories";

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();

        int? serverVersion = null;
        var deleted = false;
        await using (var find = new NpgsqlCommand(
            $"select version, deleted_at is not null from {table} where id = $1 and household_id = $2 for update", conn, tx))
        {
            find.Parameters.AddWithValue(id);
            find.Parameters.AddWithValue(householdId);
            await using var reader = await find.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                serverVersion = reader.GetInt32(0);
                deleted = reader.GetBoolean(1);
            }
        }

        var isConflict = op == "create"
            ? serverVersion is not null
            : serverVersion is null || deleted || serverVersion != item.BaseVersion;

        if (isConflict)
        {
            await Sql.Exec(conn, tx,
                @"insert into sync_conflicts (household_id, entity, entity_id, client_version, server_version, client_data)
                  values ($1,$2,$3,$4,$5,$6::jsonb)",
                householdId, item.Entity, id, item.BaseVersion ?? 0, serverVersion ?? 0, item.Data?.GetRawText() ?? "{}");
            await tx.CommitAsync();
            return "conflict";
        }

        int version;
        object payload;
        if (!isExpense)
        {
            if (op == "delete")
            {
                version = Convert.ToInt32(await Sql.Scalar(conn, tx,
                    @"update budget_categories set deleted_at = now(), version = version + 1, updated_at = now()
                      where id = $1 and household_id = $2 returning version", id, householdId));
                payload = new { id, version, deleted = true };
            }
            else
            {
                var data = item.Data!.Value;
                if (!ValidCategory(Str(data, "name"), Dec(data, "monthlyLimit"), out var name, out var limit))
                    return "invalid";

                if (op == "create")
                {
                    await Sql.Exec(conn, tx,
                        "insert into budget_categories (id, household_id, name, monthly_limit, created_by) values ($1,$2,$3,$4,$5)",
                        id, householdId, name, limit, actor);
                    version = 1;
                }
                else
                {
                    version = Convert.ToInt32(await Sql.Scalar(conn, tx,
                        @"update budget_categories set name = $1, monthly_limit = $2, version = version + 1, updated_at = now()
                          where id = $3 and household_id = $4 returning version", name, limit, id, householdId));
                }
                payload = CategoryPayload(id, version, name, limit);
            }
        }
        else
        {
            if (op == "delete")
            {
                version = Convert.ToInt32(await Sql.Scalar(conn, tx,
                    @"update expenses set deleted_at = now(), version = version + 1, updated_at = now()
                      where id = $1 and household_id = $2 returning version", id, householdId));
                payload = new { id, version, deleted = true };
            }
            else
            {
                var data = item.Data!.Value;
                var categoryId = ParseGuid(Str(data, "categoryId"));
                if (!ValidExpense(Dec(data, "amount"), Str(data, "expenseDate"), out var amount, out var date))
                    return "invalid";
                var note = Clean(Str(data, "note"));
                if (!await CategoryExists(conn, tx, householdId, categoryId))
                    return "invalid";

                if (op == "create")
                {
                    await Sql.Exec(conn, tx,
                        "insert into expenses (id, household_id, category_id, amount, expense_date, note, created_by) values ($1,$2,$3,$4,$5,$6,$7)",
                        id, householdId, categoryId, amount, date, note, actor);
                    version = 1;
                }
                else
                {
                    version = Convert.ToInt32(await Sql.Scalar(conn, tx,
                        @"update expenses set category_id = $1, amount = $2, expense_date = $3, note = $4, version = version + 1, updated_at = now()
                          where id = $5 and household_id = $6 returning version", categoryId, amount, date, note, id, householdId));
                }
                payload = ExpensePayload(id, version, categoryId, amount, date, note);
            }
        }

        var operation = op!;
        await Sql.LogChange(conn, tx, householdId, item.Entity!, id, operation, payload, actor);
        await tx.CommitAsync();
        return "applied";
    }

    private static async Task<IResult> ListConflicts(
        Guid householdId, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (_, error) = await Authorize(http, jwt, db, householdId, edit: true);
        if (error is not null) return error;

        await using var cmd = db.CreateCommand(
            @"select id, entity, entity_id, client_version, server_version, client_data::text, created_at
              from sync_conflicts
              where household_id = $1 and status = 'open'
              order by created_at");
        cmd.Parameters.AddWithValue(householdId);

        var list = new List<object>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                id = reader.GetGuid(0),
                entity = reader.GetString(1),
                entityId = reader.GetGuid(2),
                clientVersion = reader.GetInt32(3),
                serverVersion = reader.GetInt32(4),
                clientData = JsonNode.Parse(reader.GetString(5)),
                createdAt = reader.GetDateTime(6),
            });
        }
        return Results.Ok(list);
    }

    // The person picks which version to keep: "mine" (the phone's change) or "server" (the change already saved).
    // "mine" is written as a new version, so every phone receives it through the change feed.
    private static async Task<IResult> ResolveConflict(
        Guid householdId, Guid id, ResolveRequest req, HttpContext http, JwtOptions jwt, NpgsqlDataSource db)
    {
        var (me, error) = await Authorize(http, jwt, db, householdId, edit: true);
        if (error is not null) return error;

        var keep = (req.Keep ?? "").Trim().ToLowerInvariant();
        if (keep is not ("mine" or "server"))
            return Results.BadRequest(new { error = "Choose keep: \"mine\" or \"server\"." });

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();

        string entity;
        Guid entityId;
        string clientData;
        await using (var find = new NpgsqlCommand(
            "select entity, entity_id, client_data::text from sync_conflicts where id = $1 and household_id = $2 and status = 'open' for update",
            conn, tx))
        {
            find.Parameters.AddWithValue(id);
            find.Parameters.AddWithValue(householdId);
            await using var reader = await find.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
                return Results.NotFound();
            entity = reader.GetString(0);
            entityId = reader.GetGuid(1);
            clientData = reader.GetString(2);
        }

        if (keep == "mine" &&
            !await ApplyClientVersion(conn, tx, householdId, me!.Value, entity, entityId, clientData))
        {
            return Results.Conflict(new { error = "That item no longer exists, or the saved values are not valid. Enter it again." });
        }

        await Sql.Exec(conn, tx, "update sync_conflicts set status = 'resolved' where id = $1", id);
        await tx.CommitAsync();

        return Results.Ok(new { id, status = "resolved", kept = keep });
    }

    // Writes the phone's values over the current row as a new version. Also restores the row if it was deleted.
    private static async Task<bool> ApplyClientVersion(
        NpgsqlConnection conn, NpgsqlTransaction tx, Guid householdId, Guid actor,
        string entity, Guid id, string clientData)
    {
        using var doc = JsonDocument.Parse(clientData);
        var data = doc.RootElement;

        if (entity == "budget_category")
        {
            if (!ValidCategory(Str(data, "name"), Dec(data, "monthlyLimit"), out var name, out var limit))
                return false;

            var version = await Sql.Scalar(conn, tx,
                @"update budget_categories set name = $1, monthly_limit = $2, deleted_at = null, version = version + 1, updated_at = now()
                  where id = $3 and household_id = $4 returning version", name, limit, id, householdId);
            if (version is null)
                return false;

            await Sql.LogChange(conn, tx, householdId, entity, id, "update",
                CategoryPayload(id, Convert.ToInt32(version), name, limit), actor);
            return true;
        }

        if (entity == "expense")
        {
            var categoryId = ParseGuid(Str(data, "categoryId"));
            if (!ValidExpense(Dec(data, "amount"), Str(data, "expenseDate"), out var amount, out var date))
                return false;
            var note = Clean(Str(data, "note"));
            if (!await CategoryExists(conn, tx, householdId, categoryId))
                return false;

            var version = await Sql.Scalar(conn, tx,
                @"update expenses set category_id = $1, amount = $2, expense_date = $3, note = $4, deleted_at = null,
                  version = version + 1, updated_at = now()
                  where id = $5 and household_id = $6 returning version", categoryId, amount, date, note, id, householdId);
            if (version is null)
                return false;

            await Sql.LogChange(conn, tx, householdId, entity, id, "update",
                ExpensePayload(id, Convert.ToInt32(version), categoryId, amount, date, note), actor);
            return true;
        }

        return false;
    }

    // ---- Shared helpers ----

    // Returns the caller's id if they may use this household's budget, otherwise the error to send back.
    private static async Task<(Guid? UserId, IResult? Error)> Authorize(
        HttpContext http, JwtOptions jwt, NpgsqlDataSource db, Guid householdId, bool edit)
    {
        var me = CurrentUser.From(http, jwt);
        if (me is null) return (null, Results.Unauthorized());
        if (!await Access.CanAsync(db, householdId, me.Value, Module, edit)) return (null, Results.NotFound());
        return (me, null);
    }

    private static bool ValidCategory(string? name, decimal? monthlyLimit, out string cleanName, out decimal limit)
    {
        cleanName = (name ?? "").Trim();
        limit = monthlyLimit ?? 0;
        return cleanName.Length is >= 1 and <= 60 && limit > 0;
    }

    private static bool ValidExpense(decimal? amount, string? dateText, out decimal value, out DateOnly date)
    {
        value = amount ?? 0;
        date = default;
        if (value <= 0) return false;
        return DateOnly.TryParseExact(dateText, "yyyy-MM-dd", out date);
    }

    private static DateOnly? ParseDate(string? text) =>
        DateOnly.TryParseExact(text, "yyyy-MM-dd", out var date) ? date : null;

    private static async Task<bool> CategoryExists(
        NpgsqlConnection conn, NpgsqlTransaction tx, Guid householdId, Guid? categoryId)
    {
        if (categoryId is null) return true;
        return await Sql.Scalar(conn, tx,
            "select 1 from budget_categories where id = $1 and household_id = $2 and deleted_at is null",
            categoryId.Value, householdId) is not null;
    }

    private static object CategoryPayload(Guid id, int version, string name, decimal limit) =>
        new { id, version, name, monthlyLimit = limit };

    private static object ExpensePayload(Guid id, int version, Guid? categoryId, decimal amount, DateOnly date, string? note) =>
        new { id, version, categoryId, amount, expenseDate = date.ToString("yyyy-MM-dd"), note };

    private static string? Clean(string? text)
    {
        var trimmed = text?.Trim();
        return string.IsNullOrEmpty(trimmed) ? null : trimmed[..Math.Min(trimmed.Length, 500)];
    }

    private static string? Str(JsonElement data, string property) =>
        data.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static decimal? Dec(JsonElement data, string property) =>
        data.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var number)
            ? (decimal?)number
            : null;

    private static Guid? ParseGuid(string? text) =>
        Guid.TryParse(text, out var id) ? (Guid?)id : null;
}
