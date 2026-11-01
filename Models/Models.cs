using SQLite;

namespace HouseholdApp.Models;

// Each person in the household has their own account. Currency is per account,
// so every amount a user sees is shown in their own currency.
public class UserAccount
{
    [PrimaryKey, AutoIncrement]
    public int Id { get; set; }
    public string DisplayName { get; set; } = "";
    public string CurrencyCode { get; set; } = "SAR"; // ISO 4217, e.g. SAR, PKR, USD
    public DateTime CreatedUtc { get; set; } = DateTime.UtcNow;
}

public class BudgetCategory
{
    [PrimaryKey, AutoIncrement]
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Name { get; set; } = "";
    public decimal MonthlyLimit { get; set; }
}

public class Expense
{
    [PrimaryKey, AutoIncrement]
    public int Id { get; set; }
    public int UserId { get; set; }
    public int? CategoryId { get; set; }
    public decimal Amount { get; set; }
    public string Note { get; set; } = "";
    public DateTime Date { get; set; } = DateTime.Today;
}

// A shared expense (Split / Qattah). Paid by one person, owed by others.
public class SharedExpense
{
    [PrimaryKey, AutoIncrement]
    public int Id { get; set; }
    public int CreatedByUserId { get; set; }
    public string Title { get; set; } = "";
    public decimal Amount { get; set; }
    public int PaidByUserId { get; set; }
    public string ParticipantIds { get; set; } = ""; // comma-separated user ids, for offline use
    public DateTime Date { get; set; } = DateTime.Today;
}

public class Reminder
{
    [PrimaryKey, AutoIncrement]
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Title { get; set; } = "";
    public DateTime DueLocal { get; set; }
    public bool AddedToCalendar { get; set; }
}

public class GroceryItem
{
    [PrimaryKey, AutoIncrement]
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Name { get; set; } = "";
    public decimal Quantity { get; set; } = 1;
    public decimal EstimatedPrice { get; set; }
    public bool Bought { get; set; }
    public string Month { get; set; } = DateTime.Today.ToString("yyyy-MM");
}

public class Recipe
{
    [PrimaryKey, AutoIncrement]
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Ingredients { get; set; } = ""; // comma-separated
    public string Steps { get; set; } = "";
}
