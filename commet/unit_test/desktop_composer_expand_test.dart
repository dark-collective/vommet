import 'package:commet/client/client.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_widget.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'support/room_page_fixtures.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _box = ValueKey('composer-input');
const _timeline = ValueKey('timeline');
const _expand = ValueKey('composer-expand');
const _collapse = ValueKey('composer-collapse');
const _draft = 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten'
    '\neleven\ntwelve\nthirteen\nfourteen\nfifteen\nsixteen';

void main() {
  setUp(() async {
    // The unit_test/ directory is outside the analyzer's test path.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.layoutOverride.set('desktop');
  });

  Future<void> pumpPane(
    WidgetTester tester,
    ValueNotifier<bool> expanded, {
    required Size size,
    Widget? contextBar,
    MessageInputSendResult Function(String)? send,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux),
      home: Scaffold(
        body: Column(children: [
          const SizedBox(height: 44),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            return Column(children: [
              const Expanded(
                  child: ColoredBox(key: _timeline, color: Colors.teal)),
              MessageInput(
                client: FakeClient(),
                expanded: expanded,
                desktopPaneHeight: constraints.maxHeight,
                insetChatField: true,
                linkPreviewBar: contextBar,
                availibleEmoticons: const [],
                onSendMessage: (message, {overrideClient}) =>
                    send?.call(message) ?? MessageInputSendResult.success,
              ),
            ]);
          })),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final field = find.byType(TextField);
  final expand = find.byKey(_expand);
  final collapse = find.byKey(_collapse);

  for (final style in LayoutStyle.values) {
    testWidgets('${style.name}: compact and expanded scroll in the same field',
        (tester) async {
      await pickLayoutStyle(style);
      final expanded = ValueNotifier(false);
      await pumpPane(tester, expanded,
          size: style == LayoutStyle.discord
              ? const Size(680, 410)
              : const Size(370, 360));
      final box = find.byKey(_box);
      final compact = tester.getSize(box).height;
      expect(compact, 64);
      final timeline = find.byKey(_timeline);
      final compactTimeline = tester.getSize(timeline).height;
      expect(expand, findsNothing);
      await tester.enterText(field, 'short');
      await tester.pumpAndSettle();
      expect(tester.getSize(box).height, compact);
      expect(expand, findsNothing);
      await tester.enterText(field, 'one\ntwo');
      await tester.pumpAndSettle();
      expect(expand, findsNothing);
      await tester.enterText(field, 'one\ntwo\nthree');
      await tester.pumpAndSettle();
      expect(expand, findsOneWidget);
      await tester.enterText(field, _draft);
      await tester.pumpAndSettle();

      expect(tester.getSize(box).height, compact);
      expect(tester.getSize(timeline).height, compactTimeline);
      expect(expand, findsOneWidget);
      final editor = tester.widget<TextField>(field);
      final selection = editor.controller!.selection;
      expect(editor.scrollController!.position.maxScrollExtent, greaterThan(0));
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(collapse, findsOneWidget);
      final paneHeight = (style == LayoutStyle.discord ? 410 : 360) - 44;
      final expandedHeight = (paneHeight - 6) * .38;
      expect(tester.getSize(box).height, closeTo(expandedHeight, .001));
      expect(tester.getSize(timeline).height,
          closeTo(paneHeight - expandedHeight - 6, .001));
      expect(tester.getSize(timeline).height, greaterThanOrEqualTo(48));
      expect(editor.scrollController!.position.maxScrollExtent, greaterThan(0));
      expect(
          tester.widget<TextField>(field).controller, same(editor.controller));
      expect(editor.controller!.selection, selection);
      expect(editor.focusNode!.hasFocus, isTrue);

      await tester.tap(collapse);
      await tester.pumpAndSettle();
      expect(tester.getSize(box).height, compact);
      expect(editor.controller!.text, _draft);
      expect(editor.controller!.selection, selection);
      expect(editor.focusNode!.hasFocus, isTrue);
      final editable =
          tester.state<EditableTextState>(find.byType(EditableText));
      final caret =
          editable.renderEditable.getLocalRectForCaret(selection.extent);
      expect(caret.bottom,
          lessThanOrEqualTo(editable.renderEditable.size.height + 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('expanded editor caps at 216 with the inset outside the box',
      (tester) async {
    await pumpPane(tester, ValueNotifier(false), size: const Size(680, 900));
    await tester.enterText(field, _draft);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_box)).height, 64);
    expect(expand, findsOneWidget);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_box)).height, 216);
    expect(tester.getSize(find.byKey(_timeline)).height,
        closeTo(900 - 44 - 216 - 6, .001));
    expect(
        tester.getSize(find.byKey(_timeline)).height, greaterThanOrEqualTo(48));
    final input = tester.getRect(find.byType(MessageInput));
    final box = tester.getRect(find.byKey(_box));
    expect(box.left - input.left, 8);
    expect(input.right - box.right, 8);
    expect(input.bottom - box.bottom, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrapped draft exposes a keyboard toggle with stable focus',
      (tester) async {
    final expanded = ValueNotifier(false);
    await pumpPane(tester, expanded, size: const Size(370, 360));
    await tester.enterText(field, List.filled(45, 'wrapped').join(' '));
    await tester.pumpAndSettle();
    expect(expand, findsOneWidget);
    final editor = tester.widget<TextField>(field);
    final selection = editor.controller!.selection;
    final ink =
        find.ancestor(of: expand, matching: find.byType(InkResponse)).first;
    final toggleContext = tester.element(ink);
    // Reach the button through ordinary focus traversal, past the action row.
    for (var i = 0; i < 8; i++) {
      if (FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<InkResponse>() ==
          toggleContext.widget) {
        break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(editor.focusNode!.hasFocus, isFalse);
    final focus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(collapse, findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(focus));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(expand, findsOneWidget);
    expect(editor.controller!.selection, selection);
  });

  testWidgets('context consumes the height budget and tiny panes can collapse',
      (tester) async {
    final expanded = ValueNotifier(false);
    await pumpPane(tester, expanded,
        size: const Size(370, 360), contextBar: const SizedBox(height: 85));
    await tester.enterText(field, _draft);
    await tester.pumpAndSettle();
    final compact = tester.getSize(find.byKey(_box)).height;
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(compact, 64);
    expect(tester.getSize(find.byKey(_box)).height,
        closeTo((360 - 44 - 85 - 6) * .38, .001));
    expect(
        tester.getSize(find.byKey(_timeline)).height, greaterThanOrEqualTo(48));
    tester.view.physicalSize = const Size(370, 225);
    await tester.pumpAndSettle();
    expect(collapse, findsOneWidget);
    expect(tester.getSize(find.byKey(_timeline)).height, greaterThan(0));
    await tester.tap(collapse);
    await tester.pumpAndSettle();
    expect(collapse, findsNothing);
    expect(expand, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter keeps failed drafts expanded and resets after success',
      (tester) async {
    final expanded = ValueNotifier(false);
    var success = false;
    final attempts = <String>[];
    await pumpPane(tester, expanded, size: const Size(680, 410), send: (text) {
      attempts.add(text);
      return success
          ? MessageInputSendResult.success
          : MessageInputSendResult.unhandled;
    });
    await tester.enterText(field, _draft);
    await tester.pumpAndSettle();
    expect(expand, findsOneWidget);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '$_draft\n');
    expect(attempts, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    expect(attempts, [_draft]);
    expect(collapse, findsOneWidget);
    success = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    expect(attempts, [_draft, _draft]);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(collapse, findsNothing);
  });

  group('live chat widget', () {
    setUp(roomPageSetUp);
    tearDown(() async {
      InChatSearch.reset();
      await roomPageTearDown();
    });

    testWidgets('search footer bounds desktop drafts before and during search',
        (tester) async {
      final room = roomFor(RoomCase.messages);
      await preferences.layoutOverride.set('desktop');
      await pumpRoomPage(tester, room, width: 680, height: 410);
      final composer = find.byType(MessageInput);
      final editor = find.descendant(of: composer, matching: field);
      final box = find.byKey(_box);
      final compactHeight = tester.getSize(box).height;
      expect(compactHeight, 64);
      final search = InChatSearch.of(room);
      expect(search.isOpen, isFalse);
      await tester.enterText(editor, _draft);
      await settle(tester);
      expect(tester.getSize(box).height, compactHeight);
      expect(expand, findsOneWidget);

      search.open();
      await settle(tester);
      expect(search.isOpen, isTrue);
      expect(composer.hitTestable(), findsOneWidget);
      await tester.tap(expand);
      await settle(tester);
      expect(collapse, findsOneWidget);
      expect(tester.getSize(box).height, greaterThan(compactHeight));
      expect(tester.getSize(find.byType(RoomTimelineWidget)).height,
          greaterThanOrEqualTo(48));
      final textField = tester.widget<TextField>(editor);
      expect(textField.controller!.text, _draft);
      expect(
          textField.scrollController!.position.maxScrollExtent, greaterThan(0));
      search.close();
      await settle(tester);
      expect(collapse, findsOneWidget);
      await finishRoomPage(tester);
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

    testWidgets('room and thread keep separate heights and visible timelines',
        (tester) async {
      final room = roomFor(RoomCase.messages);
      const roomPane = ValueKey('room-pane');
      const threadPane = ValueKey('thread-pane');
      Finder inPane(Key pane, Finder child) =>
          find.descendant(of: find.byKey(pane), matching: child);
      tester.view.physicalSize = const Size(780, 410);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await preferences.layoutOverride.set('desktop');
      await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: Row(children: [
            Expanded(child: Chat(room, key: roomPane)),
            Expanded(child: Chat(room, threadId: r'$m0', key: threadPane)),
          ]),
        ),
      ));
      await settle(tester);
      final roomBox = inPane(roomPane, find.byKey(_box));
      final threadBox = inPane(threadPane, find.byKey(_box));
      final roomHeight = tester.getSize(roomBox).height;
      final threadHeight = tester.getSize(threadBox).height;
      await tester.enterText(inPane(threadPane, field), _draft);
      await settle(tester);
      expect(tester.getSize(threadBox).height, threadHeight);
      await tester.tap(inPane(threadPane, expand));
      await settle(tester);
      expect(inPane(threadPane, collapse), findsOneWidget);
      expect(inPane(roomPane, collapse), findsNothing);
      expect(tester.getSize(threadBox).height, greaterThan(threadHeight));
      expect(tester.getSize(roomBox).height, roomHeight);
      final timeline = inPane(roomPane, find.byType(RoomTimelineWidget));
      expect(tester.getSize(timeline).height, greaterThan(0));
      await finishRoomPage(tester);
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
  });
}
