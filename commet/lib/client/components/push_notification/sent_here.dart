import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: IDs of the events this device sent, so notification handling can
/// tell "you sent that from here" from "from another device" by ID, without
/// comparing clocks. The SDK emits a sent event (status [EventStatus.sent],
/// with its real ID) only on the device that sent it, for every send path
/// (text, files, reactions, bubbles). Kept in shared preferences because the
/// push handler may run in another isolate; newest last, capped. Android
/// only, where the notification rule that reads it runs.
class SentHere {
  static const _key = "vommet_sent_here";
  static const _max = 100;

  static void track(matrix.Client mx) {
    if (!PlatformUtils.isAndroid) return;
    mx.onTimelineEvent.stream.listen((event) {
      if (event.status != matrix.EventStatus.sent) return;
      if (event.senderId != mx.userID) return;
      _add(event.eventId);
    });
  }

  static Future<void> _add(String eventId) async {
    final prefs = Preference.preferences;
    if (prefs == null) return;
    final ids = [...?prefs.getStringList(_key)];
    if (ids.contains(eventId)) return;
    ids.add(eventId);
    if (ids.length > _max) ids.removeRange(0, ids.length - _max);
    await prefs.setStringList(_key, ids);
  }

  /// The recorded IDs; reloads first, since another isolate writes them.
  static Future<Set<String>> read() async {
    final prefs = Preference.preferences;
    if (prefs == null) return const {};
    await prefs.reload();
    return {...?prefs.getStringList(_key)};
  }
}
