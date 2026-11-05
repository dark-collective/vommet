import 'dart:async';

import 'package:commet/cache/file_cache.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:matrix/matrix.dart' show LoginState;

/// Vommet: what leaves the device when an account's session ends, whether
/// the user signed out here or the server ended it (signed out from another
/// device, token revoked): the encrypted search index (decrypted messages),
/// the sealed media cache's key and entries, saved voice transcripts, the
/// private copies made for players and sharing (media_open) and the Android
/// share and clipboard copies.
///
/// The media cache, the transcripts and the copies are shared by every
/// account on the device, so the other accounts' copies go too (they are
/// fetched or made again when next needed).
///
/// Each step runs on its own: one failing doesn't stop the others. Running
/// it again (a remote sign-out, then removing the account) is harmless.
///
/// Signing out here also forgets the account's database keys
/// ([forgetAccount], after the SDK cleared the message store): a remote
/// sign-out doesn't, the account stays listed until it is removed.
class SignOutWipe {
  SignOutWipe({
    this.deleteIndex,
    this.cache,
    this.clearTranscripts,
    this.sweepCopies = _sweepCopies,
    this.forgetKeys,
  });

  final Future<void>? Function()? deleteIndex;
  final FileCache? cache;
  final Future<void> Function()? clearTranscripts;
  final Future<void> Function() sweepCopies;

  /// Forgets the account's database keys and deletes its databases (local
  /// data encryption).
  final Future<void> Function()? forgetKeys;

  static Future<void> _sweepCopies() async {
    await PrivateMediaFiles.sweep(all: true);
    await PrivateMediaFiles.sweepAndroidCopies(all: true);
  }

  /// Whether [state] means the server ended a session this client had (and
  /// it isn't being signed out here, which wipes by itself).
  static bool endedRemotely(LoginState state,
          {required bool hadSession, required bool loggingOut}) =>
      state == LoginState.loggedOut && hadSession && !loggingOut;

  Future<void>? _running;

  /// Wipes; while a wipe runs, a second call waits for it rather than
  /// starting another.
  Future<void> run() {
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<void> _run() async {
    await Future.wait([
      _step("the search index", deleteIndex),
      _step("the encrypted media cache", cache?.forgetSensitive),
      _step("voice transcripts", clearTranscripts),
      _step("shared media copies", sweepCopies),
    ]);
  }

  /// The account was signed out here and its message store cleared: its
  /// database keys go (see [forgetKeys]). Never throws.
  Future<void> forgetAccount() =>
      _step("the account's database keys", forgetKeys);

  static Future<void> _step(String what, Future<void>? Function()? step) async {
    if (step == null) return;
    try {
      await step();
    } catch (error) {
      Log.w("Couldn't delete $what at sign-out: $error");
    }
  }
}
