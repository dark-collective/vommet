import 'package:commet/client/matrix/components/widgets/widget_call_guard.dart';
import 'package:test/test.dart';

void main() {
  group("call widget types", () {
    test("Element Call and Jitsi are call widgets", () {
      expect(WidgetCallGuard.isCallWidgetType("m.call"), isTrue);
      expect(WidgetCallGuard.isCallWidgetType("io.element.call"), isTrue);
      expect(WidgetCallGuard.isCallWidgetType("m.jitsi"), isTrue);
      expect(WidgetCallGuard.isCallWidgetType("jitsi"), isTrue);
    });

    test("other widgets are not", () {
      expect(WidgetCallGuard.isCallWidgetType("m.custom"), isFalse);
      expect(WidgetCallGuard.isCallWidgetType("m.etherpad"), isFalse);
      expect(WidgetCallGuard.isCallWidgetType("im.nether.watch_together"),
          isFalse);
    });
  });

  group("call capabilities", () {
    test("call membership, signalling and keys are blocked", () {
      for (final c in [
        "org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member",
        "org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member#_@a:b_DEV",
        "org.matrix.msc2762.receive.state_event:org.matrix.msc3401.call.member",
        "org.matrix.msc2762.send.event:org.matrix.msc4143.rtc.member",
        "org.matrix.msc2762.send.event:io.element.call.encryption_keys",
        "org.matrix.msc3819.send.to_device:io.element.call.encryption_keys",
        "org.matrix.msc3819.send.to_device:m.call.invite",
        "org.matrix.msc3819.receive.to_device:m.call.hangup",
        "org.matrix.msc2762.send.event:org.matrix.msc4075.rtc.notification",
        "chat.commet.voip_overlay.voip_state",
      ]) {
        expect(WidgetCallGuard.isCallCapability(c), isTrue, reason: c);
      }
    });

    test("ordinary widget capabilities are allowed", () {
      for (final c in [
        "org.matrix.msc2762.send.event:m.room.message#m.text",
        "org.matrix.msc2762.receive.event:m.room.message",
        "org.matrix.msc2762.send.state_event:im.nether.watch_together",
        "org.matrix.msc3819.send.to_device:im.nether.sync",
        "org.matrix.msc4157.send.delayed_event",
        "org.matrix.msc2931.navigate",
        "m.always_on_screen",
      ]) {
        expect(WidgetCallGuard.isCallCapability(c), isFalse, reason: c);
      }
    });
  });
}
