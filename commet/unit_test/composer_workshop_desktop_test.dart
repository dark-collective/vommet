import 'dart:convert';
import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/config/composer_workshop.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/current_session_panel.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/main/main_page_view_desktop.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as mx;
import 'package:provider/provider.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_gradient.dart';
import 'package:tiamat/config/style/theme_light.dart';

import 'roomlist_fixture.dart' as server;
import 'support/composer_capture.dart' as render;
import 'support/composer_workshop_fixture.dart' as fixture;
import 'support/room_page_fixtures.dart';

class PreviewMain extends Fake with Diagnosticable implements MainPageState {
  PreviewMain(this.clientManager, this.currentRoom, this.currentSpace);
  @override
  final ClientManager clientManager;
  @override
  final Room currentRoom;
  @override
  final Space currentSpace;
  @override
  Client? get filterClient => null;
  @override
  Profile? get currentUser => roomPageClient.self;
  @override
  bool get showAsTextRoom => false;
  @override
  MainPageSubView get currentView => MainPageSubView.space;
}

const root = ValueKey('full-desktop-shell');
Map<String, dynamic> event(int i, String body) => {
      'event_id': i == 0 ? r'$m0' : '\$reply$i',
      'type': 'm.room.message',
      'sender': i.isEven ? server.me : '@bob:example.com',
      'origin_server_ts': 1700000100000 + i * 1000,
      'content': {
        'msgtype': 'm.text',
        'body': body,
        if (i != 0) 'm.relates_to': {'rel_type': 'm.thread', 'event_id': r'$m0'}
      }
    };
