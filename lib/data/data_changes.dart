import 'package:flutter/foundation.dart';

/// Ticks up every time the database is written to, so open screens reload.
class DataChanges {
  DataChanges._();

  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void bump() => version.value++;
}
