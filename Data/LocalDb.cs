using SQLite;
using HouseholdApp.Models;

namespace HouseholdApp.Data;

// Offline-first local database. Later, the online backend (e.g. Supabase) can
// implement the same methods, so the screens don't need to change.
public class LocalDb
{
    private readonly SQLiteAsyncConnection _db;

    public LocalDb(string dbPath)
    {
        _db = new SQLiteAsyncConnection(dbPath);
    }

    public static string DefaultPath =>
        Path.Combine(FileSystem.AppDataDirectory, "household.db3");

    public async Task InitAsync()
    {
        await _db.CreateTablesAsync<UserAccount, BudgetCategory, Expense,
            SharedExpense, Reminder, GroceryItem, Recipe>();
    }

    // Users
    public Task<List<UserAccount>> GetUsersAsync() => _db.Table<UserAccount>().ToListAsync();
    public Task<int> SaveUserAsync(UserAccount u) =>
        u.Id == 0 ? _db.InsertAsync(u) : _db.UpdateAsync(u);

    // Budget
    public Task<List<BudgetCategory>> GetCategoriesAsync(int userId) =>
        _db.Table<BudgetCategory>().Where(c => c.UserId == userId).ToListAsync();
    public Task<int> SaveCategoryAsync(BudgetCategory c) =>
        c.Id == 0 ? _db.InsertAsync(c) : _db.UpdateAsync(c);

    // Expenses for one month
    public Task<List<Expense>> GetExpensesAsync(int userId, DateTime monthStart)
    {
        var monthEnd = monthStart.AddMonths(1);
        return _db.Table<Expense>()
            .Where(e => e.UserId == userId && e.Date >= monthStart && e.Date < monthEnd)
            .ToListAsync();
    }
    public Task<int> SaveExpenseAsync(Expense e) =>
        e.Id == 0 ? _db.InsertAsync(e) : _db.UpdateAsync(e);

    // Split / Qattah
    public Task<List<SharedExpense>> GetAllSharedAsync() =>
        _db.Table<SharedExpense>().ToListAsync();
    public Task<int> SaveSharedAsync(SharedExpense s) =>
        s.Id == 0 ? _db.InsertAsync(s) : _db.UpdateAsync(s);

    // Reminders
    public Task<List<Reminder>> GetRemindersAsync(int userId) =>
        _db.Table<Reminder>().Where(r => r.UserId == userId).ToListAsync();
    public Task<int> SaveReminderAsync(Reminder r) =>
        r.Id == 0 ? _db.InsertAsync(r) : _db.UpdateAsync(r);

    // Groceries
    public Task<List<GroceryItem>> GetGroceriesAsync(int userId, string month) =>
        _db.Table<GroceryItem>().Where(g => g.UserId == userId && g.Month == month).ToListAsync();
    public Task<int> SaveGroceryAsync(GroceryItem g) =>
        g.Id == 0 ? _db.InsertAsync(g) : _db.UpdateAsync(g);

    // Recipes
    public Task<List<Recipe>> GetRecipesAsync() => _db.Table<Recipe>().ToListAsync();
    public Task<int> SaveRecipeAsync(Recipe r) =>
        r.Id == 0 ? _db.InsertAsync(r) : _db.UpdateAsync(r);
}
