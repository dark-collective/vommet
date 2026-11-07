import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/matrix/components/threads/matrix_threads_component.dart';
import 'package:commet/client/matrix/components/threads/thread_reply_tracker.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart' show preferences;
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/translation/engine.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/gestures.dart';
import 'package:commet/utils/chat_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/context_menu.dart';

// Vommet issue 1077: "Follow thread" / "Unfollow thread" in the real message
// menu of a thread root in the main timeline, with the SDK faked at the
// network boundary.

const _me = "@me:example.org";
const _rootId = r"$root";

/// Rin's thread root as the local store keeps it: from before you replied,
/// so its summary says you didn't take part.
Map<String, Object?> _storedRoot(String roomId) => {
      "type": "m.room.message",
      "event_id": _rootId,
      "room_id": roomId,
      "sender": "@rin:example.org",
      "origin_server_ts": 1000,
      "content": {"msgtype": "m.text", "body": "Movie night on Friday?"},
      "unsigned": {
        "m.relations": {
          "m.thread": {"count": 1, "current_user_participated": false},
        },
      },
    };

class _Sdk extends Fake implements matrix.Client {
  final List<Map<String, Object?>> writes = [];

  @override
  String? get userID => _me;

  // The room is on "All threads": no thread reply rules.
  @override
  matrix.PushRuleSet? get globalPushRules => null;

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  // Saved messages and quick replies read account data.
  @override
  final Map<String, matrix.BasicEvent> accountData = {};

  @override
  Future<void> setAccountDataPerRoom(
    String userId,
    String roomId,
    String type,
    Map<String, Object?> body,
  ) async {
    if (type == "im.vommet.thread_follows") writes.add(body);
  }
}

// Vommet issue 1213: shared fixture also exercises own-message actions.
class _Self extends Fake implements Profile {
  @override
  String get identifier => _me;
}

class _Perms extends Permissions {
  @override
  bool get canSendMessage => true;

  @override
  bool get canUserEditMessages => true;
}

class _Client implements MatrixClient {
  _Client(this.sdk);
  final _Sdk sdk;
  @override
  final rooms = NotifyingList<Room>.empty();
  @override
  List<Space> get spaces => [];
  @override
  Profile get self => _Self();
  late final MatrixThreadsComponent threads = MatrixThreadsComponent(this);

  @override
  String get identifier => "fixture";

  @override
  matrix.Client getMatrixClient() => sdk;

  @override
  matrix.Client get matrixClient => sdk;

  @override
  T? getComponent<T extends Component>() => threads is T ? threads as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Room implements MatrixRoom {
  _Room(this.client, String id)
      : matrixRoom = matrix.Room(id: id, client: client.sdk);

  @override
  final _Client client;

  @override
  final matrix.Room matrixRoom;

  @override
  String get identifier => matrixRoom.id;

  @override
  Permissions get permissions => _Perms();

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SdkTimeline extends Fake implements matrix.Timeline {
  @override
  final Map<String, Map<String, Set<matrix.Event>>> aggregatedEvents = {};
}

/// The room's main timeline, holding the root.
class _Timeline implements MatrixTimeline {
  _Timeline(this.room, this.root);

  @override
  final _Room room;
  final TimelineEvent root;
  final deleted = <TimelineEvent>[];

  @override
  Future<void> deleteEvent(TimelineEvent event) async => deleted.add(event);

  @override
  Client get client => room.client;

  @override
  final matrix.Timeline matrixTimeline = _SdkTimeline();

  @override
  List<TimelineEvent> get events => [root];

  @override
  TimelineEvent? tryGetEvent(String id) => id == root.eventId ? root : null;

  @override
  bool canDeleteEvent(TimelineEvent event) => event.senderId == _me;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoEngine implements TranslationEngine {
  @override
  bool get available => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _translation = MessageTranslation(
  engine: _NoEngine(),
  android: false,
  systemLanguage: () => "en",
);

/// Each test has its own room: what you replied in is kept per room.
_Timeline _mainTimeline(String roomId, {bool own = false}) {
  final room = _Room(_Client(_Sdk()), roomId);
  final root = MatrixTimelineEventMessage(
    matrix.Event.fromJson(
        {..._storedRoot(roomId), if (own) 'sender': _me}, room.matrixRoom),
    client: room.client,
  );
  return _Timeline(room, root);
}

TimelineEventMenu _menu(_Timeline timeline, BuildContext context) =>
    TimelineEventMenu(
      timeline: timeline,
      event: timeline.root,
      translation: _translation,
      rooms: RoomTranslation(translation: _translation),
      context: context,
    );

/// A message row with the menu on right-click, its items made the way the
/// timeline's right-click menu makes them (timeline_view_entry.dart).
Widget _row(_Timeline timeline) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ContextMenu(
            itemsBuilder: () => [
              for (final i in _menu(timeline, context).secondaryActions)
                ContextMenuItem(
                  text: i.name,
                  icon: i.icon,
                  onPressed: () => i.action?.call(context),
                ),
            ],
            items: const [],
            child: const SizedBox(
              key: ValueKey("row"),
              width: 400,
              height: 40,
              child: Text("Movie night on Friday?"),
            ),
          ),
        ),
      ),
    );

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey("row")),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

