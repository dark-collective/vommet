import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/main.dart' show preferences;
import 'package:commet/ui/organisms/bookmarks/home_saved_messages.dart';
import 'package:commet/ui/organisms/bookmarks/saved_messages.dart';
import 'package:commet/ui/organisms/new_home/new_home_main.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_view.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class SavedAccountProfile extends Fake implements Profile {
  SavedAccountProfile(this.identifier, this.displayName);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  Color get defaultColor => Colors.teal;
  @override
  ImageProvider? get avatar => null;
}

class _Sdk extends Fake implements matrix.Client {
  @override
  final Map<String, matrix.BasicEvent> accountData = {};
  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();
}

class SavedAccountClient extends Fake implements MatrixClient {
  SavedAccountClient(this.identifier, String name)
      : self = SavedAccountProfile(identifier, name);
  @override
  final String identifier;
  @override
  final Profile self;
  @override
  final matrix.Client matrixClient = _Sdk();
  @override
  Room? getRoom(String id) => null;
}

class _Unsupported extends Fake implements Client {}

class SavedAccountManager extends Fake implements ClientManager {
  SavedAccountManager(List<Client> accounts) {
    clients.addAll(accounts);
  }
  @override
  final NotifyingList<Client> clients = NotifyingList.empty(growable: true);
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, SavedAccountManager manager,
      {Client? filter,
      bool phone = false,
      double width = 1000,
      double textScale = 1}) async {
    tester.view.physicalSize = Size(width, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: Scaffold(
          body: Align(
              alignment: Alignment.topCenter,
              child: NewHomeHeader(
                  tab: const HomeTab('overview', name: 'Overview'),
                  phone: phone,
                  manager: manager,
                  filterClient: filter,
                  leading: phone
                      ? IconButton(
                          onPressed: () {}, icon: const Icon(Icons.menu))
                      : null))),
    ));
    await tester.pumpAndSettle();
  }

  final action = find.byKey(const ValueKey('HomeSavedMessages'));

  testWidgets('All accounts chooses by full ID even with duplicate names',
      (tester) async {
    final a = SavedAccountClient('@alex:personal.example', 'Alex');
    final b = SavedAccountClient('@alex:work.example', 'Alex');
    await pump(tester, SavedAccountManager([a, b]));
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text(HomeSavedMessages.chooseAccount), findsOneWidget);
    expect(find.text(a.identifier), findsOneWidget);
    expect(find.text(b.identifier), findsOneWidget);
    await tester.tap(find.text(b.identifier));
    await tester.pumpAndSettle();
    expect(tester.widget<SavedMessages>(find.byType(SavedMessages)).client,
        same(b));
    expect(find.text(b.identifier), findsOneWidget);
    expect(find.text(a.identifier), findsNothing);
  });

  for (final filtered in [false, true]) {
    testWidgets(
        'opens directly for ${filtered ? "filtered" : "sole eligible"} account',
        (tester) async {
      final a = SavedAccountClient('@alex:personal.example', 'Personal');
      final b = SavedAccountClient('@alex:work.example', 'Work');
      await pump(
          tester, SavedAccountManager([a, if (filtered) b, _Unsupported()]),
          filter: filtered ? b : null);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text(HomeSavedMessages.chooseAccount), findsNothing);
      final selected = filtered ? b : a;
      expect(tester.widget<SavedMessages>(find.byType(SavedMessages)).client,
          same(selected));
      expect(find.text(selected.identifier), findsOneWidget);
      expect(find.text(SavedMessages.labelNoSavedMessages), findsOneWidget);
    });
  }

  testWidgets(
      'no eligible accounts disables and explains; follows account additions',
      (tester) async {
    final unsupported = _Unsupported();
    final manager = SavedAccountManager([unsupported]);
    await pump(tester, manager);
    expect(tester.widget<IconButton>(action).onPressed, isNull);
    expect(find.byTooltip(HomeSavedMessages.unavailable), findsOneWidget);
    manager.clients.add(SavedAccountClient('@alex:example.org', 'Alex'));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(action).onPressed, isNotNull);
    await pump(tester, manager, filter: unsupported);
    expect(tester.widget<IconButton>(action).onPressed, isNull);
  });

  testWidgets(
      'chooser refreshes on logout without silently choosing the remaining account',
      (tester) async {
    final a = SavedAccountClient('@alex:personal.example', 'Personal');
    final b = SavedAccountClient('@alex:work.example', 'Work');
    final manager = SavedAccountManager([a, b]);
    await pump(tester, manager, phone: true, width: 360);
    await tester.tap(action);
    await tester.pumpAndSettle();
    manager.clients.remove(b);
    await tester.pumpAndSettle();
    expect(find.text(b.identifier), findsNothing);
    expect(find.byType(SavedMessages), findsNothing);
    await tester.tap(find.text(a.identifier));
    await tester.pumpAndSettle();
    expect(find.byType(SavedMessages), findsOneWidget);
    manager.clients.add(b);
    manager.clients.remove(a);
    await tester.pumpAndSettle();
    expect(tester.widget<SavedMessages>(find.byType(SavedMessages)).client,
        same(a));
  });

  testWidgets('chooser remains dismissible when every account disappears',
      (tester) async {
    final manager = SavedAccountManager([
      SavedAccountClient('@alex:personal.example', 'Personal'),
      SavedAccountClient('@alex:work.example', 'Work')
    ]);
    await pump(tester, manager);
    await tester.tap(action);
    await tester.pumpAndSettle();
    manager.clients.clear();
    await tester.pumpAndSettle();
    expect(find.text(HomeSavedMessages.unavailable), findsOneWidget);
    expect(find.byType(SavedMessages), findsNothing);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(action).onPressed, isNull);
  });

  testWidgets(
      'stale account tile cannot open an account removed before repaint',
      (tester) async {
    final a = SavedAccountClient('@alex:personal.example', 'Personal');
    final b = SavedAccountClient('@alex:work.example', 'Work');
    final manager = SavedAccountManager([a, b]);
    await pump(tester, manager);
    await tester.tap(action);
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(
        find.byKey(ValueKey('saved-account-${b.identifier}')));
    manager.clients.remove(b);
    tile.onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(SavedMessages), findsNothing);
    expect(find.text(HomeSavedMessages.chooseAccount), findsOneWidget);
    expect(find.text(a.identifier), findsOneWidget);
  });

  testWidgets('phone chooser and account identity fit large text and long IDs',
      (tester) async {
    final a = SavedAccountClient(
        '@alex:personal-account-with-a-long-homeserver.example.org',
        'Personal account with a long display name');
    final b = SavedAccountClient('@alex:work.example.org', 'Work');
    await pump(tester, SavedAccountManager([a, b]),
        phone: true, width: 320, textScale: 2);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(a.identifier));
    await tester.tap(find.text(a.identifier));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(a.identifier), findsOneWidget);
  });

  testWidgets('keyboard opens Home Saved messages and chooses an account',
      (tester) async {
    final a = SavedAccountClient('@alex:personal.example', 'Personal');
    final b = SavedAccountClient('@alex:work.example', 'Work');
    await pump(tester, SavedAccountManager([a, b]));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(HomeSavedMessages.chooseAccount), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<SavedMessages>(find.byType(SavedMessages)).client,
        same(a));
  });

  for (final phone in [false, true]) {
    for (final filtered in [false, true]) {
      testWidgets(
          'unified list bookmark opens the account at '
          '${phone ? "phone" : "desktop"} size (filtered: $filtered)',
          (tester) async {
        final a = SavedAccountClient('@alex:personal.example', 'Personal');
        final b = SavedAccountClient('@alex:work.example', 'Work');
        final manager = SavedAccountManager([a, b]);
        final search = TextEditingController();
        addTearDown(search.dispose);
        tester.view.physicalSize = Size(phone ? 320 : 1000, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
        var composed = false;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(
              body: ChatListPane(
            rows: const [],
            search: search,
            now: DateTime(2026),
            onCompose: () => composed = true,
            savedMessagesAction: HomeSavedMessages(
                manager: manager, filterClient: filtered ? b : null),
          )),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final compose = find.byTooltip('New chat');
        expect(tester.getRect(action).right,
            lessThanOrEqualTo(tester.getRect(compose).left));
        expect(tester.getSize(action), const Size(48, 48));
        await tester.enterText(find.byType(TextField), 'Engineering');
        await tester.tap(compose);
        expect(composed, isTrue);
        expect(search.text, 'Engineering');
        await tester.tap(action);
        await tester.pumpAndSettle();
        if (!filtered) {
          expect(find.text(HomeSavedMessages.chooseAccount), findsOneWidget);
          await tester.tap(find.text(b.identifier));
          await tester.pumpAndSettle();
        } else {
          expect(find.text(HomeSavedMessages.chooseAccount), findsNothing);
        }
        expect(tester.widget<SavedMessages>(find.byType(SavedMessages)).client,
            same(b));
        expect(find.text(b.identifier), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('320 px phone keeps 48 px actions at text scale $scale',
        (tester) async {
      await pump(tester, SavedAccountManager([]),
          phone: true, width: 320, textScale: scale);
      expect(tester.takeException(), isNull);
      for (final key in [
        'HomeSavedMessages',
        'NewHomeCustomizeButton',
        'NotificationsBell'
      ]) {
        expect(tester.getSize(find.byKey(ValueKey(key))), const Size(48, 48));
      }
      expect(tester.getSize(find.byType(NewHomeHeader)).height, 52);
      expect(find.byTooltip('Customize'), findsOneWidget);
    });
  }
}
