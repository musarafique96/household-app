using System.Globalization;
using HouseholdApp.Models;
using HouseholdApp.Services;
using Microsoft.Maui.Graphics;

namespace HouseholdApp.Pages;

// One row on the budget and dashboard screens.
public class CategoryRow
{
    public string Name { get; init; } = "";
    public decimal Spent { get; init; }
    public decimal Limit { get; init; }
    public string Text { get; init; } = "";
    public double Progress { get; init; }
    public Color BarColor { get; init; } = Color.FromArgb("#512BD4");

    public static List<CategoryRow> Build(List<BudgetCategory> categories, List<Expense> expenses)
    {
        return categories.Select(c =>
        {
            var spent = expenses.Where(e => e.CategoryId == c.Id).Sum(e => e.Amount);
            var over = c.MonthlyLimit > 0 && spent > c.MonthlyLimit;
            return new CategoryRow
            {
                Name = c.Name,
                Spent = spent,
                Limit = c.MonthlyLimit,
                Text = $"{Session.Money(spent)} of {Session.Money(c.MonthlyLimit)}" + (over ? " (over)" : ""),
                Progress = c.MonthlyLimit <= 0 ? 0 : (double)Math.Min(1m, spent / c.MonthlyLimit),
                BarColor = over ? Colors.Crimson : Color.FromArgb("#512BD4"),
            };
        }).ToList();
    }
}

public partial class BudgetPage : ContentPage
{
    private readonly DateTime _month = new(DateTime.Today.Year, DateTime.Today.Month, 1);

    public BudgetPage()
    {
        InitializeComponent();
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await RefreshAsync();
    }

    private async Task RefreshAsync()
    {
        await App.Ready;
        MonthLabel.Text = _month.ToString("MMMM yyyy");

        if (Session.Current is null)
        {
            StatusLabel.Text = "Choose an account in the Account tab first.";
            CategoryList.ItemsSource = null;
            return;
        }

        var user = Session.Current;
        var categories = await App.Db.GetCategoriesAsync(user.Id);
        var expenses = await App.Db.GetExpensesAsync(user.Id, _month);

        CategoryPicker.ItemsSource = categories;
        CategoryList.ItemsSource = CategoryRow.Build(categories, expenses);
    }

    private async void OnAddCategoryClicked(object? sender, EventArgs e)
    {
        if (Session.Current is null) return;

        var name = CategoryNameEntry.Text?.Trim();
        if (string.IsNullOrEmpty(name) ||
            !decimal.TryParse(CategoryLimitEntry.Text, NumberStyles.Number, CultureInfo.CurrentCulture, out var limit) ||
            limit <= 0)
        {
            StatusLabel.Text = "Enter a category name and a limit above zero.";
            return;
        }

        await App.Db.SaveCategoryAsync(new BudgetCategory
        {
            UserId = Session.Current.Id,
            Name = name,
            MonthlyLimit = limit,
        });

        CategoryNameEntry.Text = "";
        CategoryLimitEntry.Text = "";
        StatusLabel.Text = "Category added.";
        await RefreshAsync();
    }

    private async void OnAddExpenseClicked(object? sender, EventArgs e)
    {
        if (Session.Current is null) return;

        if (CategoryPicker.SelectedItem is not BudgetCategory category)
        {
            StatusLabel.Text = "Choose a category.";
            return;
        }

        if (!decimal.TryParse(AmountEntry.Text, NumberStyles.Number, CultureInfo.CurrentCulture, out var amount) ||
            amount <= 0)
        {
            StatusLabel.Text = "Enter an amount above zero.";
            return;
        }

        await App.Db.SaveExpenseAsync(new Expense
        {
            UserId = Session.Current.Id,
            CategoryId = category.Id,
            Amount = amount,
            Note = NoteEntry.Text ?? "",
            Date = DateTime.Today,
        });

        AmountEntry.Text = "";
        NoteEntry.Text = "";
        StatusLabel.Text = "Expense saved.";
        await RefreshAsync();
    }
}
