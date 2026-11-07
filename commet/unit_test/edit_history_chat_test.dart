// Vommet: exercise edit history through the mounted chat (Vommet issue 1097).
import 'dart:async';
import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';

const roomId = '!edits:example.com';
const olderId = r'$older';
const newerId = r'$newer';
const rootId = r'$root';
const olderReply = r'$older-reply';
const newerReply = r'$newer-reply';
const changed = 'I will bring the projector and adapter.';
const prompt = 'Send edit and continue';
const failure = 'Couldn\'t send this edit. Your changes are still here.';

matrix.MatrixEvent event(String id, String body, int order,
        {String sender = me, bool thread = false}) =>
    matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      eventId: id,
      senderId: sender,
      originServerTs:
          DateTime.fromMillisecondsSinceEpoch(1700000100000 + order),
      content: {
        'msgtype': 'm.text',
        'body': body,
        if (thread)
          'm.relates_to': {'rel_type': 'm.thread', 'event_id': rootId},
      },
    );

http.Response response(Map<String, Object?> json, [int status = 200]) =>
    http.Response(jsonEncode(json), status,
        headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final linux = TargetPlatformVariant.only(TargetPlatform.linux);
  late MatrixClient client;
  late Room room;
  late Timeline timeline;
  late List<Map<String, dynamic>> edits;
  late Future<http.Response> Function() finishSend;
  late Completer<void> requested;
  var index = 0;

  setUpAll(() async {
    await (FontLoader('RobotoCustom')
          ..addFont(rootBundle.load('assets/font/roboto/Roboto-Regular.ttf')))
        .load();
    await (FontLoader('NunitoSans')
          ..addFont(rootBundle.load(
              'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf')))
        .load();
  });

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.layoutOverride.set('desktop');
    await preferences.experimentMessageDrafts.set(false);
    await UnicodeEmojis.load();
    edits = [];
    requested = Completer<void>();
    finishSend = () async => response({'event_id': r'$saved'});
    final root = event(rootId, 'Thread root', 1, sender: '@bob:example.com');
    final replies = [
      event(newerReply, 'Newer reply', 5, thread: true),
      event(olderReply, 'Older reply', 4, thread: true),
    ];
    stubResponse = (request) async {
      final path = request.url.path;
      if (path.endsWith('/messages')) {
        return response({'chunk': [], 'start': 'previous'});
      }
      if (path.contains('/state/m.room.member/')) {
        return response({'membership': 'join', 'displayname': 'Bob'});
      }
      if (path.contains('/profile/')) return response({'displayname': 'Bob'});
      if (path.contains('/relations/')) {
        return response({
          'chunk': [for (final reply in replies) reply.toJson()],
          'original_event': root.toJson(),
        });
      }
      if (path.contains('/send/m.room.message/')) {
        edits.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (!requested.isCompleted) requested.complete();
        return finishSend();
      }
      return null;
    };
    client = await signedInClient('edit-history-${index++}');
    client.self = MatrixProfile(client, matrix.Profile(userId: me));
    clientManager = ClientManager();
    await sync(client, join: {
      roomId: matrix.JoinedRoomUpdate(
        state: roomState(roomId),
        timeline: matrix.TimelineUpdate(events: [
          root,
          event(olderId, 'Older message', 2),
          event(newerId, 'Newer message', 3),
          ...replies.reversed,
          event(r'$other', 'Another sender', 6, sender: '@bob:example.com'),
        ], prevBatch: 'previous'),
      ),
    });
    room = client.getRoom(roomId)!;
    timeline = await room.getTimeline();
  });

  tearDown(() async {
    stubResponse = null;
    clientManager = null;
    await timeline.close();
    await client.getMatrixClient().dispose(closeDatabase: true);
  });

  ChatState chat(WidgetTester tester) => tester.state(find.byType(Chat));
  Finder field = find.byType(TextField);
  TextEditingController editor(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!;

  Future<void> mount(WidgetTester tester, {String? thread}) async {
    final size = thread == null ? const Size(1000, 700) : const Size(370, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme.copyWith(platform: TargetPlatform.linux),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(1.25)),
        child: child!,
      ),
      home: Scaffold(
          body: Chat(room,
              key: ValueKey(thread),
              threadId: thread,
              focusMessageInput: true)),
    ));
    if (thread != null) {
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && chat(tester).timeline == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
    }
    await tester.pump();
    expect(chat(tester).timeline, isNotNull);
    await tester.tap(field);
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  Future<void> changeAndStep(WidgetTester tester, String text) async {
    await press(tester, LogicalKeyboardKey.arrowUp);
    await tester.enterText(field, text);
    editor(tester).selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.text(prompt), findsOneWidget,
        reason: 'A fresh Up on the changed edit opens confirmation');
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    // Optional WebRTC plugin is unavailable in the widget-test process.
    final error = tester.takeException();
    expect(error == null || error is MissingPluginException, isTrue,
        reason: error?.toString());
  }

  Future<void> waitForSend(WidgetTester tester) async {
    await tester
        .runAsync(() => requested.future.timeout(const Duration(seconds: 5)));
    await tester.pump();
  }

  Future<void> settleSend(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && chat(tester).processing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    expect(chat(tester).processing, isFalse);
  }

  testWidgets('mounted room steps older and newer among own room messages',
      (tester) async {
    await mount(tester);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(editor(tester).text, 'Older message');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(editor(tester).text, 'Older message');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(editor(tester).text, 'Newer message');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(editor(tester).text, 'Newer message');
    expect(edits, isEmpty);
    await unmount(tester);
  }, variant: linux);

  testWidgets('thread awaits the replacement request before stepping',
      (tester) async {
    final reply = Completer<http.Response>();
    finishSend = () => reply.future;
    await mount(tester, thread: rootId);
    await changeAndStep(tester, changed);
    await press(tester, LogicalKeyboardKey.enter);
    await waitForSend(tester);
    expect(edits.single['m.relates_to'],
        {'rel_type': 'm.replace', 'event_id': newerReply});
    expect(editor(tester).text, changed);
    await press(tester, LogicalKeyboardKey.enter);
    expect(edits, hasLength(1));
    reply.complete(response({'event_id': r'$saved-thread-edit'}));
    await settleSend(tester);
    expect(editor(tester).text, 'Older reply');
    expect(find.text(prompt), findsNothing);
    await unmount(tester);
  }, variant: linux);

  for (final scenario in ['blank', 'source removed', 'target removed']) {
    testWidgets('keeps the draft when confirmation is invalid: $scenario',
        (tester) async {
      await mount(tester);
      final text = scenario == 'blank' ? '' : changed;
      await changeAndStep(tester, text);
      if (scenario != 'blank') {
        final removed = scenario == 'source removed' ? newerId : olderId;
        timeline.events.removeWhere((event) => event.eventId == removed);
      }
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.text(failure), findsOneWidget);
      expect(edits, isEmpty);
      expect(editor(tester).text, text);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.text(prompt), findsNothing);
      expect(editor(tester).text, text);
      await unmount(tester);
    }, variant: linux);
  }

  testWidgets('rejected edit leaves the changed draft visible', (tester) async {
    finishSend = () async =>
        response({'errcode': 'M_FORBIDDEN', 'error': 'edit rejected'}, 403);
    await mount(tester);
    await changeAndStep(tester, changed);
    await press(tester, LogicalKeyboardKey.enter);
    await waitForSend(tester);
    await settleSend(tester);
    expect(find.text(failure), findsOneWidget);
    expect(editor(tester).text, changed);
    expect(edits, hasLength(1));
    await unmount(tester);
  }, variant: linux);

  testWidgets('successful edit exits if the destination disappears in flight',
      (tester) async {
    final reply = Completer<http.Response>();
    finishSend = () => reply.future;
    await mount(tester);
    await changeAndStep(tester, changed);
    await press(tester, LogicalKeyboardKey.enter);
    await waitForSend(tester);
    timeline.events.removeWhere((event) => event.eventId == olderId);
    reply.complete(response({'event_id': r'$saved-without-target'}));
    await settleSend(tester);
    expect(find.text('Edit sent.'), findsOneWidget);
    expect(editor(tester).text, isEmpty);
    expect(find.text(prompt), findsNothing);
    await unmount(tester);
  }, variant: linux);

  testWidgets('dirty edit survives switching to a thread and reopening room',
      (tester) async {
    await mount(tester);
    await changeAndStep(tester, changed);
    await mount(tester, thread: rootId);
    expect(editor(tester).text, isEmpty);
    await mount(tester);
    expect(editor(tester).text, changed);
    expect(find.text(prompt), findsNothing);
    expect(edits, isEmpty);
    await unmount(tester);
  }, variant: linux);

  testWidgets('completion after leaving a room does not change the open thread',
      (tester) async {
    final reply = Completer<http.Response>();
    finishSend = () => reply.future;
    await mount(tester);
    await changeAndStep(tester, changed);
    final key = chat(tester).draftKey;
    await press(tester, LogicalKeyboardKey.enter);
    await waitForSend(tester);
    await mount(tester, thread: rootId);
    expect(ChatState.drafts.get(key)?.text, changed);
    reply.complete(response({'event_id': r'$saved-after-leaving'}));
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && ChatState.drafts.get(key) != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    expect(ChatState.drafts.get(key), isNull);
    expect(editor(tester).text, isEmpty);
    expect(find.text(prompt), findsNothing);
    await unmount(tester);
  }, variant: linux);
}
