import 'package:commet/client/client.dart';
import 'package:commet/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';

class MatrixAccountSwitchComponent extends AccountSwitchPrefix<MatrixClient> {
  @override
  MatrixClient client;

  MatrixAccountSwitchComponent(this.client);

  static const accountDataKey = "im.fluffychat.account_bundles";

  @override
  List<SendAsPattern> get patterns => SendAsPatternStorage.read(
      client.matrixClient.accountData[accountDataKey]?.content);

  @override
  (Client, SendAsPattern)? getPrefixedAccount(String string, Room currentRoom) {
    (Client, SendAsPattern)? best;

    // Vommet issue 597: of all patterns that match, the longest wins; only
    // accounts in the room count.
    for (var otherClient in clientManager!.clients) {
      if (otherClient is! MatrixClient) continue;
      if (!otherClient.hasRoom(currentRoom.identifier)) continue;

      var component = otherClient.getComponent<AccountSwitchPrefix>();
      if (component == null) continue;

      for (final pattern in component.patterns) {
        if (!pattern.matches(string)) continue;
        if (best == null || pattern.beats(best.$2)) {
          best = (otherClient, pattern);
        }
      }
    }

    return best;
  }

  @override
  String removePrefix(String string, Room currentRoom) {
    var result = getPrefixedAccount(string, currentRoom);
    if (result == null) {
      return string;
    }

    return result.$2.messageIn(string) ?? string;
  }

  @override
  Future<void> setPatterns(List<SendAsPattern> patterns) async {
    Log.d("Setting new send-as patterns: $patterns");

    final content = SendAsPatternStorage.write(
        client.matrixClient.accountData[accountDataKey]?.content, patterns);

    await client.matrixClient
        .setAccountData(client.matrixClient.userID!, accountDataKey, content);
  }

  @override
  bool isPossiblyUsingPrefix(String currentText) {
    for (var otherClient in clientManager!.clients) {
      if (otherClient is! MatrixClient) continue;

      var component = otherClient.getComponent<AccountSwitchPrefix>();
      if (component == null) continue;

      if (component.patterns.any((p) => p.possiblyMatches(currentText))) {
        return true;
      }
    }

    return false;
  }
}
