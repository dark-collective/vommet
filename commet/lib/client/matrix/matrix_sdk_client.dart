import 'package:matrix/matrix.dart';

/// Vommet: the SDK's [Client], with its answer to "does this server have
/// authenticated media?" kept in memory (Vommet issue 1035).
///
/// The SDK reads that answer from the account's database for every media url,
/// so each download, a voice message's too, and each thumbnail in its slot
/// first waited for that read, which waits for the sync being saved. The
/// answer hardly ever changes.
class MatrixSdkClient extends Client {
  MatrixSdkClient(
    super.clientName, {
    required super.database,
    super.httpClient,
    super.verificationMethods,
    super.importantStateEvents,
    super.supportedLoginTypes,
    super.nativeImplementations,
    super.logLevel,
    super.sendTimelineEventTimeout,
  });

  /// How long the answer is used before it is read again.
  static const Duration authenticatedMediaMemory = Duration(hours: 1);

  ({Uri? homeserver, DateTime until, Future<bool> answer})? _authenticatedMedia;

  @override
  Future<bool> authenticatedMediaSupported() {
    // Not while signed out: the SDK asks the server then, and signing in may
    // change the server.
    if (!isLogged()) return super.authenticatedMediaSupported();

    final known = _authenticatedMedia;
    if (known != null &&
        known.homeserver == homeserver &&
        DateTime.now().isBefore(known.until)) {
      return known.answer;
    }

    final answer = super.authenticatedMediaSupported();
    final entry = (
      homeserver: homeserver,
      until: DateTime.now().add(authenticatedMediaMemory),
      answer: answer,
    );
    _authenticatedMedia = entry;
    answer.catchError((Object _) {
      if (identical(_authenticatedMedia, entry)) _authenticatedMedia = null;
      return false;
    });
    return answer;
  }
}