void main() {
  setUp(() async {
    final avatar =
        File('assets/images/placeholders/avatar1.jpg').readAsBytesSync();
    final banner =
        File('assets/images/placeholders/photos/pexels-fr3nks-287229.jpg')
            .readAsBytesSync();
    server.stubResponse = (request) {
      final path = request.url.path;
      if (path.contains('/download/') || path.contains('/thumbnail/'))
        return http.Response.bytes(
            path.contains('banner') ? banner : avatar, 200,
            headers: {'content-type': 'image/jpeg'});
      Object? body;
      if (path.contains('/event/'))
        body = event(0, 'Composer layout discussion');
      if (path.endsWith('/notifications')) body = {'notifications': []};
      if (path.endsWith('/state')) body = [];
      if (path.contains('/relations/'))
        body = {
          'chunk': [
            event(
                2, 'That sounds good. The thread should behave the same way.'),
            event(1, 'Let’s check the room and thread side by side.')
          ],
          'original_event': event(0, 'Composer layout discussion')
        };
      if (path.endsWith('/messages'))
        body = {'chunk': [], 'state': [], 'start': 'p'};
      if (path.contains('/state/m.room.member/'))
        body = {'membership': 'join', 'displayname': 'Bob'};
      if (path.contains('/profile/'))
        body = {
          'displayname': path.contains('bob') ? 'Bob' : 'Dark Collective',
          'avatar_url': 'mxc://example.com/avatar'
        };
      return body == null
          ? null
          : http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json'});
    };
    await fixture.alignmentSetUp();
    await preferences.experimentComposerWorkshop.set(true);
    await preferences.layoutOverride.set('desktop');
    await pickLayoutStyle(LayoutStyle.discord);
    await preferences.hideRoomSidePanel.set(true);
    await preferences.experimentQuickProfileControls.set(true);
    final rooms = <String, String>{
      callRoom: 'Vommet',
      '!bridge:example.com': 'Nether Voice Bridge',
      '!widgets:example.com': 'Nether Widgets',
      '!git:example.com': 'Git Update Spam',
      '!voicechat:example.com': 'Voice Discussion',
      '!light:example.com': 'Light Chat',
      '!tech:example.com': 'Science & Tech',
      '!rules:example.com': 'Rules & Announcements',
      '!testing1:example.com': 'Auto Test 01',
      '!testing2:example.com': 'Auto Test 02',
      '!testing3:example.com': 'Auto Test 03'
    };
    final entries = <String, mx.JoinedRoomUpdate>{
      for (final e in rooms.entries) e.key: server.joined(e.key, name: e.value)
    };
    entries['!software:example.com'] = server.joined('!software:example.com',
        name: 'Software Development',
        children: [
          callRoom,
          '!bridge:example.com',
          '!widgets:example.com',
          '!git:example.com',
          '!voicechat:example.com'
        ]);
    entries['!testing:example.com'] = server.joined('!testing:example.com',
        name: 'Automated Testing',
        children: [
          '!testing1:example.com',
          '!testing2:example.com',
          '!testing3:example.com'
        ]);
    entries['!lightnet:example.com'] = server.joined('!lightnet:example.com',
        name: 'Light Network',
        children: [
          '!light:example.com',
          '!tech:example.com',
          '!rules:example.com'
        ]);
    entries['!nether:example.com'] = mx.JoinedRoomUpdate(state: [
      ...server.roomState('!nether:example.com', name: 'Nether', children: [
        '!software:example.com',
        '!testing:example.com',
        '!lightnet:example.com'
      ]),
      server.stateEvent('page.codeberg.everypizza.room.banner',
          {'url': 'mxc://example.com/banner'}),
      server.stateEvent('m.room.avatar', {'url': 'mxc://example.com/avatar'})
    ]);
    for (final (name, id) in [
      ('Dark Network', 'dark'),
      ('Community', 'community'),
      ('Projects', 'projects'),
      ('Friends', 'friends')
    ]) {
      entries['!$id:example.com'] =
          server.joined('!$id:example.com', name: name, children: []);
    }
    const messages = [
      'I’m reworking the text box designs.',
      'The account bar should line up with the navigation above it.',
      'The spaces rail stays above the account controls, alongside the room list.',
      'I’d keep the panels square, like the rest of the desktop layout.',
      'The composer grows upward, while the buttons stay at the bottom.',
      'A longer draft should offer a separate compose window.',
      'We should check this with a thread open, too.',
      'Yes, both composers should start at the same height.'
    ];
    entries[callRoom] = mx.JoinedRoomUpdate(
        state: [
          ...server.roomState(callRoom, name: 'Vommet'),
          server.stateEvent(
              'm.room.topic', {'topic': 'Matrix client and community updates'}),
          server.stateEvent(
              'm.room.member',
              {
                'membership': 'join',
                'displayname': 'Dark Collective',
                'avatar_url': 'mxc://example.com/avatar'
              },
              stateKey: server.me),
          server.stateEvent(
              'm.room.member',
              {
                'membership': 'join',
                'displayname': 'Bob',
                'avatar_url': 'mxc://example.com/avatar'
              },
              stateKey: '@bob:example.com')
        ],
        timeline: mx.TimelineUpdate(events: [
          for (var i = 0; i < 40; i++)
            mx.MatrixEvent(
                type: 'm.room.message',
                content: {
                  'msgtype': 'm.text',
                  'body': messages[i % messages.length]
                },
                senderId: i.isEven ? server.me : '@bob:example.com',
                eventId: '\$m$i',
                originServerTs: DateTime.fromMillisecondsSinceEpoch(
                    1700000100000 + i * 60000))
        ], prevBatch: 'p'));
    await server.sync(roomPageClient, join: entries);
    roomPageClient.self = MatrixProfile(
        roomPageClient,
        mx.Profile(
            userId: server.me,
            displayName: 'Dark Collective',
            avatarUrl: Uri.parse('mxc://example.com/avatar')));
    clientManager!.addClient(roomPageClient);
  });
  tearDown(() async {
    await fixture.alignmentTearDown();
    server.stubResponse = null;
  });
  for (final style in LayoutStyle.values) {
    for (final (themeName, themeData) in [
      ('dark', ThemeDark.theme),
      ('light', ThemeLight.theme),
      ('amoled', ThemeAmoled.theme),
      ('retro-storm', ThemeGradient.theme(ThemeGradient.byId('retro-storm')!))
    ]) {
      testWidgets(
          '$themeName ${style.name} full desktop: spaces, room list, account, room and thread',
          (t) async {
        addTearDown(t.view.reset);
        await pickLayoutStyle(style);
        await render.fonts(t);
        t.view.physicalSize = const Size(1909, 1148);
        t.view.devicePixelRatio = 1;
        final space = roomPageClient.getSpace('!nether:example.com')!;
        final state =
            PreviewMain(clientManager!, roomFor(RoomCase.messages), space);
        final theme = themeData;
        await t.pumpWidget(Provider<ClientManager>.value(
            value: clientManager!,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                home: Scaffold(
                    body: RepaintBoundary(
                        key: root,
                        child: GlobalRedactionScope(
                            child: OverlayWindowsManager(
                                child: Padding(
                                    padding: EdgeInsets.zero,
                                    child: ComposerWorkshopScope(
                                        child:
                                            MainPageViewDesktop(state))))))))));
        await settle(t);
        await settle(t);
        EventBus.onSelectedSpaceChanged.add(space);
        EventBus.onSelectedRoomChanged.add(state.currentRoom);
        await settle(t);
        Finder inputFor(bool thread) => find.descendant(
            of: find.byWidgetPredicate(
                (w) => w is Chat && (w.threadId != null) == thread),
            matching: find.byType(TextField));
        Rect boxFor(bool thread) => t.getRect(find.descendant(
            of: find.byWidgetPredicate(
                (w) => w is Chat && (w.threadId != null) == thread),
            matching: find.byKey(const ValueKey('composer-input'))));
        void check(bool thread) {
          expect(find.byType(SideNavigationBar),
              style == LayoutStyle.telegram ? findsNothing : findsOneWidget);
          expect(find.byType(CurrentSessionPanel), findsOneWidget);
          final account =
              t.getRect(find.byKey(const ValueKey('composer-account-bar')));
          final room = boxFor(false);
          final nav = t.getRect(find
              .ancestor(
                  of: find.byType(CurrentSessionPanel),
                  matching: find.byType(Column))
              .last);
          expect(nav.left, closeTo(account.left - 8, .1));
          expect(nav.right, closeTo(account.right + 8, .1));
          expect(account.bottom, closeTo(room.bottom, .1));
          expect(account.left, closeTo(8, .1));
          expect(account.bottom, closeTo(1140, .1));
          expect(room.left - account.right, closeTo(16, .1));
          if (thread) {
            final other = boxFor(true);
            expect(other.bottom, closeTo(room.bottom, .1));
            expect(other.left - room.right, closeTo(16, .1));
            expect(other.right, closeTo(1901, .1));
          }
          if (!thread) expect(room.right, closeTo(1901, .1));
          expect(find.byType(Dialog), findsNothing);
          expect(t.takeException(), isNull);
        }

        await preferences.experimentComposerWorkshop.set(false);
        await settle(t);
        await render.capture(t, '$themeName-${style.name}-before-no-thread',
            surface: root);
        await preferences.experimentComposerWorkshop.set(true);
        await settle(t);
        await t.enterText(inputFor(false), '');
        await settle(t);
        check(false);
        expect(boxFor(false).height, 44);
        expect(
            boxFor(false).height,
            t
                .getSize(find.byKey(const ValueKey('composer-account-bar')))
                .height);
        final initialButtons = <String, double>{
          for (final key in ['composer-attach', 'composer-voice'])
            key: t.getCenter(find.byKey(ValueKey(key))).dy
        };
        expect(
            initialButtons.values.first, closeTo(boxFor(false).center.dy, 1));
        final editable = t
            .state<EditableTextState>(find.descendant(
                of: find
                    .byWidgetPredicate((w) => w is Chat && w.threadId == null),
                matching: find.byType(EditableText)))
            .renderEditable;
        expect(
            editable
                .localToGlobal(editable
                    .getLocalRectForCaret(const TextPosition(offset: 0))
                    .center)
                .dy,
            closeTo(initialButtons.values.first, 1));
        await render.capture(t, '$themeName-${style.name}-full-no-thread',
            surface: root);
        EventBus.openThread.add((roomPageClient.identifier, callRoom, r'$m0'));
        await settle(t);
        await settle(t);
        await t.enterText(inputFor(false), '');
        await t.enterText(inputFor(true), '');
        await settle(t);
        // Only PNG capture needs to wait for the fixture SDK's SQLite worker.
        if (Platform.environment['PREVIEW_OUTPUT'] != null) {
          await t.runAsync(() async {
            for (var i = 0; i < 100; i++) {
              final thread = t.state<ChatState>(find
                  .byWidgetPredicate((w) => w is Chat && w.threadId != null));
              if (thread.timeline != null) break;
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await settle(t);
        }
        check(true);
        expect(boxFor(true).height, boxFor(false).height);
        for (final thread in [false, true]) {
          final plus = find.descendant(
              of: find.byWidgetPredicate(
                  (w) => w is Chat && (w.threadId != null) == thread),
              matching: find.byKey(const ValueKey('composer-attach')));
          expect(t.getCenter(plus).dy, closeTo(boxFor(thread).center.dy, 1));
        }
        await render.capture(t, '$themeName-${style.name}-full-thread-empty',
            surface: root);
        for (final isThread in [false, true]) {
          await t.enterText(inputFor(isThread), 'See you at seven.');
        }
        await settle(t);
        check(true);
        expect(boxFor(false).height, 44);
        expect(boxFor(true).height, 44);
        await render.capture(t, '$themeName-${style.name}-full-thread-one-line',
            surface: root);
        await t.enterText(inputFor(true), '');
        await t.enterText(inputFor(false), render.lines);
        await settle(t);
        check(true);
        expect(boxFor(false).height, greaterThan(boxFor(true).height));
        expect(
            t
                .getCenter(find.descendant(
                    of: find.byWidgetPredicate(
                        (w) => w is Chat && w.threadId == null),
                    matching: find.byKey(const ValueKey('composer-attach'))))
                .dy,
            closeTo(initialButtons['composer-attach']!, 1));
        final retained = t.widget<TextField>(inputFor(false)).controller;
        await preferences.experimentComposerWorkshop.set(false);
        await settle(t);
        expect(t.widget<TextField>(inputFor(false)).controller, same(retained));
        expect(retained!.text, render.lines);
        await preferences.experimentComposerWorkshop.set(true);
        await settle(t);
        expect(t.widget<TextField>(inputFor(false)).controller, same(retained));
        final roomPop = find.descendant(
            of: find.byWidgetPredicate((w) => w is Chat && w.threadId == null),
            matching: find.byKey(const ValueKey('composer-popout')));
        final roomSend = find.descendant(
            of: find.byWidgetPredicate((w) => w is Chat && w.threadId == null),
            matching: find.byKey(const ValueKey('composer-send')));
        expect(t.getRect(roomPop).overlaps(t.getRect(roomSend)), isFalse);
        await render.capture(t, '$themeName-${style.name}-full-room-growing',
            surface: root);
        await t.enterText(inputFor(false), '');
        await t.enterText(inputFor(true), render.lines);
        await settle(t);
        check(true);
        await render.capture(t, '$themeName-${style.name}-full-thread-growing',
            surface: root);
        await t.enterText(
            inputFor(true), List.filled(30, render.lines).join("\n"));
        await settle(t);
        expect(
            t
                .widget<TextField>(inputFor(true))
                .scrollController!
                .position
                .maxScrollExtent,
            greaterThan(0));
        check(true);
        EventBus.closeThread.add(null);
        await settle(t);
        EventBus.toggleRoomSidePanel.add(null);
        await settle(t);
        await render.capture(t, '$themeName-${style.name}-full-members',
            surface: root);
        await finishRoomPage(t);
      }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
    }
  }
}
