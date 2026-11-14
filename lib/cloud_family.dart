import 'api_client.dart';
import 'cloud_auth.dart';

/// A group the signed-in person belongs to.
/// A change from this phone that the cloud kept back for someone to decide on.
/// [entity] is 'budget_category' or 'expense'. [clientData] is what this phone wanted to save (empty for a deletion).
class SyncConflict {
  final String id;
  final String entity;
  final int clientVersion;
  final int serverVersion;
  final Map<String, dynamic> clientData;
  final DateTime createdAt;

  SyncConflict({
    required this.id,
    required this.entity,
    required this.clientVersion,
    required this.serverVersion,
    required this.clientData,
    required this.createdAt,
  });

  factory SyncConflict.fromJson(Map<String, dynamic> j) => SyncConflict(
        id: j['id'] as String,
        entity: j['entity'] as String,
        clientVersion: (j['clientVersion'] as num).toInt(),
        serverVersion: (j['serverVersion'] as num).toInt(),
        clientData: (j['clientData'] as Map<String, dynamic>?) ?? {},
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

/// A group the signed-in person belongs to. [currency] is the group's main currency (every amount on the cloud is in it).
class FamilyInfo {
  final String id;
  final String name;
  final bool isAdmin;
  final String currency;
  /// How this member sees group amounts: 'group' (the group currency) or 'own' (the member's account currency).
  final String viewCurrency;
  FamilyInfo(this.id, this.name, this.isAdmin, {this.currency = '', this.viewCurrency = 'group'});
}

/// A group budget category, in the group currency.
class GroupCategory {
  final String id;
  final String name;
  final double monthlyLimit;
  GroupCategory(this.id, this.name, this.monthlyLimit);
}

/// A group expense, in the group currency. [originalAmount] and [originalCurrency] are what it was entered as.
class GroupExpense {
  final String id;
  final String? categoryId;
  final double amount;
  final String date;
  final String note;
  final double? originalAmount;
  final String? originalCurrency;
  GroupExpense({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.date,
    required this.note,
    required this.originalAmount,
    required this.originalCurrency,
  });
}

/// A person in a group.
class FamilyMember {
  final String uid;
  final String name;
  final String role;
  FamilyMember(this.uid, this.name, this.role);
  bool get isAdmin => role == 'admin';
}

/// A request to join a group. [status] is 'pending', 'approved' or 'rejected'.
class FamilyInvite {
  final String id;
  final String familyId;
  final String familyName;
  final String invitedBy;
  final String invitedByName;
  final String targetKey;
  final String status;
  FamilyInvite({
    required this.id,
    required this.familyId,
    required this.familyName,
    required this.invitedBy,
    required this.invitedByName,
    required this.targetKey,
    required this.status,
  });

  /// The Gmail, phone number or username the request was sent to.
  String get targetLabel => targetKey.substring(targetKey.indexOf(':') + 1);
  bool get isPending => status == 'pending';
}

/// Groups (called households on the API), members and requests.
class CloudFamily {
  CloudFamily._();

  static CloudUser? get _me => CloudAuth.currentUser;

  /// Runs an API call and turns the server's error into a message for the person.
  static Future<dynamic> _call(Future<dynamic> Function() action) async {
    try {
      return await action();
    } on ApiException catch (e) {
      throw CloudAuthException(e.message);
    }
  }

  static String _key(String targetType, String value) =>
      targetType == 'gmail' ? 'gmail:$value' : 'user:$value';

  /// Kept so the account screens compile. The API keeps the username itself, so nothing needs saving here.
  static Future<void> saveProfile({required String username, required String phone}) async {}

  /// Groups the signed-in person is in. The admin of a group is its head on the API.
  static Future<List<FamilyInfo>> myFamilies() async {
    if (_me == null) return [];
    final list = await _call(() => ApiClient.get('/households')) as List<dynamic>;
    return list.map((raw) {
      final h = raw as Map<String, dynamic>;
      return FamilyInfo(
        h['id'] as String,
        (h['name'] as String?) ?? 'Group',
        h['role'] == 'head',
        currency: (h['currency'] as String?) ?? '',
        viewCurrency: (h['viewCurrency'] as String?) ?? 'group',
      );
    }).toList();
  }

  /// Creates a group, and makes the signed-in person its admin. Returns the new group's id.
  /// [currency] is the group's main currency, for example 'PKR'.
  static Future<String> createFamily(String name, String myName, {required String currency}) async {
    if (_me == null) throw CloudAuthException('Sign in first.');
    final data = await _call(() => ApiClient.post('/households', {'name': name, 'currency': currency}))
        as Map<String, dynamic>;
    return data['id'] as String;
  }

  /// Saves how this member sees group amounts ('group' or 'own'). It is kept on the account.
  static Future<void> setViewCurrency(String familyId, String view) async {
    await _call(() => ApiClient.put('/households/$familyId/view', {'view': view}));
  }

  /// The group's budget categories, in the group currency.
  static Future<List<GroupCategory>> groupCategories(String familyId) async {
    final list = await _call(() => ApiClient.get('/households/$familyId/categories')) as List<dynamic>;
    return list.map((raw) {
      final c = raw as Map<String, dynamic>;
      return GroupCategory(
        c['id'] as String,
        (c['name'] as String?) ?? 'Category',
        (c['monthlyLimit'] as num).toDouble(),
      );
    }).toList();
  }

  /// The group's expenses between [from] and [to] (yyyy-MM-dd), in the group currency.
  static Future<List<GroupExpense>> groupExpenses(String familyId, {required String from, required String to}) async {
    final list = await _call(() => ApiClient.get('/households/$familyId/expenses?from=$from&to=$to')) as List<dynamic>;
    return list.map((raw) {
      final e = raw as Map<String, dynamic>;
      final originalAmount = e['originalAmount'] as num?;
      return GroupExpense(
        id: e['id'] as String,
        categoryId: e['categoryId'] as String?,
        amount: (e['amount'] as num).toDouble(),
        date: e['expenseDate'] as String,
        note: (e['note'] as String?) ?? '',
        originalAmount: originalAmount?.toDouble(),
        originalCurrency: e['originalCurrency'] as String?,
      );
    }).toList();
  }

  /// Changes the group's main currency. Every budget amount on the cloud is multiplied by [rate],
  /// which is how many new-currency units one old-currency unit is worth. Only an admin can do this.
  static Future<void> changeCurrency(String familyId, {required String currency, required double rate}) async {
    await _call(() => ApiClient.put('/households/$familyId/currency', {'currency': currency, 'rate': rate}));
  }

  static Future<void> renameFamily(String familyId, String name) async {
    await _call(() => ApiClient.put('/households/$familyId', {'name': name}));
  }

  static Future<List<FamilyMember>> members(String familyId) async {
    final list = await _call(() => ApiClient.get('/households/$familyId/members')) as List<dynamic>;
    return list.map((raw) {
      final m = raw as Map<String, dynamic>;
      final name = (m['displayName'] as String?) ?? '';
      return FamilyMember(
        m['userId'] as String,
        name.isEmpty ? 'Member' : name,
        m['role'] == 'head' ? 'admin' : 'member',
      );
    }).toList();
  }

  /// Sends a request to join a group. Only usernames work for now. Gmail and phone invites come later.
  static Future<void> addMember({
    required String familyId,
    required String familyName,
    required String myName,
    required String kind,
    required String value,
  }) async {
    if (_me == null) throw CloudAuthException('Sign in first.');
    if (kind != 'user') {
      throw CloudAuthException('Only usernames can be invited for now. Gmail and phone invites come later.');
    }
    final username = value.trim().toLowerCase();
    if (username.isEmpty) throw CloudAuthException('Enter a username.');
    await _call(() => ApiClient.post('/households/$familyId/invites', {
          'targetType': 'username',
          'targetValue': username,
        }));
  }

  /// Requests sent from the groups the person administers.
  static Future<List<FamilyInvite>> sentInvites() async {
    final me = _me;
    if (me == null) return [];
    final result = <FamilyInvite>[];
    for (final group in await myFamilies()) {
      if (!group.isAdmin) continue;
      final list = await _call(() => ApiClient.get('/households/${group.id}/invites')) as List<dynamic>;
      for (final raw in list) {
        final i = raw as Map<String, dynamic>;
        result.add(FamilyInvite(
          id: i['id'] as String,
          familyId: group.id,
          familyName: group.name,
          invitedBy: me.uid,
          invitedByName: me.displayName.isEmpty ? me.username : me.displayName,
          targetKey: _key(i['targetType'] as String, i['targetValue'] as String),
          status: i['status'] as String,
        ));
      }
    }
    return result;
  }

  /// Requests sent to the signed-in person by username.
  static Future<List<FamilyInvite>> receivedInvites() async {
    if (_me == null) return [];
    final list = await _call(() => ApiClient.get('/invites/mine')) as List<dynamic>;
    return list.map((raw) {
      final i = raw as Map<String, dynamic>;
      final inviter = (i['invitedByName'] as String?) ?? '';
      return FamilyInvite(
        id: i['id'] as String,
        familyId: i['householdId'] as String,
        familyName: (i['householdName'] as String?) ?? 'Group',
        invitedBy: '',
        invitedByName: inviter.isEmpty ? 'Someone' : inviter,
        targetKey: _key(i['targetType'] as String, i['targetValue'] as String),
        status: 'pending',
      );
    }).toList();
  }

  /// Accepts a request. The person joins the group as a member.
  static Future<void> acceptInvite(FamilyInvite invite, String myName) async {
    if (_me == null) throw CloudAuthException('Sign in first.');
    await _call(() => ApiClient.post('/invites/${invite.id}/accept'));
  }

  static Future<void> rejectInvite(FamilyInvite invite) async {
    await _call(() => ApiClient.post('/invites/${invite.id}/reject'));
  }

  /// Admins remove a member, and a member can remove themselves by leaving.
  static Future<void> removeMember(String familyId, String uid) async {
    await _call(() => ApiClient.delete('/households/$familyId/members/$uid'));
  }

  /// Leaves a group.
  static Future<void> leaveFamily(String familyId) async {
    final me = _me;
    if (me == null) return;
    await removeMember(familyId, me.uid);
  }

  /// Changes the budget kept back for review. Only heads and members who can edit the budget see them.
  static Future<List<SyncConflict>> conflicts(String familyId) async {
    final list = await _call(() => ApiClient.get('/households/$familyId/conflicts')) as List<dynamic>;
    return list.map((r) => SyncConflict.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// keepMine: the phone's change is applied again as a new change. Otherwise the cloud's version stays.
  static Future<void> resolveConflict(String familyId, SyncConflict c, {required bool keepMine}) async {
    await _call(() => ApiClient.post(
          '/households/$familyId/conflicts/${c.id}/resolve',
          {'keep': keepMine ? 'mine' : 'server'},
        ));
  }
}
