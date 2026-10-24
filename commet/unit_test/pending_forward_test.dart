import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/forward_message/pending_forward.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Event extends Fake implements TimelineEvent {
  _Event(this.eventId);

  @override
  final String eventId;
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  setUp(() => preferences.forwardShowSender.reset());

  // Vommet issue 657.
  group("sender name", () {
    test("is hidden by default", () {
      final forward = PendingForward(event: _Event("e1"), timeline: null);
      expect(forward.showSender, isFalse);
    });

    test("follows the last choice", () async {
      PendingForward.rememberShowSender(true);
      await Future<void>.delayed(Duration.zero);
      expect(preferences.forwardShowSender.value, isTrue);
      expect(PendingForward(event: _Event("e1"), timeline: null).showSender,
          isTrue);

      PendingForward.rememberShowSender(false);
      await Future<void>.delayed(Duration.zero);
      expect(PendingForward(event: _Event("e1"), timeline: null).showSender,
          isFalse);
    });

    test("an explicit value wins over the last choice", () {
      final forward =
          PendingForward(event: _Event("e1"), timeline: null, showSender: true);
      expect(forward.showSender, isTrue);
    });
  });

  // Vommet issue 653: several messages ticked with Select wait together.
  group("several messages", () {
    final events = [_Event("e1"), _Event("e2"), _Event("e3")];

    test("keep their order and options through copyWith", () {
      final forward = PendingForward.many(events: events, timeline: null)
          .copyWith(showSender: true, hideCaption: true);
      expect(forward.events.map((e) => e.eventId), ["e1", "e2", "e3"]);
      expect(forward.event.eventId, "e1");
      expect(forward.showSender, isTrue);
      expect(forward.hideCaption, isTrue);
    });

    test("what is left after a failed send", () {
      final forward =
          PendingForward.many(events: events, timeline: null, showSender: true);
      final rest = forward.withoutFirst(1)!;
      expect(rest.events.map((e) => e.eventId), ["e2", "e3"]);
      expect(rest.showSender, isTrue);
      expect(forward.withoutFirst(0)!.events, hasLength(3));
      expect(forward.withoutFirst(3), isNull);
    });
  });
}
