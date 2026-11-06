import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'data/db.dart';
import 'data/models.dart';
import 'screens/account_screen.dart';
import 'screens/budget_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/split_screen.dart';
import 'session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load();
  await Db.instance.ensureDefaultAdmin();
  Session.restore();
  runApp(const HouseholdApp());
}

class HouseholdApp extends StatelessWidget {
  const HouseholdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Household',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(dark: false),
          darkTheme: buildTheme(dark: true),
          themeMode: mode,
          // Sign-in page until someone is signed in, then the app.
          home: ValueListenableBuilder<AppUser?>(
            valueListenable: Session.current,
            builder: (context, user, _) =>
                user == null ? const LoginScreen() : const HomeShell(),
          ),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _openTab(int tab) => setState(() => _index = tab);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: Session.current,
      builder: (context, user, _) {
        // Keying by user id makes each screen reload when the account changes.
        final id = user?.id ?? 0;
        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              HomeScreen(key: ValueKey('home-$id'), onOpenTab: _openTab),
              const ExpensesScreen(key: ValueKey('expenses')),
              SplitScreen(key: ValueKey('split-$id')),
              BudgetScreen(key: ValueKey('budget-$id')),
              const AccountScreen(key: ValueKey('account')),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _openTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.wallet_outlined),
                selectedIcon: Icon(Icons.wallet_rounded),
                label: 'Expenses',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_outlined),
                selectedIcon: Icon(Icons.groups_rounded),
                label: 'Split',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Budget',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Accounts',
              ),
            ],
          ),
        );
      },
    );
  }
}
