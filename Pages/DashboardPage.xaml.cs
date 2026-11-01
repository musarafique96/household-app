using HouseholdApp.Services;
using Microsoft.Maui.Controls;
using Microsoft.Maui.Graphics;

namespace HouseholdApp.Pages;

public partial class DashboardPage : ContentPage
{
    public DashboardPage()
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

        if (Session.Current is null)
        {
            SummaryLabel.Text = "Choose an account in the Account tab first.";
            RemainingLabel.Text = "";
            TipsLabel.Text = "";
            return;
        }

        var user = Session.Current;
        var month = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);

        var categories = await App.Db.GetCategoriesAsync(user.Id);
        var expenses = await App.Db.GetExpensesAsync(user.Id, month);
        var rows = CategoryRow.Build(categories, expenses);

        var spent = expenses.Sum(e => e.Amount);
        var budget = categories.Sum(c => c.MonthlyLimit);
        SummaryLabel.Text = $"Spent {Session.Money(spent)} of {Session.Money(budget)}";
        RemainingLabel.Text = budget >= spent
            ? $"{Session.Money(budget - spent)} left"
            : $"{Session.Money(spent - budget)} over budget";

        // Category bars, reusing the template defined in XAML.
        CategoryStack.Children.Clear();
        var template = (DataTemplate)CategoryStack.Resources["CategoryTemplate"];
        foreach (var row in rows)
        {
            var view = (View)template.CreateContent();
            view.BindingContext = row;
            CategoryStack.Children.Add(view);
        }

        TipsLabel.Text = BuildTips(rows);
        await BuildTrendAsync(user.Id, month);
    }

    private static string BuildTips(List<CategoryRow> rows)
    {
        var tips = new List<string>();

        foreach (var r in rows.Where(r => r.Limit > 0 && r.Spent > r.Limit))
            tips.Add($"{r.Name} is over its limit. Cutting it back would help most.");

        var biggest = rows.OrderByDescending(r => r.Spent).FirstOrDefault();
        if (biggest is not null && biggest.Spent > 0)
            tips.Add($"{biggest.Name} is your biggest spend this month ({Session.Money(biggest.Spent)}).");

        var nearLimit = rows.Where(r => r.Limit > 0 && r.Spent >= r.Limit * 0.8m && r.Spent <= r.Limit);
        foreach (var r in nearLimit)
            tips.Add($"{r.Name} is above 80% of its limit. Watch it for the rest of the month.");

        return tips.Count == 0
            ? "Nothing stands out yet. Add expenses to see suggestions."
            : string.Join("\n", tips);
    }

    private async Task BuildTrendAsync(int userId, DateTime currentMonth)
    {
        var trend = new List<(string Month, decimal Total)>();
        for (int i = 5; i >= 0; i--)
        {
            var m = currentMonth.AddMonths(-i);
            var list = await App.Db.GetExpensesAsync(userId, m);
            trend.Add((m.ToString("MMM yyyy"), list.Sum(e => e.Amount)));
        }

        var max = trend.Max(t => t.Total);
        TrendStack.Children.Clear();
        foreach (var t in trend)
        {
            var bar = new ProgressBar
            {
                Progress = max <= 0 ? 0 : (double)(t.Total / max),
                ProgressColor = Color.FromArgb("#512BD4"),
            };
            TrendStack.Children.Add(new Label
            {
                Text = $"{t.Month}: {Session.Money(t.Total)}",
                TextColor = Color.FromArgb("#6B6880"),
                FontSize = 13,
            });
            TrendStack.Children.Add(bar);
        }
    }
}
