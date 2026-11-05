import 'dart:async';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/atoms/message_attachment.dart';
import 'package:commet/ui/molecules/video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/panel.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/organisms/bookmarks/saved_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as mx;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _File extends Fake implements FileProvider {}

class _Sdk extends Fake implements mx.Client {
  @override
  final Map<String, mx.BasicEvent> accountData = {};
  @override
  final onSync = CachedStreamController<mx.SyncUpdate>();
}

class _Event extends Fake implements TimelineEvent {
  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;
}

class _Room extends Fake implements Room {
  _Room(this.displayName, this.load);
  @override
  final String displayName;
  final Future<TimelineEvent?> Function(String) load;
  @override
  Future<TimelineEvent?> getEvent(String id) => load(id);
}

class _Client extends Fake implements MatrixClient {
  _Client(this.matrixClient, this.byId);
  @override
  final mx.Client matrixClient;
  final Map<String, Room> byId;
  @override
  Room? getRoom(String id) => byId[id];
}

final photos = find.byKey(const ValueKey('saved-media-photos'));
final videos = find.byKey(const ValueKey('saved-media-videos'));
Future<_Sdk> open(
  WidgetTester t, {
  int count = 2,
  bool fail = false,
  Size size = const Size(900, 800),
  double scale = 1,
  Completer<TimelineEvent?>? hold,
  List<String>? calls,
  TimelineEvent? Function()? response,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final sdk = _Sdk();
  addTearDown(sdk.onSync.close);
  sdk.accountData[Bookmarks.type] = mx.BasicEvent(
    type: Bookmarks.type,
    content: Bookmarks.serialize(
      List.generate(
        count,
        (i) => Bookmark(
          roomId: i.isEven ? 'a' : 'b',
          eventId: '$i',
          savedTs: count - i,
          tags: [i.isEven ? 'work' : 'ideas'],
          note: 'Saved note $i',
        ),
      ),
    ),
  );
  final client = _Client(sdk, {
    for (final id in ['a', 'b'])
      id: _Room(id == 'a' ? 'Engineering' : 'Social', (eventId) async {
        calls?.add('$id/$eventId');
        if (hold != null) return hold.future;
        return response != null
            ? response()
            : fail
                ? null
                : _Event();
      }),
  });
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeDark.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(child: SavedMessages(client: client)),
      ),
    ),
  );
  await t.pump();
  await t.pump();
  return sdk;
}

