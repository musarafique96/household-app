using HouseholdApp.Data;
using HouseholdApp.Services;

namespace HouseholdApp;

public partial class App : Application
{
    // One database connection for the whole app. Later an online backend
    // can replace this without changing the pages.
    public static LocalDb Db { get; } = new LocalDb(LocalDb.DefaultPath);

    // Pages await this before reading data.
    public static Task Ready { get; private set; } = Task.CompletedTask;

    public App()
    {
        InitializeComponent();
        Ready = InitAsync();
    }

    private static async Task InitAsync()
    {
        await Db.InitAsync();
        await Session.RestoreAsync(Db);
    }

    protected override Window CreateWindow(IActivationState? activationState) =>
        new Window(new AppShell());
}
