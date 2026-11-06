import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/timeline_events/bookmark_menu.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:commet/ui/organisms/bookmarks/saved_messages.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/bookmark_fixtures.dart';
import 'message_selection_download_test.dart' show SelectionMessage;

class _Other extends Fake implements TimelineEvent {
  _Other(this.eventId);
  @override
  final String eventId;
  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;
}

// Exercise the production selected-message menu without rendering event media.
class _MenuEntry extends TimelineViewEntry {
  const _MenuEntry({required super.timeline}) : super(initialIndex: 0);
  @override
  State<TimelineViewEntry> createState() => _MenuState();
}

class _MenuState extends TimelineViewEntryState {
  @override
  void loadState(int index) {
    eventId = widget.timeline.events[index].eventId;
  }

  @override
  List<String> get shownEventIds => [eventId];
  @override
  Widget build(BuildContext context) => Wrap(children: [
        for (final item in selectionMenuItems() ?? [])
          Tooltip(
            message: item.tooltip ?? '',
            child: TextButton(
                onPressed:
                    item.onPressed == null ? null : () => item.onPressed!(),
                child: Text(item.text)),
          ),
      ]);
}

MessageSelection bookmarkFixture(BookmarkSdk sdk, List<TimelineEvent> events,
    {String room = '!fixture', String account = 'bookmark-account'}) {
  final r =
      BookmarkRoom(BookmarkClient(sdk, identifier: account), identifier: room);
  final selection = MessageSelection(r)
    ..timeline = BookmarkTimeline(r, events.reversed.toList())
    ..start(events.map((e) => e.eventId).toSet().toList());
  addTearDown(selection.dispose);
  addTearDown(sdk.onSync.close);
  return selection;
}

List<Bookmark> stored(BookmarkSdk sdk) => Bookmarks.parse(sdk.server);
SelectionMessage message(String id) => SelectionMessage(id, null);

Future<BuildContext> bookmarkHarness(WidgetTester t, MessageSelection selection,
    {double width = 1700, double scale = 1}) async {
  addTearDown(t.view.reset);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });
  t.view.physicalSize = Size(width, 600);
  t.view.devicePixelRatio = 1;
  // Navigator overlays must inherit the scaler too, including popup menus.
  await t.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: Column(children: [
        SizedBox(height: 56, child: MessageSelectionBar(selection)),
      ]))));
  await t.pump();
  return t.element(find.byType(MessageSelectionBar));
}