void main() {
  testWidgets(
    'media chips are exclusive and tapping active clears only media',
    (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('saved-tag-work')));
      await t.pumpAndSettle();
      await t.tap(photos);
      await t.pumpAndSettle();
      expect(t.widget<ChoiceChip>(photos).selected, isTrue);
      expect(find.text(SavedMessages.savedNoPhotos), findsOneWidget);
      await t.tap(videos);
      await t.pumpAndSettle();
      expect(t.widget<ChoiceChip>(videos).selected, isTrue);
      expect(t.widget<ChoiceChip>(photos).selected, isFalse);
      await t.tap(videos);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('saved-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-1')), findsNothing);
      expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('saved-tag-work')))
            .selected,
        isTrue,
      );
    },
  );
  testWidgets('room and tag compose with media; reset preserves both', (
    t,
  ) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('saved-room-filter')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('saved-room-option-a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('saved-tag-work')));
    await t.pumpAndSettle();
    await t.tap(photos);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('saved-media-clear')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('saved-room-active')), findsOneWidget);
    expect(
      t
          .widget<ChoiceChip>(find.byKey(const ValueKey('saved-tag-work')))
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('saved-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('saved-1')), findsNothing);
  });
  testWidgets(
    'unavailable events never claim an empty result; clearing exposes notes',
    (t) async {
      await open(t, fail: true);
      await t.tap(photos);
      await t.pumpAndSettle();
      expect(find.text(SavedMessages.savedNoPhotos), findsNothing);
      expect(find.byKey(const ValueKey('saved-media-retry')), findsOneWidget);
      expect(find.text(SavedMessages.savedUnavailableCount(2)), findsOneWidget);
      await t.tap(find.text(SavedMessages.savedAllMedia));
      await t.pumpAndSettle();
      expect(find.text('Saved note 0'), findsOneWidget);
      expect(find.text(SavedMessages.labelSavedUnavailable), findsNWidgets(2));
    },
  );
  testWidgets('unchecked events use explicit Check more, never empty', (
    t,
  ) async {
    await open(t, count: 80);
    await t.tap(photos);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('saved-media-more')), findsOneWidget);
    expect(find.text(SavedMessages.savedNoPhotos), findsNothing);
    await t.tap(find.byKey(const ValueKey('saved-media-more')));
    await t.pumpAndSettle();
    expect(find.text(SavedMessages.savedNoPhotos), findsNothing);
  });
  testWidgets(
    'stalled lookups show progress and slow notice; dispose cancels timers',
    (t) async {
      final hold = Completer<TimelineEvent?>();
      await open(t, hold: hold);
      await t.tap(photos);
      await t.pump();
      expect(find.text(SavedMessages.savedChecking), findsOneWidget);
      expect(find.text(SavedMessages.savedNoPhotos), findsNothing);
      await t.pump(const Duration(seconds: 16));
      expect(find.text(SavedMessages.savedSlow), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      hold.complete(null);
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'room and tag narrow references before a media batch is scheduled',
    (t) async {
      final calls = <String>[];
      await open(t, count: 100, calls: calls);
      await t.tap(find.byKey(const ValueKey('saved-room-filter')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('saved-room-option-a')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('saved-tag-work')));
      await t.pumpAndSettle();
      calls.clear();
      await t.tap(photos);
      await t.pumpAndSettle();
      expect(calls, isNotEmpty);
      expect(calls.length, lessThanOrEqualTo(24));
      expect(
        calls.every(
          (id) => id.startsWith('a/') && int.parse(id.split('/').last).isEven,
        ),
        isTrue,
      );
    },
  );
  testWidgets('explicit retry changes unavailable to a confirmed result', (
    t,
  ) async {
    var failed = true;
    await open(t, response: () => failed ? null : _Event());
    await t.tap(photos);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('saved-media-retry')), findsOneWidget);
    failed = false;
    await t.tap(find.byKey(const ValueKey('saved-media-retry')));
    await t.pumpAndSettle();
    expect(find.text(SavedMessages.savedNoPhotos), findsOneWidget);
    expect(find.byKey(const ValueKey('saved-media-retry')), findsNothing);
  });
  testWidgets(
    'sync redaction invalidates the cached event without declaring it unreadable',
    (t) async {
      final sdk = await open(t, count: 1);
      sdk.onSync.add(
        mx.SyncUpdate(
          nextBatch: 'redact',
          rooms: mx.RoomsUpdate(
            join: {
              'a': mx.JoinedRoomUpdate(
                timeline: mx.TimelineUpdate(
                  events: [
                    mx.MatrixEvent(
                      type: 'm.room.redaction',
                      content: {'redacts': '0'},
                      eventId: 'redact',
                      senderId: '@me:example.org',
                      originServerTs: DateTime(2026),
                    ),
                  ],
                ),
              ),
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(photos);
      await t.pumpAndSettle();
      expect(find.text(SavedMessages.savedNoPhotos), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-media-retry')), findsNothing);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '320px phone controls and privacy remain reachable at text scale $scale',
      (t) async {
        await open(t, size: const Size(320, 640), scale: scale);
        expect(t.getSize(photos).height, greaterThanOrEqualTo(48));
        await t.tap(photos);
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.text(SavedMessages.labelSavedPrivacy),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        expect(
          find.text(SavedMessages.labelSavedPrivacy).hitTestable(),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
      'saved video preview header grows with large text without clipping the frame',
      (t) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    final video = VideoAttachment(_File(),
        name: 'Trail video.mp4',
        fileSize: 2048,
        mimeType: 'video/mp4',
        width: 640,
        height: 360);
    double? normalHeight;
    for (final scale in [1.0, 1.5, 2.0]) {
      await t.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(
              body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                      child: SizedBox(
                          width: 320,
                          child: MessageAttachment(video,
                              key: ValueKey(scale), previewMedia: true)))))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final panel = t.getSize(find.byType(Panel)).height;
      if (scale == 1) {
        normalHeight = panel;
      } else {
        expect(panel, greaterThan(normalHeight!));
      }
      expect(t.getSize(find.byType(VideoPlayer)).height, 200);
    }
  });
}
