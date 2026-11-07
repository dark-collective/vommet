import 'dart:convert';

import 'package:commet/config/layout_style.dart';
import 'package:commet/config/room_layout_options.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:commet/ui/pages/main/room_chat_layout.dart';
import 'package:commet/ui/pages/main/room_primary_view.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tiamat/config/style/theme_dark.dart';

import 'helpers/navigation_fixture.dart';
import 'roomlist_fixture.dart' as sdk;
import 'support/room_page_fixtures.dart' as rooms;

// Vommet issue 1189: real Matrix-backed Chat and RoomSidePanel, with the
// homeserver transport stubbed by the shared fixture. No app/build or network.
Future<void> threadScreenSetUp() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
  await rooms.roomPageSetUp();
  // Real font metrics: Ahem makes the date divider wider than the actual UI.
  for (final (family, path) in [
    ('RobotoCustom', 'assets/font/roboto/Roboto-Regular.ttf'),
    (
      'NunitoSans',
      'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf'
    ),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(path))).load();
  }
  sdk.stubResponse = (request) {
    if (request.url.path.endsWith('/messages')) {
      return http.Response('{"chunk":[],"start":"p","end":"p"}', 200,
          headers: {'content-type': 'application/json'});
    }
    if (request.url.path.contains('/event/')) {
      return http.Response(
          jsonEncode({
            'event_id': r'$m38',
            'sender': sdk.me,
            'origin_server_ts': 1700000138000,
            'type': 'm.room.message',
            'content': {'msgtype': 'm.text', 'body': 'message 38'}
          }),
          200,
          headers: {'content-type': 'application/json'});
    }
    if (request.url.path.contains('/profile/')) {
      return http.Response('{"displayname":"Bob"}', 200,
          headers: {'content-type': 'application/json'});
    }
    if (request.url.path.contains('/state/m.room.member/')) {
      return http.Response('{"membership":"join","displayname":"Bob"}', 200,
          headers: {'content-type': 'application/json'});
    }
    if (!request.url.path.contains('/relations/')) return null;
    return http.Response(
        jsonEncode({
          'chunk': [
            for (var i = 3; i > 0; i--)
              {
                'event_id': '\$reply$i',
                'sender': sdk.me,
                'origin_server_ts': 1700000200000 + i * 1000,
                'type': 'm.room.message',
                'content': {
                  'msgtype': 'm.text',
                  'body': 'A quick reply in this thread ($i).',
                  'm.relates_to': {'rel_type': 'm.thread', 'event_id': r'$m38'}
                }
              }
          ],
          'original_event': {
            'event_id': r'$m38',
            'sender': sdk.me,
            'origin_server_ts': 1700000138000,
            'type': 'm.room.message',
            'content': {'msgtype': 'm.text', 'body': 'message 38'}
          }
        }),
        200,
        headers: {'content-type': 'application/json'});
  };
  await resizablePanels.set(true);
  await preferences.autoFocusMessageTextBox.set(false);
}

Future<void> threadScreenTearDown() async {
  sdk.stubResponse = null;
  await rooms.roomPageTearDown();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Event'), null);
}

const threadScreenKey = ValueKey('1189-screen');

Future<void> pumpThreadScreen(WidgetTester tester,
    {required LayoutStyle style,
    bool phone = false,
    double width = 1440}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = phone ? const Size(390, 844) : Size(width, 900);
  await preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
  await pickLayoutStyle(style);
  if (style == LayoutStyle.custom) {
    await LayoutOptions.discord.save();
    await preferences.chatBubbleLayout.set(true);
  }
  final room = rooms.roomFor(rooms.RoomCase.messages);
  final page = NavigationPageFixture(clientManager!)..currentRoom = room;
  final header = SizedBox(
      height: 50,
      child: ListTile(
          title: Text(room.displayName),
          leading: const Icon(Icons.tag),
          trailing: const Icon(Icons.more_horiz)));
  await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: RepaintBoundary(
          key: threadScreenKey,
          child: Material(
              child: phone
                  // Real phone side-panel content in the revealed state.
                  // Reveal/swipe mechanics are covered by overlapping_panels*.
                  ? RoomSidePanel(state: page)
                  : Row(children: [
                      SizedBox(
                          width: 320,
                          child: ListView(children: [
                            const ListTile(title: Text('Design space')),
                            for (final name in ['general', 'design', 'photos'])
                              ListTile(
                                  leading: const Icon(Icons.tag),
                                  title: Text(name))
                          ])),
                      Expanded(
                          child: RoomChatLayout(
                              room: room,
                              header: header,
                              chat: RoomPrimaryView(room),
                              panel: (changed) => RoomSidePanel(
                                  state: page, onStateChanged: changed)))
                    ])))));
  await rooms.settle(tester);
  EventBus.openThread.add((room.client.identifier, room.identifier, r'$m38'));
  await rooms.settle(tester);
  await tester.runAsync(() async {
    // Drain SDK/database futures without a wall-clock delay.
    await room.getTimeline();
  });
  await rooms.settle(tester);
}

void main() {
  setUp(threadScreenSetUp);
  tearDown(threadScreenTearDown);
  for (final style in LayoutStyle.values) {
    testWidgets(
        '1189 ${style.name}: real thread drag and explicit phone content',
        (tester) async {
      addTearDown(tester.view.reset);
      await pumpThreadScreen(tester, style: style);
      expect(tester.takeException(), isNull);
      expect(find.byType(MessageInput), findsNWidgets(2));
      final handle = find.byWidgetPredicate(
          (w) => w is PaneResizeHandle && !identical(w.pane, PaneWidths.left));
      expect(handle, findsOneWidget);
      await tester.drag(handle, const Offset(260, 0));
      await rooms.settle(tester);
      expect(tester.takeException(), isNull);
      final inputs = find.byType(MessageInput);
      expect(tester.getTopLeft(inputs.last).dx,
          greaterThan(tester.getTopLeft(inputs.first).dx + 600));
      // Real composer text survives resizing without replacing the Chat.
      final field =
          find.descendant(of: inputs.last, matching: find.byType(TextField));
      await tester.enterText(field.first, 'Keep this draft');
      await tester.drag(handle, const Offset(-40, 0));
      await rooms.settle(tester);
      expect(find.text('Keep this draft'), findsOneWidget);
      EventBus.closeThread.add(null);
      await rooms.settle(tester);
      expect(tester.takeException(), isNull);
      final room = rooms.roomFor(rooms.RoomCase.messages);
      EventBus.openThread
          .add((room.client.identifier, room.identifier, r'$m38'));
      await rooms.settle(tester);
      expect(find.byType(MessageInput), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await rooms.finishRoomPage(tester);
      await pumpThreadScreen(tester, style: style, phone: true);
      expect(tester.takeException(), isNull);
      expect(find.byType(PaneResizeHandle), findsNothing);
      expect(find.byType(MessageInput), findsOneWidget);
      expect(find.textContaining('A quick reply', findRichText: true),
          findsWidgets);
      final input = tester.getRect(find.byType(MessageInput));
      expect(input.right, lessThanOrEqualTo(390));
      expect(input.bottom, lessThanOrEqualTo(844));
      await rooms.finishRoomPage(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }
}
