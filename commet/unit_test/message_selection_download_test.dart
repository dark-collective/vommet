import 'dart:async';
import 'dart:typed_data';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_bar.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_host.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SelectionClient extends Fake implements Client {
  @override
  String get identifier => 'fixture-client';
  @override
  T? getComponent<T extends Component>() => null;
}

class SelectionRoom extends Fake implements Room {
  @override
  final Client client = SelectionClient();
  @override
  String get identifier => '!fixture';
  @override
  String get displayName => 'Weekend photos';
  @override
  T? getComponent<T extends RoomComponent>() => null;
  @override
  Stream<void> get onUpdate => const Stream.empty();
  @override
  Stream<void> get onMembersChanged => const Stream.empty();
}

class SelectionTimeline extends Fake implements Timeline {
  SelectionTimeline(this.room, this.events);
  @override
  final Room room;
  @override
  final List<TimelineEvent> events;
  @override
  Client get client => room.client;
  @override
  bool isEventRedacted(TimelineEvent event) => false;
  @override
  bool canDeleteEvent(TimelineEvent event) => false;
  @override
  TimelineEvent? tryGetEvent(String id) =>
      events.where((e) => e.eventId == id).firstOrNull;
}

class _SelectionMatrixRoom extends Fake implements matrix.Room {
  @override
  String get id => '!fixture:example.org';
}

class SelectionMessage extends Fake
    implements TimelineEventMessage, MatrixTimelineEvent {
  SelectionMessage(this.eventId, this.attachments,
      {this.plainTextBody = 'Fixture message'});
  @override
  final String eventId;
  @override
  final List<Attachment>? attachments;
  @override
  final String plainTextBody;
  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;
  @override
  matrix.Event get event => matrix.Event(
          room: _SelectionMatrixRoom(),
          eventId: eventId,
          type: 'm.room.message',
          senderId: '@maya:example.org',
          originServerTs: DateTime(2026, 10, 31),
          content: {
            'msgtype': attachments?.isNotEmpty == true ? 'm.image' : 'm.text',
            'body': plainTextBody,
            'url': 'mxc://example.org/fixture'
          });
}

class SelectionFile extends Fake implements FileProvider {}

ImageAttachment selectionPhoto(String name) =>
    ImageAttachment(MemoryImage(Uint8List(0)), SelectionFile(),
        name: name, mimeType: 'image/png');
VideoAttachment selectionVideo() =>
    VideoAttachment(SelectionFile(), name: 'walk.mp4', mimeType: 'video/mp4');

Future<MediaSaveOutcome> completeSave(
  List<FileAttachment> files, {
  required void Function(int, int) onProgress,
  required void Function(int) onSaved,
  required bool Function() shouldContinue,
}) async {
  for (var i = 0; i < files.length; i++) {
    if (!shouldContinue()) return MediaSaveOutcome.canceled;
    onProgress(i + 1, files.length);
    onSaved(i);
  }
  return MediaSaveOutcome.completed;
}

MessageSelection selectionFixture(List<SelectionMessage> oldestFirst,
    {SelectedMediaSaver saver = completeSave}) {
  final room = SelectionRoom();
  return MessageSelection(room, mediaSaver: saver)
    ..timeline = SelectionTimeline(room, oldestFirst.reversed.toList())
    ..start([for (final e in oldestFirst) e.eventId]);
}

