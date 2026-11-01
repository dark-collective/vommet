import 'dart:async';
import 'dart:convert';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/role.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/room_layout_options.dart';
import 'package:commet/main.dart' show preferences;
import 'package:commet/ui/pages/main/room_chat_layout.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/ui/organisms/room_members_list/room_media_selection.dart';
import 'package:commet/ui/organisms/room_members_list/room_members_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

// Fixture media only; actions never call a server or device file picker.
class MediaPanelClient extends Fake implements Client {
  @override
  String get identifier => 'fixture';
  @override
  Profile? get self => null;
  @override
  T? getComponent<T extends Component>() => null;
}

class MediaPanelPermissions extends Permissions {}

class MediaPanelMatrixRoom extends Fake implements matrix.Room {
  @override
  String get id => '!fixture:example.org';
}

class MediaPanelEvent extends Fake
    implements TimelineEventMessage, MatrixTimelineEvent {
  MediaPanelEvent(int i, Uint8List bytes)
      : eventId = 'media-$i',
        originServerTs = DateTime(2026, 10, 31).subtract(Duration(minutes: i)),
        attachments = [
          i % 4 == 3
              ? VideoAttachment(MediaPanelFile(),
                  name: 'Video $i.mp4',
                  mimeType: 'video/mp4',
                  thumbnail: MemoryImage(bytes))
              : ImageAttachment(MemoryImage(bytes), MediaPanelFile(),
                  name: 'Photo $i.png', mimeType: 'image/png')
        ];
  @override
  final String eventId;
  @override
  final DateTime originServerTs;
  @override
  final List<Attachment> attachments;
  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;
  @override
  List<Uri> getLinks({Timeline? timeline}) => [];
  @override
  matrix.Event get event => matrix.Event(
          eventId: eventId,
          room: MediaPanelMatrixRoom(),
          type: 'm.room.message',
          senderId: '@fixture:example.org',
          originServerTs: originServerTs,
          content: {
            'msgtype': 'm.image',
            'body': 'Fixture media',
            'url': 'mxc://example.org/fixture'
          });
}

class MediaPanelFile extends Fake implements FileProvider {}

class MediaPanelTimeline extends Fake implements Timeline {
  MediaPanelTimeline(Uint8List bytes)
      : events = List.generate(36, (i) => MediaPanelEvent(i, bytes));
  @override
  final List<TimelineEvent> events;
  @override
  StreamController<int> onEventAdded = StreamController.broadcast();
  @override
  StreamController<int> onChange = StreamController.broadcast();
  @override
  StreamController<int> onRemove = StreamController.broadcast();
  @override
  bool isEventRedacted(TimelineEvent event) => false;
  @override
  bool get canLoadHistory => false;
  @override
  bool canDeleteEvent(TimelineEvent event) => canDelete;
  bool canDelete = true;
  @override
  Future<void> close() async {
    onEventAdded.close();
    onChange.close();
    onRemove.close();
  }
}

class MediaPanelRoom extends Fake implements Room {
  MediaPanelRoom(this.identifier, {Uint8List? bytes})
      : timeline = MediaPanelTimeline(bytes ??
            base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='));
  @override
  final String identifier;
  @override
  String get localId => 'fixture:$identifier';
  @override
  final MediaPanelTimeline timeline;
  @override
  final Client client = MediaPanelClient();
  @override
  final Permissions permissions = MediaPanelPermissions();
  @override
  T? getComponent<T extends RoomComponent>() => null;
  @override
  Stream<void> get onUpdate => const Stream.empty();
  @override
  Stream<void> get onMembersChanged => const Stream.empty();
  @override
  List<Member> membersList() => [];
  @override
  List<(Member, Role)> importantMembers() => [];
  @override
  List<Member> membersWithMembership(MemberMembership membership) => [];
  @override
  bool get isMembersListComplete => true;
  @override
  int get memberCount => 0;
  @override
  String get displayName => 'Weekend plans';
}

Future<void> initMediaPanelPreferences() async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  await memberPanelTabs.set(true);
  await preferences.layoutOverride.set('mobile');
  await preferences.experimentForwardMessages.set(true);
  await preferences.experimentSelectMessages.set(true);
}

RoomMediaSelection panelSelection(WidgetTester tester) =>
    tester.widget<RoomMediaGrid>(find.byType(RoomMediaGrid)).selection!;
