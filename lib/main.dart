import 'package:flutter/material.dart';

import 'data/models.dart';
import 'screens/account_screen.dart';
import 'screens/budget_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/split_screen.dart';
import 'session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Session.restore();
  runApp(const HouseholdApp());
}

class HouseholdApp extends StatelessWidget {
  const HouseholdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Household',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF512BD4),
        useMaterial3: true,
      ),
      home: const HomeShell(),
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
              const AccountScreen(key: ValueKey('account')),
              BudgetScreen(key: ValueKey('budget-$id')),
              DashboardScreen(key: ValueKey('dashboard-$id')),
              SplitScreen(key: ValueKey('split-$id')),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Account',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Budget',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_outlined),
                selectedIcon: Icon(Icons.groups),
                label: 'Split',
              ),
            ],
          ),
        );
      },
    );
  }
}