Map<String, Object?>? _written(Map<String, Object?> body) =>
    ((body["threads"] as Map?)?[_rootId] as Map?)?.cast<String, Object?>();

// Vommet issue 1213: real menu wiring; skip unrelated message rendering.
class _AcceleratorEntry extends TimelineViewEntry {
  const _AcceleratorEntry(
      {required super.timeline, super.setReplyingEvent, super.setEditingEvent})
      : super(initialIndex: 0);
  @override
  State<TimelineViewEntry> createState() => _AcceleratorEntryState();
}

class _AcceleratorEntryState extends TimelineViewEntryState {
  @override
  void loadState(int index) {
    eventId = widget.timeline.events[index].eventId;
  }

  @override
  Widget build(BuildContext context) => desktopContextMenu(
      context,
      const SizedBox(
          width: 400,
          height: 40,
          key: ValueKey('row'),
          child: Text('Movie night on Friday?')));
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  // Vommet issue 1213: this compiles on the base and fails because R/E
  // do not activate the message menu there.
  testWidgets('real message menu activates Reply and Edit immediately',
      (tester) async {
    await preferences.experimentForwardMessages.set(true);
    final timeline = _mainTimeline('!accelerators:example.org', own: true);
    addTearDown(timeline.room.client.sdk.onSync.close);
    TimelineEvent? replied, edited;
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = call.arguments['text'] as String;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: _AcceleratorEntry(
                timeline: timeline,
                setReplyingEvent: (e) => replied = e,
                setEditingEvent: (e) => edited = e))));
    await _openMenu(tester);
    final marks = <String, String>{};
    for (final label in tester.widgetList<Text>(find.byType(Text))) {
      final span = label.textSpan;
      if (span is! TextSpan) continue;
      for (final child in span.children ?? <InlineSpan>[]) {
        if (child is TextSpan &&
            child.style?.decoration == TextDecoration.underline) {
          marks[span.toPlainText()] = child.text!;
        }
      }
    }
    expect(marks, {
      'Reply': 'R',
      'Edit': 'E',
      'Copy': 'C',
      'Delete': 'D',
      'Forward': 'F',
      'Reply In Thread': 'T'
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(replied, same(timeline.root));
    expect(find.byType(ContextMenuOverlay), findsNothing);
    await _openMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(edited, same(timeline.root));
    await _openMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(copied, 'Movie night on Friday?');
    expect(tester.takeException(), isNull);
  });

  // Vommet issue 1213: exercise the remaining keys through the real overlay.
  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    testWidgets('Delete, Forward and Thread dispatch on ${platform.name}',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await preferences.layoutOverride.set('desktop');
      await preferences.experimentForwardMessages.set(true);
      await preferences.askBeforeDeletingMessageEnabled.set(true);
      final timeline = _mainTimeline('!dispatch:example.org', own: true);
      addTearDown(timeline.room.client.sdk.onSync.close);
      final navigation = ChatNavigation();
      addTearDown(navigation.dispose);
      final local = <(String, String, String)>[];
      final main = <(String, String, String)>[];
      final replies = <String>[];
      for (final sub in [
        navigation.openThread.stream.listen(local.add),
        navigation.replyInThread.stream.listen(replies.add),
        ChatNavigation.main.openThread.stream.listen(main.add),
      ]) {
        addTearDown(sub.cancel);
      }
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        ),
        home: Scaffold(
          body: ChatNavigationScope(
            navigation: navigation,
            child: _AcceleratorEntry(timeline: timeline),
          ),
        ),
      ));
      final row = tester.element(find.byKey(const ValueKey('row')));
      expect(Theme.of(row).platform, platform);
      expect(MediaQuery.textScalerOf(row).scale(16), 16);
      Future<void> press(LogicalKeyboardKey key) async {
        await _openMenu(tester);
        await tester.sendKeyEvent(key, platform: platform.name);
        await tester.pumpAndSettle();
        expect(find.byType(ContextMenuOverlay), findsNothing);
      }

      await press(LogicalKeyboardKey.keyD);
      expect(timeline.deleted, isEmpty);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(timeline.deleted, isEmpty);
      await press(LogicalKeyboardKey.keyD);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(timeline.deleted, [timeline.root]);

      await press(LogicalKeyboardKey.keyF);
      final picker = find.byType(ForwardMessageDialog);
      expect(picker, findsOneWidget);
      Navigator.of(tester.element(picker)).pop();
      await tester.pumpAndSettle();

      await press(LogicalKeyboardKey.keyT);
      expect(local,
          [(timeline.client.identifier, timeline.room.identifier, _rootId)]);
      expect(replies, [_rootId]);
      expect(main, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Reply in Thread menu keeps its originating workspace in overlays',
      (tester) async {
    final navigation = ChatNavigation();
    final mainEvents = <(String, String, String)>[];
    final localEvents = <(String, String, String)>[];
    final replies = <String>[];
    final subscriptions = [
      ChatNavigation.main.openThread.stream.listen(mainEvents.add),
      navigation.openThread.stream.listen(localEvents.add),
      navigation.replyInThread.stream.listen(replies.add),
    ];
    final timeline = _mainTimeline('!menu:example.org');
    late BuildContext overlayContext;
    late TimelineEventMenu menu;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      overlayContext = context;
      return ChatNavigationScope(
          navigation: navigation,
          child: Builder(builder: (context) {
            menu = _menu(timeline, context);
            return const SizedBox();
          }));
    })));
    final reply = menu.secondaryActions
        .singleWhere((entry) => entry.name == menu.promptReplyInThread);
    reply.action!(overlayContext);
    await tester.pump();
    expect(localEvents,
        [(timeline.client.identifier, timeline.room.identifier, _rootId)]);
    expect(replies, [_rootId]);
    expect(mainEvents, isEmpty);
    await tester.pumpWidget(const SizedBox());
    for (final sub in subscriptions) {
      sub.cancel();
    }
    navigation.dispose();
  });

  testWidgets(
      "a thread you replied in says Unfollow thread in the root's menu "
      "though the stored root is stale", (tester) async {
    final timeline = _mainTimeline("!replied:example.org");
    final room = timeline.room;
    // Your reply arrives in sync (you replied, then closed the thread).
    await ThreadReplyTracker(room.client.sdk).onEvent(
      matrix.Event.fromJson({
        "type": "m.room.message",
        "event_id": r"$mine",
        "room_id": room.identifier,
        "sender": _me,
        "origin_server_ts": DateTime.now().millisecondsSinceEpoch,
        "content": {
          "msgtype": "m.text",
          "body": "I'll bring snacks",
          "m.relates_to": {"rel_type": "m.thread", "event_id": _rootId},
        },
      }, room.matrixRoom),
    );
    await tester.pumpWidget(_row(timeline));
    await _openMenu(tester);
    expect(find.text("Unfollow thread"), findsOneWidget);
    expect(find.text("Follow thread"), findsNothing);
  });

  testWidgets("Follow thread in the message menu follows, then unfollows",
      (tester) async {
    final timeline = _mainTimeline("!follow:example.org");
    final sdk = timeline.room.client.sdk;
    await tester.pumpWidget(_row(timeline));
    await _openMenu(tester);
    await tester.tap(find.text("Follow thread"));
    await tester.pumpAndSettle();
    expect(sdk.writes, hasLength(1));
    expect(_written(sdk.writes.single)?["follow"], isTrue);
    expect(_written(sdk.writes.single)?["automatic"], isNull);

    await _openMenu(tester);
    await tester.tap(find.text("Unfollow thread"));
    await tester.pumpAndSettle();
    expect(sdk.writes, hasLength(2));
    expect(_written(sdk.writes.last)?["follow"], isFalse);
  });
}
