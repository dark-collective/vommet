import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/ui/pages/settings/categories/account/settings_category_account.dart';
import 'package:commet/ui/pages/settings/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'dart:async';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/scheduled_messages/scheduled_messages.dart';
import 'package:commet/client/components/scheduled_messages/scheduled_edit_handoff.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/scheduled_messages/scheduled_list_strings.dart';
import 'package:commet/ui/organisms/scheduled_messages/scheduled_messages_view.dart';
import 'package:commet/ui/pages/settings/categories/account/scheduled_messages/scheduled_messages_tab.dart';
import 'package:commet/utils/message_drafts.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as mx;
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> delayed(String id, String room, int hour,
        {bool encrypted = false}) =>
    {
      'delay_id': id,
      'room_id': room,
      'type': encrypted ? 'm.room.encrypted' : 'm.room.message',
      'running_since': DateTime(2030, 1, 1, hour).millisecondsSinceEpoch,
      'delay': 0,
      'content': encrypted
          ? {'ciphertext': 'unreadable'}
          : {'body': 'Message $id', 'msgtype': 'm.text'},
    };

class _Sdk extends Fake implements mx.Client {
  bool supported = true;
  bool versionsFail = false;
  bool requestsFail = false;
  bool loop = false;
  void Function()? afterAction;
  int gets = 0;
  bool? strictVersions;
  Duration? versionsLifetime;
  List<Map<String, Object?>> messages = [];
  final List<(mx.RequestType, String, Object?, Map<String, Object?>?)> calls =
      [];
  Completer<Map<String, Object?>>? delayedResponse;

  @override
  Future<mx.GetVersionsResponse> getVersions(
      {Duration cacheLifetime = const Duration(days: 3),
      bool throwOnUpdateFailure = false}) async {
    strictVersions = throwOnUpdateFailure;
    versionsLifetime = cacheLifetime;
    if (versionsFail) throw StateError('offline');
    return mx.GetVersionsResponse(
        versions: ['v1.11'],
        unstableFeatures: {ScheduledMessages.feature: supported});
  }

  @override
  Future<Map<String, Object?>> request(mx.RequestType type, String action,
      {dynamic data = '',
      String contentType = 'application/json',
      Map<String, Object?>? query}) async {
    calls.add((type, action, data, query));
    if (requestsFail) throw StateError('offline');
    if (type == mx.RequestType.GET) {
      gets++;
      if (delayedResponse != null) return delayedResponse!.future;
      return {'delayed_events': messages, if (loop) 'next_batch': 'page-$gets'};
    }
    messages.removeWhere((m) => action.endsWith('/${m['delay_id']}'));
    afterAction?.call();
    return {};
  }

  @override
  mx.Room? getRoomById(String roomId) => null;
}

class _Profile extends Fake implements Profile {
  _Profile(this.identifier);
  @override
  final String identifier;
  @override
  String get displayName => 'Alex';
  @override
  ImageProvider? get avatar => null;
}

class _Client extends Fake implements MatrixClient {
  _Client(this.identifier, this.matrixClient);
  @override
  final String identifier;
  @override
  final _Sdk matrixClient;
  final Map<String, Room> roomsById = {};
  bool loggedIn = true;
  @override
  bool isLoggedIn() => loggedIn;
  @override
  Room? getRoom(String id) => roomsById[id];
  @override
  Profile get self => _Profile('@$identifier:example.org');
}

class _Room extends Fake implements Room {
  _Room(this.client, this.identifier);
  @override
  final Client client;
  @override
  final String identifier;
  @override
  String get displayName => 'Design';
  @override
  bool get isBanned => false;
  @override
  bool get isRemoved => false;
}

class _Manager extends Fake implements ClientManager {
  _Manager(List<Client> clients)
      : clients = NotifyingList.from(clients, growable: true);
  @override
  final NotifyingList<Client> clients;
}

