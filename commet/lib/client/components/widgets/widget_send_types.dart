// Vommet: what a widget sends into the room, so a widget the user can't
// send with is marked "View only". Catalog widgets declare their event types
// (widget_catalog.json "sends"); other widgets are learned from the
// capabilities they ask for when they open.
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';

class WidgetSendTypes {
  static const sendEvent = "org.matrix.msc2762.send.event";
  static const sendState = "org.matrix.msc2762.send.state_event";

  // Capabilities asked for this run, per "<client>/<widget namespace>".
  static final Map<String, Set<String>> _learned = {};

  static bool isSend(String capability) =>
      capability.startsWith("$sendEvent:") ||
      capability.startsWith("$sendState:");

  /// Called with every capability request a widget makes.
  static void learn(
      String clientId, String namespace, Iterable<String> capabilities) {
    final sends = capabilities.where(isSend).toSet();
    if (sends.isEmpty) return;
    _learned["$clientId/$namespace"] = sends;
  }

  /// The send capabilities a widget is known to use: [declared] (from the
  /// catalog), what it asked for this run, and what the user answered
  /// "remember" for before. Empty when nothing is known.
  static Future<Set<String>> known(String clientId, String namespace,
      {Iterable<String> declared = const []}) async {
    final accepted =
        await preferences.getAcceptedWidgetCapabilities(clientId, namespace);
    final rejected =
        await preferences.getRejectedWidgetCapabilities(clientId, namespace);
    return {
      ...declared,
      ...?_learned["$clientId/$namespace"],
      ...accepted.where(isSend),
      ...rejected.where(isSend),
    };
  }

  /// Whether the user's power level lets them send everything in
  /// [capabilities] in [room].
  static bool canSendAll(Room room, Iterable<String> capabilities) {
    if (room is! MatrixRoom) return true;
    final matrixRoom = room.matrixRoom;
    for (final capability in capabilities) {
      final colon = capability.indexOf(":");
      if (colon < 0) continue;
      // "type" or "type#state_key"
      final type = capability.substring(colon + 1).split("#").first;
      if (type.isEmpty) continue;
      final allowed = capability.startsWith("$sendState:")
          ? matrixRoom.canChangeStateEvent(type)
          : matrixRoom.canSendEvent(type);
      if (!allowed) return false;
    }
    return true;
  }
}
