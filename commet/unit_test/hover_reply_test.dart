// Vommet issue 1069: exercise the real chat, hit testing, settings and keyboard.
import 'dart:convert';

import 'package:commet/cache/file_cache.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_widget.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/pages/settings/categories/app/shortcut_settings/shortcut_settings_page.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:commet/utils/timeline_selection.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';

const roomId = '!a:example.com';
const bindingKey = 'vommet_hover_reply_key';
String binding(
        [LogicalKeyboardKey key = LogicalKeyboardKey.keyR,
        PhysicalKeyboardKey physical = PhysicalKeyboardKey.keyR]) =>
    jsonEncode({
      'key': key.keyId,
      'physical': physical.usbHidUsage,
      'modifiers': [HotKeyModifier.control.index, HotKeyModifier.shift.index],
    });

// Hit testing needs decoded pictures, not a media download under the fake clock.
class _Pictures extends Fake implements FileCache {
  @override
  Future<bool> hasFile(String id, {bool sensitive = false}) async => true;
  @override
  Future<Uint8List?> readFile(String id, {bool sensitive = false}) async =>
      base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MatrixClient client;
  late Timeline timeline;
  var serial = 0;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    messagesResponse = (_) => {'chunk': <Object>[], 'start': 'p', 'end': 'p'};
    await preferences.autoFocusMessageTextBox.set(false);
    await UnicodeEmojis.load();
    await BridgedUsers.mark.set(false);
    client = await signedInClient('hover-reply-${serial++}');
    client.self = MatrixProfile(client, matrix.Profile(userId: me));
    clientManager = ClientManager();
    await sync(client, join: {
      roomId: matrix.JoinedRoomUpdate(
          state: [
            ...roomState(roomId),
            stateEvent(
                "m.room.member", {"membership": "join", "displayname": "Alex"},
                stateKey: "@bob:example.com")
          ],
          timeline: matrix.TimelineUpdate(events: [
            matrix.MatrixEvent(
                type: matrix.EventTypes.Message,
                content: {'msgtype': 'm.emote', 'body': 'waves'},
                senderId: '@bob:example.com',
                eventId: r'$emote',
                originServerTs: DateTime(2026, 11, 2, 11, 59)),
            for (var i = 0; i < 4; i++)
              matrix.MatrixEvent(
                  type: matrix.EventTypes.Message,
                  content: {'msgtype': 'm.text', 'body': 'Review message $i'},
                  senderId: i.isEven ? '@bob:example.com' : me,
                  eventId: '\$message$i',
                  originServerTs: DateTime(2026, 11, 2, 12, i)),
          ], prevBatch: 'p'))
    });
    timeline = await client.getRoom(roomId)!.getTimeline();
    await timeline.loadMoreHistory();
  });
  tearDown(() async {
    TimelineSelection.current.value = null;
    for (final shortcut in SystemWideShortcuts.shortcuts.values) {
      shortcut.hotkey = null;
    }
    stubResponse = null;
    messagesResponse = null;
    clientManager = null;
    await timeline.close();
    await client.getMatrixClient().dispose(closeDatabase: true);
  });
  Future<void> configure() async =>
      (await SharedPreferences.getInstance()).setString(bindingKey, binding());
  Future<void> chord(WidgetTester tester, {bool repeat = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    if (repeat) await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<TestGesture> hover(WidgetTester tester, String text,
      {Finder? scope}) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter((scope == null
            ? find.text(text)
            : find.descendant(of: scope, matching: find.text(text)))
        .first));
    await tester.pump();
    addTearDown(mouse.removePointer);
    return mouse;
  }

  Future<void> pump(WidgetTester tester,
      {Widget? child, Size size = const Size(1280, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(body: child ?? Chat(client.getRoom(roomId)!))));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  ChatState chat(WidgetTester tester) =>
      tester.state<ChatState>(find.byType(Chat).first);

  for (final layout in [
    ('Discord', LayoutOptions.discord),
    ('Telegram', LayoutOptions.telegram),
    (
      'Custom',
      const LayoutOptions(
          oneChatList: true,
          captionBelow: false,
          limitWidth: false,
          bubbles: true,
          ownSide: OwnBubbleSide.right,
          avatarAtBottom: true)
    )
  ]) {
    testWidgets(
        '${layout.$1}: unbound then reply under pointer preserves draft',
        (tester) async {
      await layout.$2.save();
      await pump(tester);
      final mouse = await hover(tester, 'Review message 2');
      await chord(tester);
      expect(chat(tester).interactingEvent, isNull);
      await configure();
      final input = tester.state<MessageInputState>(find.byType(MessageInput));
      input.controller.text = 'Keep this draft';
      input.controller.selection = const TextSelection.collapsed(offset: 15);
      await chord(tester, repeat: true);
      expect(chat(tester).interactingEvent?.eventId, r'$message2');
      expect(chat(tester).interactionType, EventInteractionType.reply);
      expect(input.controller.text, 'Keep this draft');
      await mouse.moveTo(tester.getCenter(find.text('*Alex waves').first));
      await chord(tester);
      expect(chat(tester).interactingEvent?.eventId, r'$emote');
      chat(tester).setInteractingEvent(null);
      await tester.pump();
      await mouse.moveTo(const Offset(1, 1));
      await chord(tester);
      expect(chat(tester).interactingEvent, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  }

  testWidgets(
      'selection, IME, sent-message edits, dialogs and call collisions preserve reply target',
      (tester) async {
    await configure();
    await pump(tester);
    final mouse = await hover(tester, 'Review message 2');
    await chord(tester);
    expect(chat(tester).interactingEvent?.eventId, r'$message2');
    chat(tester).setInteractingEvent(null);
    await tester.pump();
    final input = tester.state<MessageInputState>(find.byType(MessageInput));
    input.controller.value = const TextEditingValue(
        text: 'draft',
        selection: TextSelection(baseOffset: 0, extentOffset: 5));
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    input.controller.value = const TextEditingValue(
        text: 'draft',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5));
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    input.controller.value = const TextEditingValue(
        text: 'draft', selection: TextSelection.collapsed(offset: 5));
    TimelineSelection.current.value = 'Review';
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    TimelineSelection.current.value = null;
    final selection = MessageSelectionScope.maybeOf(
        tester.element(find.byType(RoomTimelineWidget)))!;
    selection.start([r'$message2']);
    await tester.pump();
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    selection.exit();
    await tester.pump();
    clientManager!.callManager.playSounds = false;
    await preferences.voipPushToTalk.set(true);
    await tester.pump();
    clientManager!.callManager.pushToTalk.press('test');
    expect(clientManager!.callManager.pushToTalk.talking, isTrue);
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    clientManager!.callManager.pushToTalk.reset();
    await preferences.voipPushToTalk.set(false);
    chat(tester).setInteractingEvent(
        chat(tester).timeline!.tryGetEvent(r'$message3'),
        type: EventInteractionType.edit);
    await tester.pump();
    await chord(tester);
    expect(chat(tester).interactionType, EventInteractionType.edit);
    chat(tester).setInteractingEvent(null);
    await tester.pump();
    SystemWideShortcuts.shortcuts['push_to_talk']!.hotkey = HotKey(
        key: PhysicalKeyboardKey.keyR,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift]);
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    SystemWideShortcuts.shortcuts['push_to_talk']!.hotkey = null;
    final context = tester.element(find.byType(Chat));
    showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Modal')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull,
        reason: 'closing a dialog requires fresh hover');
    await mouse.moveTo(tester.getCenter(find.text('Review message 2').first) +
        const Offset(2, 0));
    await chord(tester);
    expect(chat(tester).interactingEvent?.eventId, r'$message2');
    chat(tester).setInteractingEvent(null);
    await tester.pump();
    await tester.runAsync(() => sync(client, join: {
          roomId: matrix.JoinedRoomUpdate(state: [
            stateEvent('m.room.power_levels', {
              'users': {me: 0},
              'events': {'m.room.message': 50}
            })
          ])
        }));
    await tester.pump();
    expect(client.getRoom(roomId)!.permissions.canSendMessage, isFalse);
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
      'hover owns the room or thread, including a shared root and close',
      (tester) async {
    await configure();
    Map<String, Object> event(String id, String text, {bool thread = false}) =>
        {
          'type': 'm.room.message',
          'event_id': id,
          'sender': '@bob:example.com',
          'origin_server_ts': 1700000100000,
          'content': {
            'msgtype': 'm.text',
            'body': text,
            if (thread)
              'm.relates_to': {
                'rel_type': 'm.thread',
                'event_id': r'$message2',
                'm.in_reply_to': {'event_id': r'$message2'}
              }
          }
        };
    stubResponse = (request) => request.url.path.contains('/relations/')
        ? http.Response(
            jsonEncode({
              'chunk': [event(r'$thread', 'Thread reply', thread: true)],
              'original_event': event(r'$message2', 'Review message 2')
            }),
            200,
            headers: {'content-type': 'application/json'})
        : null;
    final room = client.getRoom(roomId)!;
    const mainKey = ValueKey('main-chat'), threadKey = ValueKey('thread-chat');
    await pump(tester,
        child: Row(children: [
          Expanded(child: Chat(room, key: mainKey)),
          SizedBox(
              width: 420,
              child: Chat(room, key: threadKey, threadId: r'$message2'))
        ]));
    for (var i = 0; i < 15; i++) {
      await tester.pump();
    }
    final main = tester.state<ChatState>(find.byKey(mainKey));
    final thread = tester.state<ChatState>(find.byKey(threadKey));
    expect(thread.threadsComponent, isNotNull);
    await tester.runAsync(() async {
      final extra = await thread.threadsComponent!.getThreadTimeline(
          roomTimeline: timeline, threadRootEventId: r'$message2');
      await extra?.close();
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(thread.timeline?.events.map((e) => e.plainTextBody),
        contains('Thread reply'));
    final mouse =
        await hover(tester, 'Thread reply', scope: find.byKey(threadKey));
    await chord(tester);
    expect(thread.interactingEvent?.eventId, r'$thread');
    expect(main.interactingEvent, isNull);
    final root = find.descendant(
        of: find.byKey(mainKey), matching: find.text('Review message 2'));
    await mouse.moveTo(tester.getCenter(root.first));
    await chord(tester);
    expect(main.interactingEvent?.eventId, r'$message2');
    expect(thread.interactingEvent?.eventId, r'$thread');
    main.setInteractingEvent(null);
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
            body: Row(children: [Expanded(child: Chat(room, key: mainKey))]))));
    await tester.pump();
    await chord(tester);
    expect(main.interactingEvent, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
      'wheel preserves the pointer and blur, drag and foreign focus block Reply',
      (tester) async {
    await configure();
    final outside = FocusNode();
    addTearDown(outside.dispose);
    await pump(tester,
        child: Column(children: [
          TextField(focusNode: outside),
          Expanded(child: Chat(client.getRoom(roomId)!)),
        ]));
    final mouse = await hover(tester, 'Review message 2');
    final point = tester.getCenter(find.text('Review message 2').first);
    tester.binding.handlePointerEvent(PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: point,
      scrollDelta: const Offset(0, -40),
      viewId: tester.view.viewId,
    ));
    await tester.pump();
    await chord(tester);
    expect(chat(tester).interactingEvent?.eventId, r'$message1',
        reason: 'Reply must hit the row now under the stationary pointer');
    chat(tester).setInteractingEvent(null);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    await mouse.moveTo(point);
    await mouse.down(point);
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    await mouse.up();
    await mouse.moveTo(point);
    outside.requestFocus();
    await tester.pump();
    await chord(tester);
    expect(chat(tester).interactingEvent, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('mosaic reply uses the hit picture, not the last menu target',
      (tester) async {
    await configure();
    await LayoutOptions.discord.save();
    await preferences.groupConsecutiveMedia.set(true);
    await preferences.previewMediaInPublicRooms.set(true);
    await preferences.previewMediaInPrivateRooms.set(true);
    final previousCache = fileCache;
    fileCache = _Pictures();
    addTearDown(() => fileCache = previousCache);
    await tester.runAsync(() => sync(client, join: {
          roomId: matrix.JoinedRoomUpdate(
              state: [
                stateEvent('m.room.join_rules', {'join_rule': 'invite'})
              ],
              timeline: matrix.TimelineUpdate(events: [
                for (var i = 0; i < 2; i++)
                  matrix.MatrixEvent(
                      type: matrix.EventTypes.Message,
                      senderId: '@bob:example.com',
                      eventId: '\$pic$i',
                      originServerTs: DateTime(2026, 11, 2, 12, 5, i),
                      content: {
                        'msgtype': 'm.image',
                        'body': 'picture$i.png',
                        'filename': 'picture$i.png',
                        'url': 'mxc://example.com/pic$i',
                        'info': {'w': 400, 'h': 300, 'mimetype': 'image/png'}
                      })
              ]))
        }));
    await pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    for (final id in [r'$pic1', r'$pic0']) {
      final tile = find.byKey(ValueKey(id));
      expect(tile, findsOneWidget);
      await mouse.moveTo(tester.getCenter(tile));
      await chord(tester);
      expect(chat(tester).interactingEvent?.eventId, id);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
      'settings record, reject plain text, cancel, save, reject inverse call bind, clear',
      (tester) async {
    await pump(tester,
        child: const SingleChildScrollView(child: ShortcutSettingsPage()));
    expect(find.text('Reply to message under pointer'), findsOneWidget);
    await tester.tap(find.text('Set shortcut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(
        (await SharedPreferences.getInstance()).getString(bindingKey), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Set shortcut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await chord(tester);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect((await SharedPreferences.getInstance()).getString(bindingKey),
        isNotNull);
    expect(find.text('Ctrl + Shift + R'), findsOneWidget);
    await expectLater(
        SystemWideShortcuts.shortcuts['push_to_talk']!.setHotkey(HotKey(
            key: PhysicalKeyboardKey.keyR,
            modifiers: [HotKeyModifier.control, HotKeyModifier.shift])),
        throwsArgumentError);
    await tester.tap(find.text('Change shortcut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ctrl + Shift + R'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect((await SharedPreferences.getInstance()).containsKey(bindingKey),
        isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });
  for (final size in [const Size(360, 800), const Size(320, 640)]) {
    testWidgets('settings wrap at $size without MOBILE define', (tester) async {
      await pump(tester,
          size: size,
          child: const SingleChildScrollView(child: ShortcutSettingsPage()));
      expect(find.text('Set shortcut'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Set shortcut'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Set reply shortcut'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  }
}
