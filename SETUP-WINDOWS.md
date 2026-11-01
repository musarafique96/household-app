# Windows setup: first run on Android

The code in this folder is a set of source files. Visual Studio creates the project shell (icons, fonts, splash screen), and these files go into it.

## 1. Install Visual Studio 2022
1. Download Visual Studio 2022 Community (free) from visualstudio.microsoft.com.
2. In the installer, select the **.NET Multi-platform App UI development** workload.
3. Under individual components, make sure **Android SDK setup** (or the Android emulator) is checked.

## 2. Create the project
1. Open Visual Studio, choose **Create a new project**, then **.NET MAUI App**.
2. Name it **HouseholdApp**, and use the same name for the solution.
3. Let it finish creating the project, then run it once with the Android emulator to confirm the template works.

## 3. Add the packages
In Visual Studio, open **Tools > NuGet Package Manager > Manage NuGet Packages for Solution** and install:
- `sqlite-net-pcl`
- `SQLitePCLRaw.bundle_green`

## 4. Copy the files
Copy these from this folder into the new project, replacing the template files when asked:
- `App.xaml`, `App.xaml.cs`
- `AppShell.xaml`, `AppShell.xaml.cs`
- `MauiProgram.cs`
- `Models/`, `Data/`, `Services/`, `Pages/` (whole folders)

Do **not** copy `HouseholdApp.csproj`. The template's project file already has the icon and font settings, so keep that one. Delete the template's `MainPage.xaml` and `MainPage.xaml.cs` if they're still there.

## 5. Icons
`AppShell.xaml` uses icon files named `icon_wallet.png`, `icon_chart.png`, `icon_split.png`, and `icon_person.png`. Either add those PNG files to the `Resources/Images` folder, or delete the `Icon=` lines and the tabs will show text only. This is a placeholder until the real icons are chosen.

## 6. Run it
Pick **Android Emulator** or your phone (with USB debugging on) in the toolbar, then press **Run**.

First use:
1. Open the **Account** tab, create your account with your currency code (for example SAR or PKR), then pick it and press **Use this account**.
2. Open **Budget**, add a category such as Groceries with a monthly limit, then add an expense.
3. Check **Dashboard** and **Split**.

## What works in this version
- Account per household member, each with their own currency
- Budget categories, expenses, and monthly progress bars
- Dashboard with totals, category bars, savings tips, and a 6-month trend
- Split / Qattah: shared expenses, split equally, with who owes whom

## Not yet built
- Reminders linked to the calendar (needs platform-specific code)
- Monthly grocery list
- Daily cooking suggestions from a recipe list
- Dark mode and a fuller visual design
- Online sync (later)

## iPhone
iPhone builds need a Mac with Xcode. Once the Android version runs, we can either use a Mac you have access to, or a cloud build service that builds for iOS from Windows.
