import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'reports_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final features = <_Feature>[
      _Feature('Reports', 'Download & share', Icons.bar_chart_rounded, AppColors.primary,
          'Monthly and yearly reports you can download and share.',
          page: (_) => const ReportsScreen()),
      _Feature('Recurring', 'Auto-add expenses', Icons.event_repeat_rounded, AppColors.pink,
          'Rent, subscriptions, and bills that are added automatically.'),
      _Feature('Receipts', 'Scan & attach', Icons.photo_camera_rounded, AppColors.primary,
          'Attach a photo of a receipt to any expense.'),
      _Feature('Export', 'PDF / Excel', Icons.file_download_rounded, AppColors.green,
          'Export your expenses and reports to PDF or Excel.'),
      _Feature('Currency', 'Multi-currency', Icons.sync_alt_rounded, AppColors.primary,
          'Track expenses in more than one currency.'),
      _Feature('Reminders', 'Bill & settlement alerts', Icons.notifications_rounded,
          AppColors.amber, 'Reminders for bills and for settling up with friends.'),
      _Feature('Backup & Sync', 'Keep data safe', Icons.cloud_done_rounded, AppColors.blue,
          'Back up your data and sync it online.'),
    ];

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
                const SizedBox(width: 4),
                const Text('More Features',
                    style: TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.3,
                  children: [
                    for (final f in features)
                      SoftCard(
                        onTap: () => _open(context, f),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconBubble(icon: f.icon, color: f.color),
                            const SizedBox(height: 10),
                            Text(f.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                            Text(f.subtitle,
                                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SoftCard(
                  onTap: () => _pickTheme(context),
                  child: const Row(
                    children: [
                      IconBubble(icon: Icons.dark_mode_rounded, color: AppColors.deep),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Dark Mode',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            Text('Switch theme',
                                style: TextStyle(color: AppColors.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  onTap: () => _open(
                    context,
                    const _Feature('Settings', '', Icons.settings_rounded, AppColors.muted,
                        'App settings will appear here.'),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.settings_rounded, color: AppColors.muted),
                      SizedBox(width: 12),
                      Expanded(child: Text('Settings', style: TextStyle(fontWeight: FontWeight.w700))),
                      Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, _Feature f) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: f.page ?? (_) => _FeaturePage(feature: f),
    ));
  }

  Future<void> _pickTheme(BuildContext context) async {
    final choice = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in ThemeMode.values)
              ListTile(
                leading: Icon(switch (m) {
                  ThemeMode.system => Icons.phone_android_rounded,
                  ThemeMode.light => Icons.light_mode_rounded,
                  ThemeMode.dark => Icons.dark_mode_rounded,
                }),
                title: Text(switch (m) {
                  ThemeMode.system => 'Use phone setting',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
                trailing: AppSettings.themeMode.value == m
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (choice != null) await AppSettings.setThemeMode(choice);
  }
}

class _Feature {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String description;
  final WidgetBuilder? page;

  const _Feature(this.title, this.subtitle, this.icon, this.color, this.description,
      {this.page});
}

class _FeaturePage extends StatelessWidget {
  final _Feature feature;
  const _FeaturePage({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(feature.title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconBubble(icon: feature.icon, color: feature.color, size: 72),
            const SizedBox(height: 16),
            Text(feature.description, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Coming in the next update.',
                style: TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
