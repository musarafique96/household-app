using HouseholdApp.Models;
using HouseholdApp.Services;

namespace HouseholdApp.Pages;

public partial class AccountPage : ContentPage
{
    public AccountPage()
    {
        InitializeComponent();
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await LoadUsersAsync();
    }

    private async Task LoadUsersAsync()
    {
        await App.Ready;
        var users = await App.Db.GetUsersAsync();
        UserPicker.ItemsSource = users;
        if (Session.Current is not null)
            UserPicker.SelectedItem = users.FirstOrDefault(u => u.Id == Session.Current.Id);
    }

    private async void OnCreateClicked(object? sender, EventArgs e)
    {
        var name = NameEntry.Text?.Trim();
        if (string.IsNullOrEmpty(name))
        {
            StatusLabel.Text = "Enter a name.";
            return;
        }

        var code = string.IsNullOrWhiteSpace(CurrencyEntry.Text)
            ? "SAR"
            : CurrencyEntry.Text.Trim().ToUpperInvariant();

        var user = new UserAccount { DisplayName = name, CurrencyCode = code };
        await App.Db.SaveUserAsync(user);

        NameEntry.Text = "";
        StatusLabel.Text = $"Created {name} ({code}).";
        await LoadUsersAsync();
    }

    private void OnUseClicked(object? sender, EventArgs e)
    {
        if (UserPicker.SelectedItem is UserAccount user)
        {
            Session.SetCurrent(user);
            StatusLabel.Text = $"Using {user.DisplayName}.";
        }
        else
        {
            StatusLabel.Text = "Select an account first.";
        }
    }
}