Future<BuildContext> selectionHarness(
    WidgetTester tester, MessageSelection selection,
    {double width = 1400, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 600), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: Column(children: [
            SizedBox(height: 50, child: MessageSelectionBar(selection)),
          ])))));
  await tester.pump();
  return tester.element(find.byType(MessageSelectionBar));
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.experimentForwardMessages.set(true);
  });
  testWidgets(
      'mixed selection filters files and deduplicates event/attachment entries in timeline order',
      (t) async {
    final photo = selectionPhoto('same.png');
    final a = SelectionMessage('a', [photo, photo]);
    final selection = selectionFixture([
      SelectionMessage('text', null),
      a,
      SelectionMessage(
          'document', [FileAttachment(SelectionFile(), name: 'route.pdf')]),
      SelectionMessage('b', [photo, selectionVideo()]),
      a
    ]);
    await selectionHarness(t, selection);
    expect(
        selection.downloadableMedia().map((e) => e.eventId), ['a', 'b', 'b']);
    expect(find.text('Download 3'), findsOneWidget);
    selection.dispose();
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets(
      'busy starts before awaiting and blocks repeat saves and selection mutation; success exits',
      (t) async {
    final gate = Completer<void>();
    var calls = 0;
    final selection = selectionFixture([
      SelectionMessage('a', [selectionPhoto('a.png')]),
      SelectionMessage('text', null)
    ], saver: (files,
        {required onProgress,
        required onSaved,
        required shouldContinue}) async {
      calls++;
      await gate.future;
      onSaved(0);
      return MediaSaveOutcome.completed;
    });
    final context = await selectionHarness(t, selection);
    selection.toggle(['a']);
    selection.dragStart(['a']);
    final save = selection.save(context);
    expect(selection.busy, isTrue);
    expect(selection.ticked.dragging, isFalse);
    await selection.save(context);
    selection.toggle(['a']);
    selection.start(['other']);
    selection.copy();
    expect(calls, 1);
    expect(selection.ticked.ids, unorderedEquals(['a', 'text']));
    await t.pump();
    expect(
        t
            .widget<TextButton>(
                find.byKey(const ValueKey('message-selection-download')))
            .onPressed,
        isNull);
    gate.complete();
    await save;
    await t.pump();
    expect(selection.active, isFalse);
    expect(find.text('Saved 1 item'), findsOneWidget);
    selection.dispose();
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  for (final outcome in [
    MediaSaveOutcome.permissionDenied,
    MediaSaveOutcome.canceled
  ]) {
    testWidgets('$outcome preserves selection and never reports success',
        (t) async {
      final selection = selectionFixture([
        SelectionMessage('a', [selectionPhoto('a.png')])
      ],
          saver: (files,
                  {required onProgress,
                  required onSaved,
                  required shouldContinue}) async =>
              outcome);
      final context = await selectionHarness(t, selection);
      await selection.save(context);
      await t.pump();
      expect(selection.ticked.ids, ['a']);
      expect(selection.active, isTrue);
      expect(selection.busy, isFalse);
      expect(find.text('Saved 1 item'), findsNothing);
      expect(
          find.text(MessageSelection.messageSelectionGalleryDenied),
          outcome == MediaSaveOutcome.permissionDenied
              ? findsOneWidget
              : findsNothing);
      selection.dispose();
      await t.pumpWidget(const SizedBox());
      t.view.reset();
    });
  }
  testWidgets(
      'partial failure retains pending media and text; retry skips successful attachment in same event',
      (t) async {
    final a = selectionPhoto('a.png'), b = selectionPhoto('b.png');
    final video = selectionVideo();
    var attempt = 0;
    final selection = selectionFixture([
      SelectionMessage('photos', [a, b]),
      SelectionMessage('video', [video]),
      SelectionMessage('text', null)
    ], saver: (files,
        {required onProgress,
        required onSaved,
        required shouldContinue}) async {
      if (attempt++ == 0) {
        onSaved(0);
        throw StateError('Unavailable media');
      }
      expect(files, [b, video]);
      return completeSave(files,
          onProgress: onProgress,
          onSaved: onSaved,
          shouldContinue: shouldContinue);
    });
    final context = await selectionHarness(t, selection);
    await selection.save(context);
    await t.pumpAndSettle();
    expect(find.text('Saved 1 of 3 items'), findsOneWidget);
    expect(find.textContaining('Unavailable media'), findsOneWidget);
    expect(selection.downloadableMedia().map((e) => e.file), [b, video]);
    expect(selection.ticked.ids, unorderedEquals(['photos', 'video', 'text']));
    Navigator.of(t.element(find.text('Saved 1 of 3 items'))).pop();
    await t.pumpAndSettle();
    await selection.save(context);
    await t.pump();
    expect(selection.active, isFalse);
    selection.dispose();
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('partial cancellation unticks completed events only', (t) async {
    final selection = selectionFixture([
      SelectionMessage('a', [selectionPhoto('a.png')]),
      SelectionMessage('b', [selectionVideo()]),
      SelectionMessage('text', null)
    ], saver: (files,
        {required onProgress,
        required onSaved,
        required shouldContinue}) async {
      onSaved(0);
      return MediaSaveOutcome.canceled;
    });
    final context = await selectionHarness(t, selection);
    await selection.save(context);
    await t.pump();
    expect(selection.ticked.ids, unorderedEquals(['b', 'text']));
    expect(find.text('Saved 1 of 2 items'), findsOneWidget);
    selection.toggle(['a']);
    expect(
        selection.downloadableMedia().map((item) => item.eventId), ['a', 'b']);
    selection.dispose();
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets(
      'navigation/disposal stops subsequent saves and ignores late callbacks',
      (t) async {
    final gate = Completer<void>();
    bool? canContinue;
    final selection = selectionFixture([
      SelectionMessage('a', [selectionPhoto('a.png')])
    ], saver: (files,
        {required onProgress,
        required onSaved,
        required shouldContinue}) async {
      await gate.future;
      canContinue = shouldContinue();
      onSaved(0);
      return MediaSaveOutcome.completed;
    });
    final context = await selectionHarness(t, selection);
    final save = selection.save(context);
    await t.pumpWidget(const SizedBox());
    selection.dispose();
    gate.complete();
    await save;
    await t.pump();
    expect(canContinue, isFalse);
    expect(t.takeException(), isNull);
    t.view.reset();
  });
  testWidgets(
      'a late save result cannot clear a new selection in the same room',
      (t) async {
    final gate = Completer<void>();
    final selection = selectionFixture([
      SelectionMessage('a', [selectionPhoto('a.png')]),
      SelectionMessage('b', [selectionVideo()]),
    ], saver: (files,
        {required onProgress,
        required onSaved,
        required shouldContinue}) async {
      await gate.future;
      expect(shouldContinue(), isFalse);
      onSaved(0);
      return MediaSaveOutcome.canceled;
    });
    selection.start(['a']);
    final context = await selectionHarness(t, selection);
    final saving = selection.save(context);
    selection.exit();
    selection.start(['b']);
    gate.complete();
    await saving;
    await t.pump();
    expect(selection.ticked.ids, ['b']);
    expect(selection.active, isTrue);
    expect(selection.busy, isFalse);
    selection.dispose();
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });

  testWidgets(
      'responsive controls keep Download beside Copy; narrow/large text actions use accessible overflow',
      (t) async {
    final selection = selectionFixture([
      SelectionMessage('a', [selectionPhoto('a.png')])
    ]);
    for (final width in [920.0, 700.0, 520.0, 390.0, 320.0, 240.0, 180.0]) {
      for (final scale in [1.0, 2.0]) {
        await selectionHarness(t, selection, width: width, scale: scale);
        expect(t.takeException(), isNull, reason: '$width/$scale');
        final copy = find.byTooltip('Copy');
        final download =
            find.byKey(const ValueKey('message-selection-download'));
        if (copy.evaluate().isNotEmpty) {
          expect(t.getCenter(copy).dx, lessThan(t.getCenter(download).dx));
          expect(t.getCenter(download).dx - t.getCenter(copy).dx,
              closeTo(48, 0.1));
        }
      }
    }
    final semantics = t.ensureSemantics();
    await selectionHarness(t, selection, width: 320, scale: 2);
    expect(find.bySemanticsLabel('1 selected'), findsOneWidget);
    semantics.dispose();
    await t.tap(find.byKey(const ValueKey('message-selection-more')));
    await t.pumpAndSettle();
    expect(find.text('Forward 1'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(
        t
            .widget<PopupMenuItem>(find.ancestor(
                of: find.text('Delete'),
                matching: find
                    .byWidgetPredicate((widget) => widget is PopupMenuItem)))
            .enabled,
        isFalse);
    selection.dispose();
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
  testWidgets('Back preserves selection while busy and exits after the batch',
      (t) async {
    final fixture = selectionFixture([
      SelectionMessage('a', [selectionPhoto('a.png')])
    ]);
    late MessageSelection local;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessageSelectionHost(
      room: fixture.room,
      timeline: fixture.timeline!,
      child: Builder(builder: (context) {
        local = MessageSelectionScope.maybeOf(context)!;
        return const SizedBox();
      }),
    ))));
    local.start(['a']);
    local.progress = 'Saving 1 of 1…';
    final busyBack = ScopePopped();
    EventBus.onPopInvoked.add(busyBack);
    expect(busyBack.handled, isTrue);
    expect(local.active, isTrue);
    local.progress = null;
    final idleBack = ScopePopped();
    EventBus.onPopInvoked.add(idleBack);
    expect(idleBack.handled, isTrue);
    expect(local.active, isFalse);
    await t.pumpWidget(const SizedBox());
    fixture.dispose();
    await t.pump();
  });

  testWidgets('text and unsupported attachments alone disable Download',
      (t) async {
    final selection = selectionFixture([
      SelectionMessage('text', null),
      SelectionMessage(
          'audio', [AudioAttachment(SelectionFile(), name: 'voice.ogg')])
    ]);
    await selectionHarness(t, selection, width: 390);
    // A phone-width bar keeps Reply and Delete as icons, no overflow menu.
    expect(
        find.byKey(const ValueKey('message-selection-reply')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-selection-more')), findsNothing);
    expect(
        t
            .widget<IconButton>(
                find.byKey(const ValueKey('message-selection-download')))
            .onPressed,
        isNull);
    selection.progress = 'Saving 1 of 2…';
    await t.pump();
    selection.dispose();
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
}
