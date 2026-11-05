import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/matrix/components/widgets/capabilities/voip_state_capability.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_permission_groups.dart';
import 'package:commet/client/room.dart';

/// Vommet (issue 444): widgets are allowed in voice rooms, except for what
/// would join or signal the room's call itself. Upstream hid every widget
/// there because a MatrixRTC widget interfered with the ongoing call.
class WidgetCallGuard {
  static bool isVoiceRoom(Room? room) =>
      room?.getComponent<VoipRoomComponent>() != null;

  /// Element Call and Jitsi widgets: they are a call of their own.
  static bool isCallWidgetType(String type) {
    final t = type.toLowerCase();
    return t == "m.call" ||
        t.startsWith("io.element.call") ||
        t.contains("jitsi");
  }

  static const _callEventTypes = {
    "org.matrix.msc3401.call",
    "org.matrix.msc3401.call.member",
    "org.matrix.msc4143.rtc.member",
    "org.matrix.msc4310.rtc.decline",
    "org.matrix.msc4075.call.notify",
    "org.matrix.msc4075.rtc.notification",
  };

  static const _callEventPrefixes = [
    "m.call.",
    "m.rtc.",
    "org.matrix.call.",
    "io.element.call.",
  ];

  /// A capability that sends or reads call membership, call signalling or
  /// call encryption keys, or Commet's call state. Delayed and sticky events
  /// stay allowed: without call membership they can't touch the call.
  static bool isCallCapability(String capability) {
    final parsed = MatrixWidgetCapabilityString.parse(capability);
    if (parsed.capability == MatrixCapabilityVoipState.name) return true;
    final type = parsed.eventType;
    if (type == null) return false;
    return _callEventTypes.contains(type) ||
        _callEventPrefixes.any((p) => type.startsWith(p));
  }
}
