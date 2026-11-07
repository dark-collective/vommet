import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/event_search/event_search_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SearchComponent implements EventSearchComponent<Client> {
  @override
  List<String> getSupportedSearchFeatures(Room room) => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  String get identifier => 'account';

  @override
  T? getComponent<T extends Component>() {
    final search = _SearchComponent();
    return search is T ? search as T : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Room implements Room {
  @override
  final Client client = _Client();

  @override
  String get identifier => '!room';

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Result implements TimelineEvent {
  @override
  String get eventId => 'result';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final linux = TargetPlatformVariant({TargetPlatform.linux});
  late Room room;
  late InChatSearch search;
  const outsideKey = ValueKey("outside-search");
  late FocusNode outside;
  late ValueNotifier<bool> showComposer;
  final composer = find.descendant(
    of: find.byType(MessageInput),
    matching: find.byType(TextField),
  );

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.layoutOverride.set('desktop');
    room = _Room();
    search = InChatSearch.of(room);
    showComposer = ValueNotifier(true);
  });

  tearDown(() {
    InChatSearch.reset();
    showComposer.dispose();
  });

  Future<void> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    bool openKey(KeyEvent event) => InChatSearch.handleOpenKey(event, room);
    KeyEventResult lateKey(KeyEvent event) =>
        InChatSearch.handleUnhandledEscape(event, room)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

    HardwareKeyboard.instance.addHandler(openKey);
    FocusManager.instance.addLateKeyEventHandler(lateKey);
    addTearDown(() {
      HardwareKeyboard.instance.removeHandler(openKey);
      FocusManager.instance.removeLateKeyEventHandler(lateKey);
    });

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(platform: TargetPlatform.linux),
      home: Scaffold(
        body: Column(children: [
          InChatSearchField.orHeader(room, (_) => const Text('Room')),
          const Expanded(child: Focus(child: SizedBox(key: outsideKey))),
          ValueListenableBuilder<bool>(
            valueListenable: showComposer,
            builder: (_, show, __) => InChatSearchFooter(
              search: search,
              composer: show
                  ? MessageInput(
                      client: room.client,
                      availibleEmoticons: const [],
                      onSendMessage: (_, {overrideClient}) =>
                          MessageInputSendResult.success,
                    )
                  : const SizedBox(),
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();
    outside = Focus.of(tester.element(find.byKey(outsideKey)));
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(search.isOpen, isTrue);
    expect(search.focus.hasPrimaryFocus, isTrue);
  }

  Future<void> escape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(search.isOpen, isFalse);
  }

  for (final viaFallback in [false, true]) {
    testWidgets(
        'Escape restores typing to the composer '
        '(${viaFallback ? 'late handler' : 'field shortcut'})', (tester) async {
      await pumpChat(tester);
      await tester.tap(composer);
      await tester.pump();
      final node = tester.widget<TextField>(composer).focusNode!;
      expect(node.hasPrimaryFocus, isTrue);
      await openSearch(tester);
      if (viaFallback) {
        await openSearch(tester); // Reopening must keep the original target.
        outside.requestFocus();
        await tester.pump();
        expect(outside.hasPrimaryFocus, isTrue);
      }
      await escape(tester);
      expect(node.hasPrimaryFocus, isTrue);
      tester.testTextInput.enterText('Back to the draft');
      await tester.pump();
      expect(tester.widget<TextField>(composer).controller!.text,
          'Back to the draft');
    }, variant: linux);
  }

  testWidgets('Escape skips an unfocused or removed composer', (tester) async {
    await pumpChat(tester);
    outside.requestFocus();
    await tester.pump();
    final node = tester.widget<TextField>(composer).focusNode!;
    await openSearch(tester);
    await escape(tester);
    expect(node.hasFocus, isFalse);

    await tester.tap(composer);
    await tester.pump();
    await openSearch(tester);
    showComposer.value = false;
    await tester.pump();
    expect(node.parent, isNull);
    await escape(tester);
    expect(node.hasFocus, isFalse);
  });

  testWidgets(
      'Enter selects a result and Close keeps the query without '
      'refocusing the composer', (tester) async {
    await pumpChat(tester);
    await tester.tap(composer);
    await tester.pump();
    final node = tester.widget<TextField>(composer).focusNode!;
    await openSearch(tester);
    search.text.text = 'moss';
    search.query = 'moss';
    search.results = [_Result()];
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(search.current, 0);
    expect(search.isOpen, isTrue);
    expect(node.hasFocus, isFalse);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(search.isOpen, isFalse);
    expect(search.text.text, 'moss');
    expect(node.hasFocus, isFalse);
  });
}
