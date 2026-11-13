using Npgsql;

namespace Gharbaar.Api.Data;

// Who may do what in a household. A head can do everything. A member needs a permission granted by a head.
public static class Access
{
    // "head", "member", or null when the user is not an active member.
    public static async Task<string?> RoleAsync(NpgsqlDataSource db, Guid householdId, Guid userId)
    {
        await using var conn = await db.OpenConnectionAsync();
        return await Sql.Scalar(conn, null,
            "select role from household_members where household_id = $1 and user_id = $2 and left_at is null",
            householdId, userId) as string;
    }

    public static async Task<bool> CanAsync(NpgsqlDataSource db, Guid householdId, Guid userId, string module, bool edit)
    {
        var role = await RoleAsync(db, householdId, userId);
        if (role is null) return false;
        if (role == "head") return true;

        // The column name comes only from this method, never from the user.
        var column = edit ? "can_edit" : "can_view";
        await using var conn = await db.OpenConnectionAsync();
        var granted = await Sql.Scalar(conn, null,
            $"select {column} from member_permissions where household_id = $1 and user_id = $2 and module = $3",
            householdId, userId, module);
        return granted is true;
    }
}
