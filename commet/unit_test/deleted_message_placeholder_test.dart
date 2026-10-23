// Vommet issue 306: the "Message deleted" placeholder.
import 'package:commet/client/matrix/matrix_deleted_message.dart';
import 'package:commet/client/timeline_events/timeline_event_deleted.dart';
import 'package:commet/ui/molecules/timeline_events/deleted_message_placeholder.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class _FakeClient extends Fake implements matrix.Client {}

final _room = matrix.Room(id: "!room:example.org", client: _FakeClient());

matrix.Event _event(String type,
    {Map<String, dynamic>? content, String? stateKey}) {
  return matrix.Event.fromJson({
    "type": type,
    "event_id": "\$event",
    "sender": "@alice:example.org",
    "origin_server_ts": 1700000000000,
    "content": content ?? {"msgtype": "m.text", "body": "hello"},
    if (stateKey != null) "state_key": stateKey,
  }, _room);
}

matrix.Event _redaction(
    {String sender = "@alice:example.org", String? reason}) {
  return matrix.Event.fromJson({
    "type": matrix.EventTypes.Redaction,
    "event_id": "\$redaction",
    "sender": sender,
    "origin_server_ts": 1700000060000,
    "redacts": "\$event",
    "content": {
      "redacts": "\$event",
      if (reason != null) "reason": reason,
    },
  }, _room);
}

matrix.Event _deleted(String type,
    {Map<String, dynamic>? content,
    String? stateKey,
    String sender = "@alice:example.org",
    String? reason}) {
  final event = _event(type, content: content, stateKey: stateKey);
  event.setRedactionEvent(_redaction(sender: sender, reason: reason));
  return event;
}

String _name(String id) => switch (id) {
      "@mod:example.org" => "Mod",
      _ => id,
    };

void main() {
  group("matrixDeletedMessageInfo", () {
    test("a message that wasn't deleted has no placeholder", () {
      expect(
          matrixDeletedMessageInfo(_event(matrix.EventTypes.Message)), isNull);
    });

    test("a message deleted by its sender", () {
      final info =
          matrixDeletedMessageInfo(_deleted(matrix.EventTypes.Message));
      expect(info, isNotNull);
      expect(info!.deletedBy, "@alice:example.org");
      expect(info.reason, isNull);
    });

    test("a message removed by a moderator keeps who and why", () {
      final info = matrixDeletedMessageInfo(_deleted(matrix.EventTypes.Message,
          sender: "@mod:example.org", reason: "  spam  "));
      expect(info!.deletedBy, "@mod:example.org");
      expect(info.reason, "spam");
    });

    test("a blank reason counts as none", () {
      final info = matrixDeletedMessageInfo(
          _deleted(matrix.EventTypes.Message, reason: "   "));
      expect(info!.reason, isNull);
    });

    test("a message deleted before it was loaded (server-side redaction)", () {
      final event = matrix.Event.fromJson({
        "type": matrix.EventTypes.Message,
        "event_id": "\$event",
        "sender": "@alice:example.org",
        "origin_server_ts": 1700000000000,
        "content": <String, dynamic>{},
        "unsigned": {"redacted_because": _redaction().toJson()},
      }, _room);
      expect(matrixDeletedMessageInfo(event), isNotNull);
    });

    test("encrypted messages, stickers and polls get a placeholder", () {
      for (final type in [
        matrix.EventTypes.Encrypted,
        matrix.EventTypes.Sticker,
        "org.matrix.msc3381.poll.start",
        "m.poll.start",
      ]) {
        expect(matrixDeletedMessageInfo(_deleted(type)), isNotNull,
            reason: type);
      }
    });

    test("deleted reactions and state events stay hidden", () {
      expect(
          matrixDeletedMessageInfo(
              _deleted(matrix.EventTypes.Reaction, content: {
            "m.relates_to": {
              "rel_type": "m.annotation",
              "event_id": "\$other",
              "key": "👍"
            }
          })),
          isNull);
      expect(
          matrixDeletedMessageInfo(_deleted(matrix.EventTypes.RoomMember,
              content: {"membership": "join"}, stateKey: "@alice:example.org")),
          isNull);
      expect(
          matrixDeletedMessageInfo(_deleted(matrix.EventTypes.RoomName,
              content: {"name": "x"}, stateKey: "")),
          isNull);
    });
  });

  group("deletedMessageText", () {
    test("deleted by the sender", () {
      expect(
          deletedMessageText(
              const DeletedMessageInfo(deletedBy: "@alice:example.org"),
              senderId: "@alice:example.org",
              nameOf: _name),
          "Message deleted");
    });

    test("deleter unknown", () {
      expect(
          deletedMessageText(const DeletedMessageInfo(),
              senderId: "@alice:example.org", nameOf: _name),
          "Message deleted");
    });

    test("deleted by someone else names them", () {
      expect(
          deletedMessageText(
              const DeletedMessageInfo(deletedBy: "@mod:example.org"),
              senderId: "@alice:example.org",
              nameOf: _name),
          "Message deleted by Mod");
    });

    test("adds the reason", () {
      expect(
          deletedMessageText(
              const DeletedMessageInfo(
                  deletedBy: "@mod:example.org", reason: "spam"),
              senderId: "@alice:example.org",
              nameOf: _name),
          "Message deleted by Mod (reason: spam)");
      expect(
          deletedMessageText(
              const DeletedMessageInfo(
                  deletedBy: "@alice:example.org", reason: "typo"),
              senderId: "@alice:example.org",
              nameOf: _name),
          "Message deleted (reason: typo)");
    });
  });

  test("placeholders are on unless the experiment is turned off", () {
    expect(experimentDeletedMessagePlaceholders.key,
        "vommet_experiment_deleted_message_placeholders");
    expect(experimentDeletedMessagePlaceholders.value, isTrue);
  });

  testWidgets("the placeholder is one muted, italic line", (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          child: DeletedMessagePlaceholder(
              text: "Message deleted by Mod (reason: ${"spam " * 20})"),
        ),
      ),
    ));

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.style?.fontStyle, FontStyle.italic);
    final context = tester.element(find.byType(Text));
    expect(text.style?.color, Theme.of(context).colorScheme.onSurfaceVariant);
    expect(tester.takeException(), isNull);
  });

  test("a placeholder ends a run of collapsed server events", () {
    // A hidden deleted event (a reaction, a state event, or any deleted
    // message with the experiment off) folds into the run; a placeholder
    // row breaks it, like any message.
    expect(
        TimelineViewEntryState.isEventTypeCollapsible(
            TimelineEventWidgetDisplayType.hidden),
        isTrue);
    expect(
        TimelineViewEntryState.isEventTypeCollapsible(
            TimelineEventWidgetDisplayType.deleted),
        isFalse);
    expect(
        TimelineViewEntryState.isEventTypeCollapsible(
            TimelineEventWidgetDisplayType.message),
        isFalse);
  });
}