Future<void> save(WidgetTester t, String label,
    {bool compact = false, double scale = 1}) async {
  if (compact) {
    await t.tap(find.byKey(const ValueKey('message-selection-more')));
    await t.pumpAndSettle();
  }
  // On the unmodified base this fails because the selection has no Save action.
  expect(find.text(label), findsOneWidget);
  if (compact)
    expect(MediaQuery.textScalerOf(t.element(find.text(label))).scale(16),
        16 * scale);
  await t.tap(find.text(label));
  await t.pump();
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.experimentForwardMessages.set(true);
  });

  test(
      'local bookmark mutations read after preceding writes, including removal',
      () async {
    final sdk = BookmarkSdk()..nextWrite = Completer<void>();
    final gate = sdk.nextWrite!;
    final client = BookmarkClient(sdk);
    sdk.emitBookmarks(
        [const Bookmark(roomId: '!fixture', eventId: 'old', savedTs: 1)]);
    addTearDown(sdk.onSync.close);
    final a = Bookmarks.save(client, '!fixture', 'a');
    final b = Bookmarks.save(client, '!fixture', 'b', tags: ['work']);
    final removal = Bookmarks.remove(client, '!fixture', 'old');
    try {
      await Future<void>.delayed(Duration.zero);
      expect(sdk.writes, hasLength(1));
      expect(Bookmarks.of(client).map((b) => b.eventId), ['old']);
    } finally {
      gate.complete();
      await Future.wait([a, b, removal]);
    }
    expect(stored(sdk).map((b) => b.eventId).toSet(), {'a', 'b'});
    expect(stored(sdk).firstWhere((b) => b.eventId == 'b').tags, ['work']);
  });

  testWidgets(
      'one batch persists unique messages in order and preserves old metadata',
      (t) async {
    final sdk = BookmarkSdk();
    const old = Bookmark(
        roomId: '!fixture',
        eventId: 'old',
        savedTs: 9,
        tags: ['work'],
        note: 'Keep me');
    sdk.emitBookmarks([old]);
    final s = bookmarkFixture(sdk, [
      message('a'),
      message('old'),
      message('b'),
      message('a'),
      _Other('poll')
    ]);
    await bookmarkHarness(t, s, width: 1700);
    await save(t, 'Save 2 messages');
    expect(sdk.writes, hasLength(1));
    expect(stored(sdk).map((b) => b.eventId), ['b', 'a', 'old']);
    expect(stored(sdk).last.toJson(), old.toJson());
    expect(stored(sdk).first.tags, isEmpty);
    expect(s.ticked.ids, ['poll']);
    expect(find.textContaining('Saved 2 messages.'), findsOneWidget);
    expect(find.textContaining('1 already saved.'), findsOneWidget);
    expect(find.textContaining("1 message couldn't be saved."), findsOneWidget);
  });

  testWidgets(
      'capacity preserves all old saves, reports partial result and full retry writes nothing',
      (t) async {
    final sdk = BookmarkSdk();
    final old = List.generate(
        999, (i) => Bookmark(roomId: '!elsewhere', eventId: '$i', savedTs: i));
    sdk.emitBookmarks(old);
    final s = bookmarkFixture(sdk, [message('a'), message('b'), message('c')]);
    await bookmarkHarness(t, s, width: 1700);
    await save(t, 'Save 3 messages');
    expect(stored(sdk), hasLength(1000));
    expect(stored(sdk).first.eventId, 'a');
    expect(stored(sdk).where((b) => b.roomId == '!elsewhere'), hasLength(999));
    expect(s.ticked.ids.toSet(), {'b', 'c'});
    expect(find.textContaining("2 couldn't fit."), findsOneWidget);
    await save(t, 'Save 2 messages');
    expect(sdk.writes, hasLength(1));
    expect(s.ticked.ids.toSet(), {'b', 'c'});
  });

  testWidgets(
      'batch starts busy before awaiting, blocks double taps and publishes only on acknowledgment',
      (t) async {
    final sdk = BookmarkSdk()..nextWrite = Completer<void>();
    final gate = sdk.nextWrite!;
    final s = bookmarkFixture(sdk, [message('a'), message('b')]);
    await bookmarkHarness(t, s, width: 1700);
    await save(t, 'Save 2 messages');
    expect(s.busy, isTrue);
    expect(Bookmarks.of(s.room.client), isEmpty);
    await t.tap(find.text('Save 2 messages'));
    s.toggle(['a']);
    expect(s.ticked.length, 2);
    expect(sdk.writes, hasLength(1));
    gate.complete();
    await t.pumpAndSettle();
    expect(s.active, isFalse);
    expect(Bookmarks.of(s.room.client), hasLength(2));
  });

  testWidgets(
      'batch plus queued single tag edit and removal preserve every accepted change',
      (t) async {
    final sdk = BookmarkSdk()..nextWrite = Completer<void>();
    final gate = sdk.nextWrite!;
    sdk.emitBookmarks(
        [const Bookmark(roomId: '!fixture', eventId: 'remove', savedTs: 1)]);
    final s = bookmarkFixture(sdk, [message('a'), message('b')]);
    await bookmarkHarness(t, s, width: 1700);
    await save(t, 'Save 2 messages');
    final edit = Bookmarks.save(s.room.client, '!fixture', 'a',
        tags: ['Work'], note: 'edited');
    final remove = Bookmarks.remove(s.room.client, '!fixture', 'remove');
    await t.pump();
    expect(sdk.writes, hasLength(1));
    gate.complete();
    await t.pumpAndSettle();
    await Future.wait([edit, remove]);
    expect(stored(sdk).map((b) => b.eventId).toSet(), {'a', 'b'});
    expect(stored(sdk).firstWhere((b) => b.eventId == 'a').tags, ['work']);
    expect(stored(sdk).firstWhere((b) => b.eventId == 'a').note, 'edited');
  });

  testWidgets(
      'failed response keeps pending selection; late sync deduplicates retry',
      (t) async {
    final sdk = BookmarkSdk()..nextWrite = Completer<void>();
    final gate = sdk.nextWrite!;
    final s = bookmarkFixture(sdk, [message('a'), message('b')]);
    await bookmarkHarness(t, s, width: 1700);
    await save(t, 'Save 2 messages');
    gate.completeError(StateError('response lost'));
    await t.pumpAndSettle();
    expect(s.busy, isFalse);
    expect(s.ticked.length, 2);
    expect(Bookmarks.of(s.room.client), isEmpty);
    expect(find.text("Couldn't confirm saving. Try again."), findsOneWidget);
    sdk.emitBookmarks([
      const Bookmark(
          roomId: '!fixture', eventId: 'a', savedTs: 1, tags: ['remote'])
    ]);
    await t.pumpAndSettle();
    await save(t, 'Save 1 message');
    expect(sdk.writes, hasLength(2));
    expect(stored(sdk).map((b) => b.eventId), ['b', 'a']);
    expect(stored(sdk).last.tags, ['remote']);
    expect(s.active, isFalse);
  });

  testWidgets('accounts and rooms with the same event ID remain independent',
      (t) async {
    final a = BookmarkSdk()..nextWrite = Completer<void>();
    final gate = a.nextWrite!;
    final sa = bookmarkFixture(a, [message('same')], account: 'a');
    await bookmarkHarness(t, sa, width: 1700);
    await save(t, 'Save 1 message');
    final b = BookmarkSdk();
    b.emitBookmarks([
      const Bookmark(
          roomId: '!other', eventId: 'same', savedTs: 3, tags: ['private'])
    ]);
    final sb = bookmarkFixture(b, [message('same')], account: 'b');
    await bookmarkHarness(t, sb, width: 1700);
    await save(t, 'Save 1 message');
    expect(stored(b).map((e) => e.roomId).toSet(), {'!fixture', '!other'});
    expect(Bookmarks.of(sa.room.client), isEmpty);
    gate.complete();
    await t.pumpAndSettle();
    expect(stored(a), hasLength(1));
    expect(stored(a).single.tags, isEmpty);
  });

  testWidgets(
      'all saved selection disables action and reacts to synced removal',
      (t) async {
    final sdk = BookmarkSdk();
    sdk.emitBookmarks(
        [const Bookmark(roomId: '!fixture', eventId: 'a', savedTs: 1)]);
    final s = bookmarkFixture(sdk, [message('a')]);
    await bookmarkHarness(t, s, width: 1700);
    expect(
        find.byTooltip('Selected messages are already saved'), findsOneWidget);
    await t.tap(find.text('Save messages'));
    await t.pump();
    expect(sdk.writes, isEmpty);
    sdk.emitBookmarks([]);
    await t.pumpAndSettle();
    await save(t, 'Save 1 message');
    expect(stored(sdk).single.eventId, 'a');
  });

  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0), (800.0, 1.0)]) {
    testWidgets(
        'compact save remains reachable at $width and text scale $scale',
        (t) async {
      final sdk = BookmarkSdk();
      final s = bookmarkFixture(sdk, [message('a')]);
      await bookmarkHarness(t, s, width: width, scale: scale);
      await save(t, 'Save 1 message', compact: true, scale: scale);
      expect(stored(sdk).single.eventId, 'a');
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('queued batch rechecks redactions before writing', (t) async {
    final sdk = BookmarkSdk()..nextWrite = Completer<void>();
    final gate = sdk.nextWrite!;
    final s = bookmarkFixture(sdk, [message('a'), message('b')]);
    final first = Bookmarks.save(s.room.client, '!fixture', 'before');
    await t.pump();
    await bookmarkHarness(t, s, width: 1700);
    await save(t, 'Save 2 messages');
    (s.timeline as BookmarkTimeline).redacted.add('a');
    gate.complete();
    await t.pumpAndSettle();
    await first;
    expect(stored(sdk).map((b) => b.eventId).toSet(), {'before', 'b'});
    expect(s.ticked.ids, ['a']);
  });

  testWidgets(
      'unmounted selection does not write a queued batch or show stale feedback',
      (t) async {
    final sdk = BookmarkSdk()..nextWrite = Completer<void>();
    final gate = sdk.nextWrite!;
    final s = bookmarkFixture(sdk, [message('a')]);
    final first = Bookmarks.save(s.room.client, '!fixture', 'before');
    await t.pump();
    await bookmarkHarness(t, s);
    await save(t, 'Save 1 message');
    await t.pumpWidget(const SizedBox());
    gate.complete();
    await t.pumpAndSettle();
    await first;
    expect(sdk.writes, hasLength(1));
    expect(stored(sdk).single.eventId, 'before');
    expect(t.takeException(), isNull);
  });

  testWidgets('selected-message context menu saves the whole batch immediately',
      (t) async {
    final sdk = BookmarkSdk();
    final s = bookmarkFixture(sdk, [message('a'), message('b')]);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessageSelectionScope(
                selection: s, child: _MenuEntry(timeline: s.timeline!)))));
    await save(t, 'Save 2 messages');
    expect(stored(sdk).map((b) => b.eventId), ['b', 'a']);
    expect(find.byType(BookmarkTagEditor), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('selected-message context menu disables save when all are saved',
      (t) async {
    final sdk = BookmarkSdk();
    sdk.emitBookmarks(
        [const Bookmark(roomId: '!fixture', eventId: 'a', savedTs: 1)]);
    final s = bookmarkFixture(sdk, [message('a')]);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessageSelectionScope(
                selection: s, child: _MenuEntry(timeline: s.timeline!)))));
    // On the unmodified base this fails because the menu has no Save item.
    final item = find.widgetWithText(TextButton, 'Save messages');
    expect(item, findsOneWidget);
    expect(t.widget<TextButton>(item).onPressed, isNull);
    expect(
        find.byTooltip('Selected messages are already saved'), findsOneWidget);
    await t.tap(item);
    await t.pump();
    expect(sdk.writes, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('unsupported selection explains disabled save without writing',
      (t) async {
    final sdk = BookmarkSdk();
    final s = bookmarkFixture(sdk, [_Other('poll')]);
    await bookmarkHarness(t, s);
    expect(find.byTooltip('No selected messages can be saved'), findsOneWidget);
    await t.tap(find.text('Save messages'));
    await t.pump();
    expect(sdk.writes, isEmpty);
    expect(s.active, isTrue);
  });

  testWidgets(
      'single-save tag editor is still the existing flow after bulk saving',
      (t) async {
    final sdk = BookmarkSdk();
    final s = bookmarkFixture(sdk, [message('a')]);
    final context = await bookmarkHarness(t, s, width: 1700);
    await save(t, 'Save 1 message');
    final entries = BookmarkMenu.entries(s.room, message('a'), null);
    expect(entries.first.name, 'Edit saved tags');
    unawaited(BookmarkTagEditor.show(context, s.room.client, '!fixture', 'a'));
    await t.pumpAndSettle();
    expect(find.byType(BookmarkTagEditor), findsOneWidget);
  });
}
