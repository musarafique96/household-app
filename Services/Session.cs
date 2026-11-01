using HouseholdApp.Data;
using HouseholdApp.Models;

namespace HouseholdApp.Services;

// Tracks which household member is using the app on this phone.
public static class Session
{
    private const string UserIdKey = "current_user_id";

    public static UserAccount? Current { get; private set; }

    public static async Task RestoreAsync(LocalDb db)
    {
        var savedId = Preferences.Default.Get(UserIdKey, 0);
        if (savedId == 0) return;

        var users = await db.GetUsersAsync();
        Current = users.FirstOrDefault(u => u.Id == savedId);
    }

    public static void SetCurrent(UserAccount user)
    {
        Current = user;
        Preferences.Default.Set(UserIdKey, user.Id);
    }

    // Shows amounts in the current user's own currency.
    public static string Money(decimal amount) =>
        Current is null ? amount.ToString("N2") : $"{amount:N2} {Current.CurrencyCode}";
}
