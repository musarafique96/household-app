import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// A message to show the person when sign-in or linking fails.
class CloudAuthException implements Exception {
  final String message;
  CloudAuthException(this.message);
  @override
  String toString() => message;
}

/// Cloud sign-in: username + password, Google, and linking a Gmail address.
/// Each cloud account has a Firebase user ID. That ID is what sync will use.
class CloudAuth {
  CloudAuth._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final GoogleSignIn _google = GoogleSignIn();

  /// Usernames become a made-up address for Firebase, for example musa@gharbaar.app.
  /// No mail is ever sent there.
  static const String _domain = 'gharbaar.app';

  static String emailFor(String username) => '${username.toLowerCase()}@$_domain';

  static bool validUsername(String username) =>
      RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username.toLowerCase());

  /// Phone numbers are stored as digits with an optional leading +.
  static String normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '');

  static bool validPhone(String phone) {
    final p = normalizePhone(phone);
    return RegExp(r'^\+?[0-9]{8,15}$').hasMatch(p);
  }

  /// Creates a username account. Firebase rejects a username that is already taken.
  static Future<User> signUp(String username, String password) async {
    final name = username.toLowerCase();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: emailFor(name),
        password: password,
      );
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          throw CloudAuthException('That username is already taken.');
        case 'weak-password':
          throw CloudAuthException('Password must be at least 6 characters.');
        default:
          throw CloudAuthException('Could not create the account: ${e.code}');
      }
    }
  }

  static Future<User> signIn(String username, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: emailFor(username),
        password: password,
      );
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential' ||
          e.code == 'wrong-password' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-email') {
        throw CloudAuthException('Username or password is wrong.');
      }
      throw CloudAuthException('Could not sign in: ${e.code}');
    }
  }

  /// Signs in with a Google account. Creates a cloud account if this Gmail is new.
  static Future<User?> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) return null; // person cancelled
    final auth = await account.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    final result = await _auth.signInWithCredential(cred);
    return result.user;
  }

  /// Adds a Gmail address to the signed-in account, so the account can also sign in with Google
  /// and reset its password through it. If the Gmail belongs to another account, this fails.
  static Future<void> linkGmail() async {
    final user = _auth.currentUser;
    if (user == null) throw CloudAuthException('Sign in first.');
    final account = await _google.signIn();
    if (account == null) return; // person cancelled
    final auth = await account.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    try {
      await user.linkWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use') {
        throw CloudAuthException('This Gmail is already linked to another account.');
      }
      throw CloudAuthException('Could not link Gmail: ${e.code}');
    }
  }

  /// The Gmail address on the signed-in account, or null if none is linked.
  static String? linkedGmail() {
    final user = _auth.currentUser;
    if (user == null) return null;
    for (final info in user.providerData) {
      if (info.providerId == 'google.com') return info.email;
    }
    return null;
  }

  /// Reserves a phone number for the signed-in account. Fails if another account has it.
  /// Also frees the old number, if the account had one.
  static Future<void> setPhone(String phone, {String? oldPhone}) async {
    final user = _auth.currentUser;
    if (user == null) throw CloudAuthException('Sign in first.');
    final newId = normalizePhone(phone);
    final newRef = _db.collection('phones').doc(newId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(newRef);
      if (snap.exists && snap.data()?['uid'] != user.uid) {
        throw CloudAuthException('That phone number is already used by another account.');
      }
      tx.set(newRef, {'uid': user.uid});
    });
    final old = oldPhone == null ? '' : normalizePhone(oldPhone);
    if (old.isNotEmpty && old != newId) {
      final oldRef = _db.collection('phones').doc(old);
      final snap = await oldRef.get();
      if (snap.exists && snap.data()?['uid'] == user.uid) {
        await oldRef.delete();
      }
    }
  }

  /// Changes the password of the signed-in username account, after checking the current one.
  static Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) return; // not a username account: nothing to change
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw CloudAuthException('Current password is wrong.');
      }
      if (e.code == 'weak-password') {
        throw CloudAuthException('Password must be at least 6 characters.');
      }
      throw CloudAuthException('Could not change the password: ${e.code}');
    }
  }

  static Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }

  static User? get currentUser => _auth.currentUser;
}
