// Vommet issue 72: before signing out, is this the account's last device
// that holds its message keys? Decides which warning the sign-out dialog
// shows (see sign_out_dialog.dart).
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/matrix_session.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/renamed_session_last_seen.dart';
import 'package:matrix/matrix.dart' as matrix;

enum SignOutCase {
  /// No encryption on this account (or it failed to load): a plain
  /// confirmation.
  plain,

  /// Another verified session was seen recently: it still has the keys.
  otherSession,

  /// The last device, but message backup is on: the recovery key brings
  /// the history back, so check it first.
  lastDeviceBackedUp,

  /// The last device and no backup: signing out loses the history.
  lastDeviceNoBackup,
}

/// Another session of the account, as far as the sign-out check cares.
class SignOutSession {
  const SignOutSession(
      {required this.deviceId,
      this.displayName,
      this.lastSeen,
      this.verified = false});
  final String deviceId;
  final String? displayName;
  final DateTime? lastSeen;

  /// Verified (cross-signed, or verified directly) by this account.
  final bool verified;
}

class SignOutAssessment {
  const SignOutAssessment(this.kind, {this.keeper});
  final SignOutCase kind;

  /// [SignOutCase.otherSession]: the session that keeps the keys (the most
  /// recently seen one).
  final SignOutSession? keeper;

  @override
  String toString() => kind.name;
}

class SignOutCheck {
  /// How recently another session must have been seen to count as still
  /// holding the keys.
  static const recent = Duration(days: 14);

  /// The decision on its own, for tests. [others] is null when the session
  /// list couldn't be loaded: then this counts as the last device (fails
  /// safe). [backupRecoverable] = an online key backup the recovery key
  /// opens.
  static SignOutAssessment decide({
    required bool encryption,
    required List<SignOutSession>? others,
    required bool backupRecoverable,
    required DateTime now,
  }) {
    if (!encryption) return const SignOutAssessment(SignOutCase.plain);
    SignOutSession? keeper;
    for (final s in others ?? const <SignOutSession>[]) {
      final seen = s.lastSeen;
      if (!s.verified || seen == null) continue;
      if (now.difference(seen) > recent) continue;
      if (keeper == null || seen.isAfter(keeper.lastSeen!)) keeper = s;
    }
    if (keeper != null) {
      return SignOutAssessment(SignOutCase.otherSession, keeper: keeper);
    }
    return SignOutAssessment(backupRecoverable
        ? SignOutCase.lastDeviceBackedUp
        : SignOutCase.lastDeviceNoBackup);
  }

  /// Asks the server for the account's sessions and decides. Never throws.
  static Future<SignOutAssessment> load(MatrixClient client,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final mx = _signedIn(client);
    if (mx == null || mx.encryption == null) {
      return const SignOutAssessment(SignOutCase.plain);
    }
    final status = SecureMessaging.fromClient(mx);
    final backupRecoverable =
        status.hasKeyBackup && SecureMessaging.secretStorageHasSecrets(mx);
    final result = decide(
        encryption: true,
        others: await _otherSessions(mx, timeout),
        backupRecoverable: backupRecoverable,
        now: DateTime.now());
    Log.i("Sign-out check: $result");
    return result;
  }

  /// The signed-in SDK client, or null (signed out, failed to load).
  static matrix.Client? _signedIn(MatrixClient client) {
    try {
      return client.isLoggedIn() ? client.getMatrixClient() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<SignOutSession>?> _otherSessions(
      matrix.Client mx, Duration timeout) async {
    try {
      final devices = await mx.getDevices().timeout(timeout);
      final userId = mx.userID;
      if (devices == null || userId == null) return null;
      // A rename stamps "last seen" on some servers: undo that, or a
      // renamed old session would look active.
      await RenamedSessionLastSeen(preferences.vommetSharedPreferences)
          .restore(userId, devices);
      final keys = mx.userDeviceKeys[userId]?.deviceKeys;
      return [
        for (final d in devices)
          if (d.deviceId != mx.deviceID &&
              !isDehydratedSession(
                  displayName: d.displayName,
                  deviceKeys: keys?[d.deviceId]?.toJson(),
                  sdkDisplayName: mx.dehydratedDeviceDisplayName))
            SignOutSession(
                deviceId: d.deviceId,
                displayName: d.displayName,
                lastSeen: d.lastSeenTs == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(d.lastSeenTs!),
                verified: keys?[d.deviceId]?.verified ?? false),
      ];
    } catch (e) {
      Log.w("Sign-out check: couldn't load the sessions: $e");
      return null;
    }
  }
}
