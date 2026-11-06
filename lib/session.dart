import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/db.dart';
import 'data/models.dart';

/// Which household member is using this phone. Remembered between launches.
class Session {
  Session._();

  static final ValueNotifier<AppUser?> current = ValueNotifier<AppUser?>(null);
  static const String _key = 'current_user_id';

  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_key);
    if (id == null) return;

    final users = await Db.instance.users();
    for (final u in users) {
      if (u.id == id) {
        current.value = u;
        return;
      }
    }
  }

  static Future<void> signOut() async {
    current.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> select(AppUser user) async {
    current.value = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, user.id);
  }
}