void main() {
  final clients = <_Client>[];
  _Client account(String id) {
    final c = _Client(id, _Sdk());
    clients.add(c);
    return c;
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.layoutOverride.set('desktop');
  });
  tearDown(() {
    for (final c in clients) {
      ScheduledMessages.forget(c);
    }
    clients.clear();
  });

  test('account cache is isolated, immutable, sorted with stable ties',
      () async {
    final a = account('a'), b = account('b');
    a.matrixClient.messages = [
      delayed('later', '!b:x', 12),
      delayed('z', '!a:x', 9),
      delayed('a', '!a:x', 9)
    ];
    b.matrixClient.messages = [delayed('a', '!other:x', 8)];
    await ScheduledMessages.refresh(a, strict: true);
    await ScheduledMessages.refresh(b, strict: true);
    expect(ScheduledMessages.inAccount(a).map((m) => m.delayId),
        ['a', 'z', 'later']);
    expect(ScheduledMessages.inAccount(b).single.roomId, '!other:x');
    expect(
        () => ScheduledMessages.inAccount(a).clear(), throwsUnsupportedError);
    expect(ScheduledMessages.inRoom(a, '!a:x').length, 2);
  });

  test(
      'capability failure is distinct from unsupported and retry forces SDK check',
      () async {
    final a = account('a');
    a.matrixClient.versionsFail = true;
    await expectLater(
        ScheduledMessages.supported(a, throwOnError: true), throwsStateError);
    expect(ScheduledMessages.supportedCached(a), isNull);
    a.matrixClient.versionsFail = false;
    a.matrixClient.supported = false;
    expect(
        await ScheduledMessages.supported(a, throwOnError: true, force: true),
        isFalse);
    expect(a.matrixClient.strictVersions, isTrue);
    expect(a.matrixClient.versionsLifetime, Duration.zero);
    await expectLater(ScheduledMessages.refresh(a, strict: true),
        throwsA(isA<ScheduleException>()));
    expect(a.matrixClient.gets, 0);
  });

  test('bounded pagination never publishes a partial or empty success',
      () async {
    final a = account('a');
    a.matrixClient.messages = [delayed('one', '!a:x', 12)];
    await ScheduledMessages.refresh(a);
    a.matrixClient.loop = true;
    await expectLater(ScheduledMessages.refresh(a, strict: true),
        throwsA(isA<ScheduleException>()));
    expect(a.matrixClient.gets, 21);
    expect(ScheduledMessages.inAccount(a).single.delayId, 'one');
  });

  test('logout invalidates in-flight refresh and destroys edit plaintext',
      () async {
    final a = account('a');
    final room = _Room(a, '!a:x');
    await ScheduledMessages.supported(a);
    final response = a.matrixClient.delayedResponse = Completer();
    final refresh = ScheduledMessages.refresh(a);
    await Future<void>.delayed(Duration.zero);
    ScheduledEditHandoff.put(room, 'private');
    ScheduledMessages.forget(a);
    response.complete({
      'delayed_events': [delayed('stale', '!a:x', 12)]
    });
    expect(await refresh, isEmpty);
    expect(ScheduledMessages.inAccount(a), isEmpty);
    expect(ScheduledEditHandoff.take(room), isNull);
    expect(ScheduledMessages.available(a), isFalse);
  });

  test(
      'failed action keeps cached message; cancellation targets chosen account only',
      () async {
    final a = account('a'), b = account('b');
    for (final c in [a, b]) {
      c.matrixClient.messages = [delayed('same', '!a:x', 12)];
      await ScheduledMessages.refresh(c);
    }
    a.matrixClient.requestsFail = true;
    await expectLater(ScheduledMessages.cancel(a, 'same'), throwsStateError);
    expect(ScheduledMessages.inAccount(a), hasLength(1));
    await ScheduledMessages.cancel(b, 'same');
    expect(ScheduledMessages.inAccount(b), isEmpty);
    expect(a.matrixClient.messages, hasLength(1));
  });

  test(
      'edit handoff binds client instance and room; existing draft blocks edit',
      () {
    final a = account('a'), b = account('b');
    final ar = _Room(a, '!same:x'), br = _Room(b, '!same:x');
    final key = MessageDrafts.keyFor(a.identifier, ar.identifier);
    ChatState.drafts.set(key, const MessageDraft('existing draft'));
    expect(ChatState.canAcceptScheduledEdit(ar), isFalse);
    expect(ChatState.canAcceptScheduledEdit(br), isTrue);
    ChatState.drafts.clear(key);
    ScheduledEditHandoff.put(ar, 'edit');
    expect(ChatState.canAcceptScheduledEdit(ar), isFalse);
    expect(ScheduledEditHandoff.take(br), isNull);
    expect(ScheduledEditHandoff.take(ar), 'edit');
    expect(ScheduledEditHandoff.take(ar), isNull);
  });

  Future<void> pump(WidgetTester tester, _Manager manager,
      {double width = 390, double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 950);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 950), textScaler: TextScaler.linear(scale)),
            child:
                Scaffold(body: ScheduledMessagesTab(clientManager: manager)))));
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
      'multiple accounts start unselected, chooser never loads the first silently',
      (tester) async {
    final a = account('a'), b = account('b');
    await pump(tester, _Manager([a, b]));
    expect(find.text(ScheduledListStrings.noAccount), findsOneWidget);
    expect(a.matrixClient.gets, 0);
    expect(b.matrixClient.gets, 0);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('@b:example.org'));
    await tester.pumpAndSettle();
    expect(a.matrixClient.gets, 0);
    expect(b.matrixClient.gets, 1);
    expect(find.text(ScheduledListStrings.none), findsOneWidget);
    for (final c in clients) {
      ScheduledMessages.forget(c);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'loading, capability error, retry and unsupported are distinct from empty',
      (tester) async {
    final a = account('a');
    a.matrixClient.versionsFail = true;
    await pump(tester, _Manager([a]));
    await tester.pumpAndSettle();
    expect(find.text(ScheduledListStrings.unavailable), findsOneWidget);
    expect(find.text(ScheduledListStrings.none), findsNothing);
    a.matrixClient.versionsFail = false;
    a.matrixClient.supported = false;
    await tester.tap(find.text(ScheduledListStrings.retry));
    await tester.pumpAndSettle();
    expect(find.text(ScheduleStrings.scheduleUnsupportedExplanation),
        findsOneWidget);
    expect(find.text(ScheduledListStrings.none), findsNothing);
    for (final c in clients) {
      ScheduledMessages.forget(c);
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [390.0, 1100.0]) {
    testWidgets(
        'room identity, encrypted fallback and actions fit at $width with 200% text',
        (tester) async {
      final a = account('a');
      a.matrixClient.messages = [
        delayed('plain', '!one:example.org', 9),
        delayed('encrypted', '!two:example.org', 10, encrypted: true),
        delayed('left', '!left:example.org', 11)
      ];
      a.roomsById['!one:example.org'] = _Room(a, '!one:example.org');
      a.roomsById['!two:example.org'] = _Room(a, '!two:example.org');
      await pump(tester, _Manager([a]), width: width, scale: 2);
      await tester.pumpAndSettle();
      expect(find.text('!one:example.org'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
          find.text(ScheduleStrings.scheduledEncryptedText), 350,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
          find.text(ScheduledListStrings.roomUnavailableHelp), 350,
          scrollable: find.byType(Scrollable).first);
      final row = find.ancestor(
          of: find.text(ScheduledListStrings.roomUnavailableHelp),
          matching: find.byType(ScheduledMessageEntry));
      final buttons = tester
          .widgetList<TextButton>(
              find.descendant(of: row, matching: find.byType(TextButton)))
          .toList();
      expect(
          buttons.map((b) => b.onPressed != null), [false, false, false, true]);
      for (final c in clients) {
        ScheduledMessages.forget(c);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('logout clears view and does not select the remaining account',
      (tester) async {
    final a = account('a'), b = account('b');
    final manager = _Manager([a]);
    a.matrixClient.messages = [delayed('private', '!missing:x', 10)];
    await pump(tester, manager);
    await tester.pumpAndSettle();
    manager.clients.add(b);
    ScheduledMessages.forget(a);
    manager.clients.remove(a);
    await tester.pumpAndSettle();
    expect(find.text(ScheduledListStrings.signedOut), findsOneWidget);
    expect(find.text(ScheduledListStrings.noAccount), findsOneWidget);
    expect(b.matrixClient.gets, 0);
    for (final c in clients) {
      ScheduledMessages.forget(c);
    }
    await tester.pumpWidget(const SizedBox());
  });
  for (final style in LayoutStyle.values) {
    for (final unified in style == LayoutStyle.custom
        ? [false, true]
        : [style == LayoutStyle.telegram]) {
      for (final width in [390.0, 1100.0]) {
        testWidgets(
            'Settings entry opens in ${style.name} unified=$unified at $width',
            (tester) async {
          final a = account('a');
          final manager = _Manager([a]);
          await (style == LayoutStyle.telegram
                  ? LayoutOptions.telegram
                  : LayoutOptions.discord)
              .save();
          await layoutStyleCustomPicked.set(style == LayoutStyle.custom);
          await experimentUnifiedChatList.set(unified);
          await preferences.layoutOverride
              .set(width < 500 ? 'mobile' : 'desktop');
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 950);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(Provider<ClientManager>.value(
              value: manager,
              child: MaterialApp(
                  theme: ThemeDark.theme,
                  home: SettingsPage(
                      settings: [SettingsCategoryAccount()],
                      initialTab: ScheduleStrings.scheduledListTitle))));
          await tester.pumpAndSettle();
          if (width < 500) {
            await tester.tap(find.text(ScheduleStrings.scheduledListTitle));
            await tester.pumpAndSettle();
          }
          expect(find.byType(ScheduledMessagesTab), findsOneWidget);
          expect(find.text(ScheduledListStrings.none), findsOneWidget);
          expect(tester.takeException(), isNull);
          for (final c in clients) {
            ScheduledMessages.forget(c);
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  for (final stale in [false, true]) {
    testWidgets(
        'global action targets explicit account and rechecks pending=$stale',
        (tester) async {
      final a = account('a'), b = account('b');
      for (final c in [a, b]) {
        c.matrixClient.messages = [delayed('same', '!same:x', 12)];
        c.roomsById['!same:x'] = _Room(c, '!same:x');
      }
      await pump(tester, _Manager([a, b]), width: 1100);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('@b:example.org'));
      await tester.pumpAndSettle();
      if (stale) b.matrixClient.messages = [];
      await tester.tap(find.byKey(const ValueKey('scheduled-send-now-same')));
      await tester.pumpAndSettle();
      expect(a.matrixClient.calls.where((c) => c.$1 == mx.RequestType.POST),
          isEmpty);
      expect(
          b.matrixClient.calls.where((c) => c.$1 == mx.RequestType.POST).length,
          stale ? 0 : 1);
      if (stale) expect(find.text(ScheduledListStrings.gone), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final c in clients) {
        ScheduledMessages.forget(c);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'global Edit keeps a conflicting draft and leaves the server event scheduled',
      (tester) async {
    final a = account('a');
    final room = _Room(a, '!room:x');
    a.roomsById[room.identifier] = room;
    a.matrixClient.messages = [delayed('edit', room.identifier, 12)];
    final key = MessageDrafts.keyFor(a.identifier, room.identifier);
    ChatState.drafts.set(key, const MessageDraft('keep me'));
    await pump(tester, _Manager([a]), width: 1100);
    await tester.pumpAndSettle();
    await tester.tap(find.text(ScheduleStrings.scheduledEdit));
    await tester.pumpAndSettle();
    expect(find.text(ScheduledListStrings.draftConflict), findsOneWidget);
    expect(ChatState.drafts.get(key)?.text, 'keep me');
    expect(a.matrixClient.calls.where((c) => c.$1 == mx.RequestType.POST),
        isEmpty);
    ChatState.drafts.clear(key);
    for (final c in clients) {
      ScheduledMessages.forget(c);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Edit retains the exact room handoff if a leave arrives during cancellation',
      (tester) async {
    final a = account('a');
    final room = _Room(a, '!room:x');
    a.roomsById[room.identifier] = room;
    a.matrixClient.messages = [delayed('edit', room.identifier, 12)];
    a.matrixClient.afterAction = () => a.roomsById.clear();
    await pump(tester, _Manager([a]), width: 1100);
    await tester.pumpAndSettle();
    await tester.tap(find.text(ScheduleStrings.scheduledEdit));
    await tester.pumpAndSettle();
    expect(ScheduledEditHandoff.take(room), 'Message edit');
    expect(
        a.matrixClient.calls.where((c) => c.$1 == mx.RequestType.POST).length,
        1);
    for (final c in clients) {
      ScheduledMessages.forget(c);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a withdrawn capability updates an open queue to unsupported, not empty',
      (tester) async {
    final a = account('a');
    a.matrixClient.messages = [delayed('queued', '!room:x', 12)];
    await pump(tester, _Manager([a]), width: 1100);
    await tester.pumpAndSettle();
    a.matrixClient.supported = false;
    await ScheduledMessages.supported(a, force: true);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleStrings.scheduleUnsupportedExplanation),
        findsOneWidget);
    expect(find.text(ScheduledListStrings.none), findsNothing);
    for (final c in clients) {
      ScheduledMessages.forget(c);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'scheduled action popup titles wrap at 200% text on a narrow desktop',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 950);
    addTearDown(tester.view.reset);
    for (final title in [
      ScheduleStrings.scheduleFailedTitle,
      ScheduleStrings.schedulePickTitle,
      ScheduledListStrings.chooseAccount
    ]) {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(390, 950), textScaler: TextScaler.linear(2)),
              child: Scaffold(
                  body: tiamat.PopupDialog(
                      title: title,
                      content: const SizedBox(
                          width: 400, child: Text('Message details')))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
