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
  String? get clientPrefix {
    final bundles = client.matrixClient.accountData[accountDataKey];
    final content = bundles?.content;
    final prefix = content?["prefix"];
    if (prefix is String) {
      return prefix;
    }

    return null;
  }

  @override
  (Client, String)? getPrefixedAccount(String string, Room currentRoom) {
    for (var otherClient in clientManager!.clients) {
      if (otherClient is! MatrixClient) continue;

      var component = otherClient.getComponent<AccountSwitchPrefix>();
      if (component == null) continue;

      if (component.clientPrefix == null) continue;

      if (AccountPrefixText.matches(string, component.clientPrefix!)) {
        print("Found prefixed client!, $otherClient");

        if (otherClient.hasRoom(currentRoom.identifier)) {
          return (otherClient, component.clientPrefix!);
        } else {
          print("Client is not a member of the room!");
        }
      }
    }

    return null;
  }

  @override
  String removePrefix(String string, Room currentRoom) {
    var result = getPrefixedAccount(string, currentRoom);
    if (result == null) {
      return string;
    }

    return AccountPrefixText.remove(string, result.$2);
  }

  @override
  Future<void> setClientPrefix(String? prefix) async {
    Log.d("Setting new account prefix: $prefix");

    final bundles = client.matrixClient.accountData[accountDataKey];
    final content = bundles?.content ?? {};

    final normalized = AccountPrefixText.normalize(prefix);
    if (normalized == null) {
      content.remove("prefix");
    } else {
      content["prefix"] = normalized;
    }

    await client.matrixClient
        .setAccountData(client.matrixClient.userID!, accountDataKey, content);
  }

  @override
  bool isPossiblyUsingPrefix(String currentText) {
    for (var otherClient in clientManager!.clients) {
      if (otherClient is! MatrixClient) continue;

      var component = otherClient.getComponent<AccountSwitchPrefix>();
      if (component == null) continue;

      if (component.clientPrefix == null) continue;

      if (AccountPrefixText.possiblyMatches(
          currentText, component.clientPrefix!)) {
        return true;
      }
    }

    return false;
  }
}
