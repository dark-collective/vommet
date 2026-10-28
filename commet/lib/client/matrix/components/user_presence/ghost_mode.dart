import 'package:matrix/matrix.dart' as matrix;

/// Vommet: ghost mode turns off public read receipts and the typing
/// indicator in every room with one switch, over the per-account and per-room
/// settings (those come back as they were when it's turned off). Stored in
/// private account data, so it follows the account to other Vommet devices.
class GhostMode {
  static const String key = "im.nether.vommet.ghost_mode";

  static bool isOn(matrix.Client client) =>
      enabledIn(client.accountData[key]?.content);

  static bool enabledIn(Map<String, Object?>? content) =>
      content?["enabled"] == true;

  static Future<void> set(matrix.Client client, bool value) =>
      client.setAccountData(client.userID!, key, {"enabled": value});
}
