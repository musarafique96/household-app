using System.Globalization;
using HouseholdApp.Models;

namespace HouseholdApp.Pages;

public partial class SplitPage : ContentPage
{
    public SplitPage()
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
        var users = await App.Db.GetUsersAsync();
        var names = users.ToDictionary(u => u.Id, u => u.DisplayName);
        string NameOf(int id) => names.TryGetValue(id, out var n) ? n : "Unknown";

        PayerPicker.ItemsSource = users;

        var shared = await App.Db.GetAllSharedAsync();

        ExpenseLabel.Text = shared.Count == 0
            ? "No shared expenses yet."
            : string.Join("\n", shared
                .OrderByDescending(s => s.Date)
                .Select(s => $"{s.Date:d}  {s.Title}: {s.Amount:N2}, paid by {NameOf(s.PaidByUserId)}"));

        // owes[(debtor, creditor)] = total the debtor owes the creditor
        var owes = new Dictionary<(int From, int To), decimal>();
        foreach (var s in shared)
        {
            var ids = s.ParticipantIds
                .Split(',', StringSplitOptions.RemoveEmptyEntries)
                .Select(int.Parse)
                .ToList();
            if (ids.Count == 0) continue;

            var share = s.Amount / ids.Count;
            foreach (var id in ids.Where(id => id != s.PaidByUserId))
            {
                var key = (id, s.PaidByUserId);
                owes[key] = owes.GetValueOrDefault(key) + share;
            }
        }

        // Net the two directions so each pair shows one line.
        var lines = new List<string>();
        foreach (var ((from, to), amount) in owes)
        {
            var net = amount - owes.GetValueOrDefault((to, from));
            if (net > 0)
                lines.Add($"{NameOf(from)} owes {NameOf(to)} {net:N2}");
        }

        BalanceLabel.Text = lines.Count == 0 ? "Everyone is square." : string.Join("\n", lines);
    }

    private async void OnAddSharedClicked(object? sender, EventArgs e)
    {
        if (Session.Current is null)
        {
            StatusLabel.Text = "Choose an account in the Account tab first.";
            return;
        }

        var title = SharedTitle.Text?.Trim();
        if (string.IsNullOrEmpty(title))
        {
            StatusLabel.Text = "Enter what the expense was for.";
            return;
        }

        if (!decimal.TryParse(SharedAmount.Text, NumberStyles.Number, CultureInfo.CurrentCulture, out var amount) ||
            amount <= 0)
        {
            StatusLabel.Text = "Enter an amount above zero.";
            return;
        }

        if (PayerPicker.SelectedItem is not UserAccount payer)
        {
            StatusLabel.Text = "Choose who paid.";
            return;
        }

        var users = await App.Db.GetUsersAsync();
        await App.Db.SaveSharedAsync(new SharedExpense
        {
            CreatedByUserId = Session.Current.Id,
            Title = title,
            Amount = amount,
            PaidByUserId = payer.Id,
            ParticipantIds = string.Join(",", users.Select(u => u.Id)),
            Date = DateTime.Today,
        });

        SharedTitle.Text = "";
        SharedAmount.Text = "";
        StatusLabel.Text = "Saved.";
        await RefreshAsync();
    }
}