Future<void> openMediaPanel(WidgetTester tester) async {
  await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('member-panel-tab-media'))),
      alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('member-panel-tab-media')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(initMediaPanelPreferences);
  Future<void> pump(WidgetTester tester, MediaPanelRoom room,
      {double scale = 1, double width = 320, VoidCallback? escape}) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(
                size: const Size(320, 700),
                textScaler: TextScaler.linear(scale)),
            child: Scaffold(
                body: CallbackShortcuts(
                    bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      escape ?? () {}
                },
                    child: Align(
                        alignment: Alignment.topRight,
                        child: SizedBox(
                            width: width,
                            child: RoomMembersListWidget(room,
                                key: const ValueKey('panel')))))))));
    await tester.pumpAndSettle();
  }

  testWidgets('long press, toggle, range, last untick, pinned contextual row',
      (tester) async {
    final room = MediaPanelRoom('gestures');
    addTearDown(room.timeline.close);
    await pump(tester, room);
    await openMediaPanel(tester);
    final tiles = find.byType(RoomMediaTileActions);
    await tester.longPress(tiles.first);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('member-panel-tab-media')), findsOneWidget);
    await tester.tap(tiles.at(1));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    final selection = panelSelection(tester);
    selection.tickRange('media-3');
    await tester.pumpAndSettle();
    expect(selection.ticked.length, 4);
    final barTop = tester.getTopLeft(find.byType(RoomMediaSelectionBar)).dy;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(RoomMediaSelectionBar)).dy, barTop);
    expect(find.byTooltip('Cancel').hitTestable(), findsOneWidget);
    selection.exit();
    selection.start('media-5');
    selection.toggle('media-5');
    await tester.pumpAndSettle();
    expect(find.byType(RoomMediaSelectionBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('filter, tab, room changes and closing clear selection',
      (tester) async {
    final first = MediaPanelRoom('first'), second = MediaPanelRoom('second');
    addTearDown(first.timeline.close);
    addTearDown(second.timeline.close);
    await pump(tester, first);
    await openMediaPanel(tester);
    panelSelection(tester).start('media-0');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-attachment-chip-photos')));
    await tester.pumpAndSettle();
    expect(panelSelection(tester).active, isFalse);
    panelSelection(tester).start('media-0');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-panel-tab-files')));
    await tester.pumpAndSettle();
    await openMediaPanel(tester);
    expect(panelSelection(tester).active, isFalse);
    panelSelection(tester).start('media-0');
    await tester.pumpAndSettle();
    await pump(tester, second);
    await openMediaPanel(tester);
    expect(panelSelection(tester).room, same(second));
    expect(panelSelection(tester).active, isFalse);
    panelSelection(tester).start('media-0');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await pump(tester, second);
    expect(panelSelection(tester).active, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('first Escape cancels, next reaches panel navigation',
      (tester) async {
    final room = MediaPanelRoom('escape');
    addTearDown(room.timeline.close);
    var escapes = 0;
    await pump(tester, room, escape: () => escapes++);
    await openMediaPanel(tester);
    panelSelection(tester).start('media-0');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panelSelection(tester).active, isFalse);
    expect(escapes, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(escapes, 1);
  });
  testWidgets('Back first clears without popping the page', (tester) async {
    final room = MediaPanelRoom('back');
    addTearDown(room.timeline.close);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav, home: const Scaffold(body: Text('Home'))));
    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: RoomMembersListWidget(room))));
    await tester.pumpAndSettle();
    await openMediaPanel(tester);
    panelSelection(tester).start('media-0');
    await tester.pumpAndSettle();
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(panelSelection(tester).active, isFalse);
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
  testWidgets('large text and one-item overflow keep count and 48 px actions',
      (tester) async {
    final room = MediaPanelRoom('large');
    addTearDown(room.timeline.close);
    await pump(tester, room, scale: 2);
    await openMediaPanel(tester);
    panelSelection(tester).start('media-0');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RoomMediaSelectionBar>(find.byType(RoomMediaSelectionBar))
            .countRowHeight,
        isNotNull);
    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Save')).height,
        greaterThanOrEqualTo(48));
    room.timeline.canDelete = false;
    panelSelection(tester).toggle('media-1');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.delete))
            .onPressed,
        isNull);
    panelSelection(tester).progress = 'Deleting 2 of 3…';
    await pump(tester, room, scale: 2);
    expect(find.text('Deleting 2 of 3…'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.save_alt))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('experiment off leaves no media selection', (tester) async {
    await preferences.experimentSelectMessages.set(false);
    final room = MediaPanelRoom('off');
    addTearDown(room.timeline.close);
    await pump(tester, room);
    await openMediaPanel(tester);
    await tester.longPress(find.byType(RoomMediaTileActions).first);
    await tester.pumpAndSettle();
    expect(find.byType(RoomMediaSelectionBar), findsNothing);
  });
  testWidgets('expanding preserves selection, hiding the live panel clears it',
      (tester) async {
    final room = MediaPanelRoom('desktop-layout');
    addTearDown(room.timeline.close);
    await preferences.layoutOverride.set('desktop');
    await preferences.hideRoomSidePanel.set(false);
    tester.view.physicalSize = const Size(1200, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RoomChatLayout(
                room: room,
                header: const SizedBox(height: 56),
                chat: const SizedBox.expand(),
                panel: (_) => RoomMembersListWidget(room)))));
    await tester.pumpAndSettle();
    await openMediaPanel(tester);
    final selection = panelSelection(tester)..start('media-0');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-panel-expand')));
    await tester.pumpAndSettle();
    expect(panelSelection(tester), same(selection));
    expect(selection.active, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selection.active, isFalse);
    expect(find.byTooltip('Back to the side'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand'), findsOneWidget);
    selection.start('media-0');
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(500, 750);
    await tester.pumpAndSettle();
    expect(selection.active, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('minimum panel width wraps actions with the one-item menu',
      (tester) async {
    final room = MediaPanelRoom('minimum-width');
    addTearDown(room.timeline.close);
    await pump(tester, room, width: 180);
    await openMediaPanel(tester);
    panelSelection(tester).start('media-0');
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    final save = find.byTooltip('Save');
    expect(tester.getSize(save).height, greaterThanOrEqualTo(48));
    expect(find.byType(PopupMenuButton<Function>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
