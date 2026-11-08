import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'cloud_auth.dart';

/// A family the signed-in person belongs to.
class FamilyInfo {
  final String id;
  final String name;
  final bool isAdmin;
  FamilyInfo(this.id, this.name, this.isAdmin);
}

/// A person in a family.
class FamilyMember {
  final String uid;
  final String name;
  final String role;
  FamilyMember(this.uid, this.name, this.role);
  bool get isAdmin => role == 'admin';
}

/// An invite the signed-in person can accept or reject.
class FamilyInvite {
  final String key;
  final String familyId;
  final String familyName;
  FamilyInvite(this.key, this.familyId, this.familyName);
}

/// Families, members and invites in the cloud.
class CloudFamily {
  CloudFamily._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static User? get _me => CloudAuth.currentUser;

  /// Saves the details other people can use to invite this account. Call after sign-in and profile saves.
  static Future<void> saveProfile({required String username, required String phone}) async {
    final user = _me;
    if (user == null) return;
    await _db.collection('personal').doc(user.uid).collection('profile').doc('info').set({
      'username': username.toLowerCase(),
      'phone': phone.isEmpty ? '' : CloudAuth.normalizePhone(phone),
      'email': user.email ?? '',
    }, SetOptions(merge: true));
  }

  /// Invite key for a Gmail, phone number or username.
  static String inviteKey(String kind, String value) {
    switch (kind) {
      case 'gmail':
        return 'gmail:${value.trim().toLowerCase()}';
      case 'phone':
        return 'phone:${CloudAuth.normalizePhone(value)}';
      default:
        return 'user:${value.trim().toLowerCase()}';
    }
  }

  /// Families the signed-in person is in.
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
        (doc.data()?['name'] as String?) ?? 'Family',
        (m.data()['role'] as String?) == 'admin',
      ));
    }
    return result;
  }

  /// Creates a family, and makes the signed-in person its first admin.
  static Future<String> createFamily(String name, String myName) async {
    final user = _me;
    if (user == null) throw CloudAuthException('Sign in first.');
    final family = _db.collection('families').doc();
    await family.set({'name': name, 'createdBy': user.uid});
    await family.collection('members').doc(user.uid).set({
      'role': 'admin',
      'name': myName,
    });
    return family.id;
  }

  static Future<List<FamilyMember>> members(String familyId) async {
    final snap = await _db.collection('families').doc(familyId).collection('members').get();
    return snap.docs
        .map((d) => FamilyMember(d.id, (d.data()['name'] as String?) ?? 'Member',
            (d.data()['role'] as String?) ?? 'member'))
        .toList();
  }

  /// Invites a person by Gmail, phone number or username. Only admins can do this.
  static Future<void> invite({
    required String familyId,
    required String familyName,
    required String kind,
    required String value,
  }) async {
    final user = _me;
    if (user == null) throw CloudAuthException('Sign in first.');
    final key = inviteKey(kind, value);
    if (key.endsWith(':')) throw CloudAuthException('Enter a Gmail, phone number or username.');
    await _db.collection('invites').doc(key).set({
      'familyId': familyId,
      'familyName': familyName,
      'invitedBy': user.uid,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Invites waiting for the signed-in person.
  static Future<List<FamilyInvite>> myInvites() async {
    final user = _me;
    if (user == null) return [];
    final keys = <String>[];
    if (user.email != null) keys.add(inviteKey('gmail', user.email!));
    final profile = await _db.collection('personal').doc(user.uid).collection('profile').doc('info').get();
    final username = (profile.data()?['username'] as String?) ?? '';
    final phone = (profile.data()?['phone'] as String?) ?? '';
    if (username.isNotEmpty) keys.add(inviteKey('user', username));
    if (phone.isNotEmpty) keys.add(inviteKey('phone', phone));

    final result = <FamilyInvite>[];
    for (final key in keys) {
      try {
        final doc = await _db.collection('invites').doc(key).get();
        final data = doc.data();
        if (doc.exists && data != null) {
          result.add(FamilyInvite(key, data['familyId'] as String, (data['familyName'] as String?) ?? 'Family'));
        }
      } catch (_) {}
    }
    return result;
  }

  /// Accepts an invite: joins the family and removes the invite.
  static Future<void> acceptInvite(FamilyInvite invite, String myName) async {
    final user = _me;
    if (user == null) throw CloudAuthException('Sign in first.');
    await _db.collection('families').doc(invite.familyId).collection('members').doc(user.uid).set({
      'role': 'member',
      'name': myName,
    });
    await _db.collection('invites').doc(invite.key).delete();
  }

  static Future<void> rejectInvite(FamilyInvite invite) async {
    await _db.collection('invites').doc(invite.key).delete();
  }

  /// Admins remove a member. A member can also leave.
  static Future<void> removeMember(String familyId, String uid) async {
    await _db.collection('families').doc(familyId).collection('members').doc(uid).delete();
  }
}
