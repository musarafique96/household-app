# Household App (first foundation)

Offline-first .NET MAUI app for Android and iPhone.

## What's here so far
- `HouseholdApp.csproj`: project file (Android and iOS targets)
- `MauiProgram.cs`: app startup and dependency injection
- `Models/Models.cs`: data models for users (with per-account currency), budget, expenses, shared expenses (Split/Qattah), reminders, groceries, and recipes
- `Data/LocalDb.cs`: local SQLite database. Each screen calls this layer, so moving to an online backend later only changes this file.

Not yet built: the screens (App.xaml, pages, dashboard, UI styling), reminders-to-calendar, and the recipe and grocery logic. These come next.

## Build requirements
- **Android:** Windows or Mac with Visual Studio 2022 (17.8 or later) and the ".NET MAUI" workload.
- **iPhone:** a Mac with Xcode installed. iOS apps can only be built on a Mac.
- Check the .NET version in the `.csproj` against what your Visual Studio offers, and update it if needed.

## Next steps
1. Add `App.xaml`, `AppShell`, and the tab pages (Budget, Dashboard, Split, Reminders).
2. Add the account picker and per-user currency formatting.
3. Add the Dashboard charts and the Savings suggestions.
