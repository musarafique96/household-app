import 'package:flutter/material.dart';

import '../data/data_changes.dart';

/// Reloads a screen whenever any data in the app changes, so an expense added
/// on one tab shows up on every other tab straight away.
mixin DataRefreshState<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    DataChanges.version.addListener(_onAnyDataChanged);
  }

  @override
  void dispose() {
    DataChanges.version.removeListener(_onAnyDataChanged);
    super.dispose();
  }

  void _onAnyDataChanged() => onDataChanged();

  /// Reload this screen's data. Implementations should call setState.
  void onDataChanged();
}
