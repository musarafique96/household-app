using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace Gharbaar.Api.Data;

// Small helpers so each endpoint can run its SQL inside one transaction.
public static class Sql
{
    public static async Task Exec(NpgsqlConnection conn, NpgsqlTransaction tx, string sql, params object?[] args)
    {
        await using var cmd = new NpgsqlCommand(sql, conn, tx);
        foreach (var arg in args)
            cmd.Parameters.AddWithValue(arg ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync();
    }

    public static async Task<object?> Scalar(NpgsqlConnection conn, NpgsqlTransaction? tx, string sql, params object?[] args)
    {
        await using var cmd = new NpgsqlCommand(sql, conn, tx);
        foreach (var arg in args)
            cmd.Parameters.AddWithValue(arg ?? DBNull.Value);
        return await cmd.ExecuteScalarAsync();
    }

    // Every change to a household's data is written to change_log, in the same transaction as the change.
    // The payload is the full row after the change, so the phone can apply it without asking again.
    public static async Task LogChange(
        NpgsqlConnection conn, NpgsqlTransaction tx, Guid householdId,
        string entity, Guid entityId, string operation, object? payload, Guid actor)
    {
        await using var cmd = new NpgsqlCommand(
            "insert into change_log (household_id, entity, entity_id, operation, payload, actor) values ($1,$2,$3,$4,$5,$6)",
            conn, tx);
        cmd.Parameters.AddWithValue(householdId);
        cmd.Parameters.AddWithValue(entity);
        cmd.Parameters.AddWithValue(entityId);
        cmd.Parameters.AddWithValue(operation);
        cmd.Parameters.Add(new NpgsqlParameter
        {
            NpgsqlDbType = NpgsqlDbType.Jsonb,
            Value = payload is null ? DBNull.Value : JsonSerializer.Serialize(payload),
        });
        cmd.Parameters.AddWithValue(actor);
        await cmd.ExecuteNonQueryAsync();
    }
}
