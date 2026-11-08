import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'cloud_auth.dart';

/// A group the signed-in person belongs to.
class FamilyInfo {
  final String id;
  final String name;
  final bool isAdmin;
  FamilyInfo(this.id, this.name, this.isAdmin);
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

/// Groups, members and requests in the cloud.
class CloudFamily {
  CloudFamily._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static User? get _me => CloudAuth.currentUser;

  /// Saves the details other people can use to find this account. Call after sign-in and profile saves.
  static Future<void> saveProfile({required String username, required String phone}) async {
    final user = _me;
    if (user == null) return;
    await _db.collection('personal').doc(user.uid).collection('profile').doc('info').set({
      'username': username.toLowerCase(),
      'phone': phone.isEmpty ? '' : CloudAuth.normalizePhone(phone),
      'email': user.email ?? '',
    }, SetOptions(merge: true));
  }

  /// Target for a request: 'gmail:<address>', 'phone:<number>' or 'user:<username>'.
  static String targetKey(String kind, String value) {
    switch (kind) {
      case 'gmail':
        return 'gmail:${value.trim().toLowerCase()}';
      case 'phone':
        return 'phone:${CloudAuth.normalizePhone(value)}';
      default:
        return 'user:${value.trim().toLowerCase()}';
    }
  }

  /// Groups the signed-in person is in (created by them, or joined).
  static Future<List<FamilyInfo>> myFamilies() async {
    final user = _me;
    if (user == null) return [];
    final memberships = await _db
        .collectionGroup('members')
        .where(FieldPath.documentId, isEqualTo: user.uid)
        .get();
    final result = <FamilyInfo>[];
    for (final m in memberships.docs) {
      final family = m.reference.parent.parent;
      if (family == null) continue;
      final doc = await family.get();
      result.add(FamilyInfo(
        family.id,
        (doc.data()?['name'] as String?) ?? 'Group',
        (m.data()['role'] as String?) == 'admin',
      ));
    }
    return result;
  }

  /// Creates a group, and makes the signed-in person its admin.
  static Future<String> createFamily(String name, String myName) async {
    final user = _me;
    if (user == null) throw CloudAuthException('Sign in first.');
    final family = _db.collection('families').doc();
    await family.set({'name': name, 'createdBy': user.uid});
    await family.collection('members').doc(user.uid).set({'role': 'admin', 'name': myName});
    return family.id;
  }

  static Future<void> renameFamily(String familyId, String name) async {
    await _db.collection('families').doc(familyId).update({'name': name});
  }

  static Future<List<FamilyMember>> members(String familyId) async {
    final snap = await _db.collection('families').doc(familyId).collection('members').get();
    return snap.docs
        .map((d) => FamilyMember(d.id, (d.data()['name'] as String?) ?? 'Member',
            (d.data()['role'] as String?) ?? 'member'))
        .toList();
  }

  /// Sends a request to join a group. Any member of the group can do this.
  static Future<void> addMember({
    required String familyId,
    required String familyName,
    required String myName,
    required String kind,
    required String value,
  }) async {
    final user = _me;
    if (user == null) throw CloudAuthException('Sign in first.');
    final key = targetKey(kind, value);
    if (key.endsWith(':')) throw CloudAuthException('Enter a Gmail, phone number or username.');
    await _db.collection('invites').doc('$familyId|$key').set({
      'familyId': familyId,
      'familyName': familyName,
      'invitedBy': user.uid,
      'invitedByName': myName,
      'targetKey': key,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Requests the signed-in person sent.
  static Future<List<FamilyInvite>> sentInvites() async {
    final user = _me;
    if (user == null) return [];
    final snap = await _db.collection('invites').where('invitedBy', isEqualTo: user.uid).get();
    return snap.docs.map(_fromDoc).toList();
  }

  /// Requests sent to the signed-in person, by Gmail, phone number or username.
  static Future<List<FamilyInvite>> receivedInvites() async {
    final user = _me;
    if (user == null) return [];
    final keys = <String>[];
    if (user.email != null) keys.add(targetKey('gmail', user.email!));
    final profile = await _db.collection('personal').doc(user.uid).collection('profile').doc('info').get();
    final username = (profile.data()?['username'] as String?) ?? '';
    final phone = (profile.data()?['phone'] as String?) ?? '';
    if (username.isNotEmpty) keys.add(targetKey('user', username));
    if (phone.isNotEmpty) keys.add(targetKey('phone', phone));

    final result = <FamilyInvite>[];
    for (final key in keys) {
      try {
        final snap = await _db.collection('invites').where('targetKey', isEqualTo: key).get();
        result.addAll(snap.docs.map(_fromDoc));
      } catch (_) {}
    }
    return result;
  }

  static FamilyInvite _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    return FamilyInvite(
      id: d.id,
      familyId: (data['familyId'] as String?) ?? '',
      familyName: (data['familyName'] as String?) ?? 'Group',
      invitedBy: (data['invitedBy'] as String?) ?? '',
      invitedByName: (data['invitedByName'] as String?) ?? 'Someone',
      targetKey: (data['targetKey'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'pending',
    );
  }

  /// Accepts a request: joins the group, then marks the request approved.
  static Future<void> acceptInvite(FamilyInvite invite, String myName) async {
    final user = _me;
    if (user == null) throw CloudAuthException('Sign in first.');
    await _db.collection('families').doc(invite.familyId).collection('members').doc(user.uid).set({
      'role': 'member',
      'name': myName,
    });
    await _db.collection('invites').doc(invite.id).update({'status': 'approved'});
  }

  static Future<void> rejectInvite(FamilyInvite invite) async {
    await _db.collection('invites').doc(invite.id).update({'status': 'rejected'});
  }

  /// Admins remove a member.
  static Future<void> removeMember(String familyId, String uid) async {
    await _db.collection('families').doc(familyId).collection('members').doc(uid).delete();
  }

  /// Leaves a group.
  static Future<void> leaveFamily(String familyId) async {
    final user = _me;
    if (user == null) return;
    await removeMember(familyId, user.uid);
  }
}
