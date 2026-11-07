// Vommet issue 1022: the timeline only follows new messages from its bottom,
// so a reply sent from further up stayed out of view.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/scheduled_messages/scheduled_messages.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/message_box.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';

const a = "!a:example.com";

matrix.MatrixEvent message(String id, int n) => matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: {"msgtype": "m.text", "body": "body $id"},
      senderId: "@bob:example.com",
      eventId: id,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000100000 + n),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  late Timeline timeline;
  var n = 0;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await UnicodeEmojis.load();
    client = await signedInClient("jump-after-send-${n++}");
    client.self = MatrixProfile(client, matrix.Profile(userId: me));
    clientManager = ClientManager();
    await sync(
      client,
      join: {
        a: matrix.JoinedRoomUpdate(
          state: roomState(a),
          timeline: matrix.TimelineUpdate(
            events: [for (var i = 0; i < 80; i++) message("\$e$i", i)],
            prevBatch: "p",
          ),
        ),
      },
    );
    timeline = await client.getRoom(a)!.getTimeline();
  });

  tearDown(() async {
    clientManager = null;
    await timeline.close();
    await client.getMatrixClient().dispose(closeDatabase: true);
  });

  ChatState chat(WidgetTester tester) =>
      tester.state<ChatState>(find.byType(Chat));

  RoomTimelineWidgetViewState view(WidgetTester tester) => tester
      .state<RoomTimelineWidgetViewState>(find.byType(RoomTimelineWidgetView));

  // Runs [send] for real (the SDK's database and echo aren't fake-async), lets
  // the request finish and [until] come true, then lets any jump land.
  Future<void> run(WidgetTester tester, Future<void> Function() send,
      {bool Function()? until}) async {
    await tester.runAsync(() async {
      await send();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (var i = 0; i < 100 && until?.call() == false; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool newestIsMine() => timeline.events.first.senderId == me;

  Future<void> pumpChatScrolledUp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: SizedBox.expand(child: Chat(client.getRoom(a)!))),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    final state = view(tester);
    expect(state.firstFrame, isFalse);
    state.controller.jumpTo(state.controller.position.maxScrollExtent * .6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.attachedToBottom, isFalse);
  }

  bool newestRowShown(WidgetTester tester) {
    final state = view(tester);
    final row = state.eventKeys.first.$1.globalPaintBounds;
    final viewport = state.stackKey.globalPaintBounds!;
    return row != null && row.height > 0 && viewport.overlaps(row);
  }

  // The SDK's member lookups leave a one-minute timer, the message box its
  // keyboard height timers.
  Future<void> finish(WidgetTester tester) async {
    // WebRTC's plugin isn't there under flutter test (once per run).
    final error = tester.takeException();
    expect(error == null || error is MissingPluginException, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  testWidgets("a reply sent from further up lands on the reply",
      (tester) async {
    await pumpChatScrolledUp(tester);
    final state = chat(tester);
    state.setInteractingEvent(timeline.events[40],
        type: EventInteractionType.reply);
    await tester.pump();

    await run(tester, () async => state.sendMessage("my reply"),
        until: newestIsMine);

    expect(
        view(tester).timeline.events.first.senderId, client.self!.identifier);
    expect(newestRowShown(tester), isTrue);
    expect(view(tester).attachedToBottom, isTrue);
    await finish(tester);
  });

  testWidgets("a message that comes in during the jump is shown",
      (tester) async {
    await pumpChatScrolledUp(tester);
    view(tester).jumpToLatest();
    await tester.pump(const Duration(milliseconds: 100));
    expect(view(tester).animatingToBottom, isTrue);

    await run(
        tester,
        () => sync(client, join: {
              a: matrix.JoinedRoomUpdate(
                  timeline: matrix.TimelineUpdate(
                      events: [message(r"$during", 100)], prevBatch: "q")),
            }));

    expect(view(tester).timeline.events.first.eventId, r"$during");
    expect(view(tester).animatingToBottom, isFalse);
    expect(newestRowShown(tester), isTrue);
    await finish(tester);
  });

  testWidgets("an edit leaves the view where it is", (tester) async {
    await pumpChatScrolledUp(tester);
    final state = chat(tester);
    final offset = view(tester).controller.offset;
    await run(tester, () => client.getRoom(a)!.sendMessage(message: "mine"),
        until: newestIsMine);
    state.setInteractingEvent(timeline.events.first,
        type: EventInteractionType.edit);
    await tester.pump();

    await run(tester, () async => state.sendMessage("mine, edited"));

    expect(view(tester).animatingToBottom, isFalse);
    expect(view(tester).controller.offset, closeTo(offset, 200));
    expect(view(tester).attachedToBottom, isFalse);
    await finish(tester);
  });

  testWidgets("a scheduled message leaves the view where it is",
      (tester) async {
    await pumpChatScrolledUp(tester);
    final state = chat(tester);
    await run(tester, () async {
      ScheduledMessages.runScheduled(
          ScheduleRequest(DateTime.now().add(const Duration(hours: 1))),
          () => state.sendMessage("later"));
    });

    expect(view(tester).attachedToBottom, isFalse);
    await finish(tester);
  });

  testWidgets("/me lands on the message", (tester) async {
    await pumpChatScrolledUp(tester);
    await run(tester, () async => chat(tester).sendMessage("/me waves"),
        until: newestIsMine);

    expect(newestRowShown(tester), isTrue);
    expect(view(tester).attachedToBottom, isTrue);
    await finish(tester);
  });

  testWidgets("a command that posts nothing leaves the view where it is",
      (tester) async {
    await pumpChatScrolledUp(tester);
    await run(tester, () async => chat(tester).sendMessage("/clearemojistats"));

    expect(view(tester).attachedToBottom, isFalse);
    await finish(tester);
  });

  testWidgets("a send from the bottom doesn't rebuild the timeline",
      (tester) async {
    await pumpChatScrolledUp(tester);
    final state = view(tester);
    state.controller.jumpTo(state.controller.position.minScrollExtent);
    await tester.pump();
    final key = state.eventKeys.first.$1;

    await run(tester, () async => chat(tester).sendMessage("hello"),
        until: newestIsMine);

    expect(state.eventKeys.map((e) => e.$1), contains(key));
    expect(newestRowShown(tester), isTrue);
    await finish(tester);
  });

  testWidgets("a send from the bottom of a far jump returns to the live page",
      (tester) async {
    await pumpChatScrolledUp(tester);
    final state = view(tester);
    // A far jump shows its own timeline; the chat keeps the live one.
    late Timeline around;
    await tester
        .runAsync(() async => around = await client.getRoom(a)!.getTimeline());
    addTearDown(() => around.close());
    state.initFromTimeline(around);
    tester.element(find.byType(RoomTimelineWidgetView)).markNeedsBuild();
    await tester.pump();
    state.controller.jumpTo(state.controller.position.minScrollExtent);
    await tester.pump();
    expect(state.attachedToBottom, isTrue);

    await run(tester, () async => chat(tester).sendMessage("hello"),
        until: newestIsMine);

    expect(state.timeline, chat(tester).timeline);
    expect(newestRowShown(tester), isTrue);
    await finish(tester);
  });

  // Vommet issue 1111: the room composer opts into the shared field inset.
  testWidgets("the room composer uses the shared chat field inset",
      (tester) async {
    await pumpChatScrolledUp(tester);
    final input = find.byType(MessageInput).first;
    expect(tester.widget<MessageInput>(input).insetChatField, isTrue);
    final box = find.descendant(of: input, matching: find.byType(MessageBox));
    expect(tester.widget<MessageBox>(box.first).minimumHeight,
        MessageBox.chatMinimumHeight);
    await finish(tester);
  });
}
