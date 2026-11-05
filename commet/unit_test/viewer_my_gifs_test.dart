import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:commet/ui/molecules/my_gifs.dart';
import 'package:commet/ui/molecules/my_gifs_from_viewer.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class ViewerClient extends Fake implements Client {
  final gifs = ViewerGifs();
  bool loggedIn = true;
  bool hasGifs = true;
  @override
  bool isLoggedIn() => loggedIn;
  @override
  T? getComponent<T extends Component>() =>
      hasGifs && gifs is T ? gifs as T : null;
}

class ViewerRoom extends Fake implements Room {
  ViewerRoom(this.client);
  @override
  final ViewerClient client;
  @override
  Member getMemberOrFallback(String id) => ViewerMember();
  @override
  Timeline? get timeline => null; // Media feed can contain unloaded messages.
}

class ViewerMember extends Fake implements Member {
  @override
  String get displayName => 'Someone';
}

class ViewerEvent extends Fake implements TimelineEventMessage {
  ViewerEvent(this.eventId,
      {this.gif = true,
      this.encrypted = false,
      this.status = TimelineEventStatus.synced,
      this.attachments});
  final bool gif;
  final bool encrypted;
  @override
  final String eventId;
  @override
  final TimelineEventStatus status;
  @override
  final List<Attachment>? attachments;
  @override
  String get senderId => '@sender:example.org';
}

class OtherMatrixClient extends Fake implements MatrixClient {}

class OtherAccountEvent extends Fake implements MatrixTimelineEvent {
  @override
  final MatrixClient client = OtherMatrixClient();
  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;
}

class ViewerGifs extends Fake implements GifComponent {
  final saved = <String>{};
  final writes = <String>[];
  Completer<void>? saving;
  bool fail = false;
  @override
  bool isGif(TimelineEvent event) => (event as ViewerEvent).gif;
  @override
  bool isFavoriteGif(TimelineEvent event) => saved.contains(event.eventId);
  @override
  bool savesUnencryptedCopy(TimelineEvent event) =>
      (event as ViewerEvent).encrypted;
  @override
  Future<void> setFavoriteFromEvent(TimelineEvent event) async {
    writes.add('add:${event.eventId}');
    await saving?.future;
    if (fail) throw StateError('test failure');
    saved.add(event.eventId);
  }

  @override
  Future<void> removeFavoriteFromEvent(TimelineEvent event) async {
    writes.add('remove:${event.eventId}');
    saved.remove(event.eventId);
  }
}

class ViewerFile extends Fake implements FileProvider {}

const viewerPng = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0xf8,
  0xcf,
  0xc0,
  0xf0,
  0x1f,
  0x00,
  0x05,
  0x00,
  0x01,
  0xff,
  0x89,
  0x99,
  0x3d,
  0x1d,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
ImageAttachment viewerImage(String id) =>
    ImageAttachment(MemoryImage(Uint8List.fromList(viewerPng)), ViewerFile(),
        name: '$id.gif', mimeType: 'image/gif');

Future<void> openViewer(WidgetTester tester, ViewerRoom room, ViewerEvent event,
    {double scale = 1}) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  onPressed: () => Lightbox.show(context,
                      image: viewerImage('fixture').image,
                      onReply: () {},
                      onForward: () {},
                      myGifsMenuEntry: () => myGifsFromViewer(room, event)),
                  child: const Text('open'))))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> openViewerMenu(WidgetTester tester) async {
  await tester
      .tap(find.byKey(const ValueKey('lightbox_menu_button')).hitTestable());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  test('requires synced recognized media, its room, account and component', () {
    final client = ViewerClient(),
        room = ViewerRoom(ViewerClient()),
        event = ViewerEvent('gif');
    expect(myGifsFromViewer(null, event), isNull);
    expect(myGifsFromViewer(room, null), isNull);
    expect(myGifsFromViewer(room, OtherAccountEvent()), isNull);
    expect(
        myGifsFromViewer(
            room, ViewerEvent('sending', status: TimelineEventStatus.sending)),
        isNull);
    expect(myGifsFromViewer(room, ViewerEvent('photo', gif: false)), isNull);
    client.hasGifs = false;
    expect(myGifsFromViewer(ViewerRoom(client), event), isNull);
    client.hasGifs = true;
    client.loggedIn = false;
    expect(myGifsFromViewer(ViewerRoom(client), event), isNull);
  });
  testWidgets(
      'Add, feedback, Undo and Remove stay in the viewer and use its account',
      (tester) async {
    final client = ViewerClient(),
        other = ViewerClient(),
        event = ViewerEvent('gif');
    await openViewer(tester, ViewerRoom(client), event);
    await openViewerMenu(tester);
    expect(find.text(MyGifs.promptSaveToFolder), findsNothing);
    expect(tester.getTopLeft(find.text(MyGifs.promptAdd)).dy,
        greaterThan(tester.getTopLeft(find.text('Forward')).dy));
    await tester.tap(find.text(MyGifs.promptAdd));
    await tester.pumpAndSettle();
    expect(client.gifs.saved, {'gif'});
    expect(other.gifs.saved, isEmpty);
    expect(find.byType(Lightbox), findsOneWidget);
    expect(find.text(MyGifs.added).hitTestable(), findsOneWidget);
    await tester.tap(find.text(MyGifs.promptUndo));
    await tester.pumpAndSettle();
    expect(client.gifs.saved, isEmpty);
    client.gifs.saved.add('gif');
    await openViewerMenu(tester);
    expect(find.text(MyGifs.promptRemove), findsOneWidget);
    expect(find.text(MyGifs.promptAdd), findsNothing);
    await tester.tap(find.text(MyGifs.promptRemove));
    await tester.pumpAndSettle();
    expect(client.gifs.saved, isEmpty);
  });
  testWidgets('ordinary media retain file actions without collection actions',
      (tester) async {
    await openViewer(
        tester, ViewerRoom(ViewerClient()), ViewerEvent('photo', gif: false));
    await openViewerMenu(tester);
    expect(find.text(MyGifs.promptAdd), findsNothing);
    expect(find.text(MyGifs.promptRemove), findsNothing);
    expect(find.text('Save as…'), findsOneWidget);
    expect(find.text('Forward'), findsOneWidget);
  });
  testWidgets(
      'cancel encrypted-copy question never writes; confirming reuses the flow',
      (tester) async {
    final client = ViewerClient();
    await MyGifs.askBeforeUnencryptedCopy.set(true);
    await openViewer(
        tester, ViewerRoom(client), ViewerEvent('encrypted', encrypted: true));
    await openViewerMenu(tester);
    await tester.tap(find.text(MyGifs.promptAdd));
    await tester.pumpAndSettle();
    expect(find.text(MyGifs.copyBody), findsOneWidget);
    expect(client.gifs.writes, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.gifs.writes, isEmpty);
    await openViewerMenu(tester);
    await tester.tap(find.text(MyGifs.promptAdd));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MyGifs.promptSaveCopy));
    await tester.pumpAndSettle();
    expect(client.gifs.saved, {'encrypted'});
  });
  testWidgets(
      'duplicate in-flight actions are suppressed and failures can retry',
      (tester) async {
    final client = ViewerClient(), event = ViewerEvent('gif');
    final room = ViewerRoom(client);
    client.gifs.saving = Completer<void>();
    await openViewer(tester, room, event);
    await openViewerMenu(tester);
    await tester.tap(find.text(MyGifs.promptAdd));
    await tester.pumpAndSettle();
    expect(myGifsFromViewer(room, event), isNull);
    expect(client.gifs.writes, ['add:gif']);
    client.gifs.fail = true;
    client.gifs.saving!.complete();
    await tester.pumpAndSettle();
    expect(find.text(MyGifs.saveFailed).hitTestable(), findsOneWidget);
    expect(myGifsFromViewer(room, event), isNotNull);
  });
  testWidgets('closing during a save does not use a disposed feedback surface',
      (tester) async {
    final client = ViewerClient();
    client.gifs.saving = Completer<void>();
    await openViewer(tester, ViewerRoom(client), ViewerEvent('gif'));
    await openViewerMenu(tester);
    await tester.tap(find.text(MyGifs.promptAdd));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(Lightbox))).pop();
    await tester.pumpAndSettle();
    client.gifs.saving!.complete();
    await tester.pumpAndSettle();
    expect(client.gifs.saved, {'gif'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'gallery menu follows the displayed event in a feed outside the timeline',
      (tester) async {
    final client = ViewerClient(), room = ViewerRoom(ViewerClient());
    final gif = viewerImage('gif'),
        photo = viewerImage('photo'),
        saved = viewerImage('saved');
    final feed = RoomAttachmentFeed(room)
      ..media.addAll([
        (ViewerEvent('saved', attachments: [saved]), saved),
        (ViewerEvent('photo', gif: false, attachments: [photo]), photo),
        (ViewerEvent('gif', attachments: [gif]), gif),
      ]);
    room.client.gifs.saved.add('saved');
    await preferences.experimentLightboxGallery.set(true);
    addTearDown(() => preferences.experimentLightboxGallery.set(false));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
            body: LightboxGalleryScope.source(
                source: RoomMediaGallerySource(feed, RoomAttachmentFilter.all),
                child: Builder(
                    builder: (context) => TextButton(
                        onPressed: () =>
                            Lightbox.show(context, image: gif.image),
                        child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await openViewerMenu(tester);
    await tester.tap(find.text(MyGifs.promptAdd));
    await tester.pumpAndSettle();
    expect(room.client.gifs.saved, {'gif', 'saved'});
    expect(client.gifs.saved, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await openViewerMenu(tester);
    expect(find.text(MyGifs.promptAdd), findsNothing);
    expect(find.text(MyGifs.promptRemove), findsNothing);
    Navigator.of(tester.element(find.text('Save as…'))).pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await openViewerMenu(tester);
    expect(find.text(MyGifs.promptRemove), findsOneWidget);
    await tester.tap(find.text(MyGifs.promptRemove));
    await tester.pumpAndSettle();
    expect(room.client.gifs.saved, {'gif'});
  });
  testWidgets('long label wraps at large text without losing media actions',
      (tester) async {
    final client = ViewerClient()..gifs.saved.add('gif');
    await openViewer(tester, ViewerRoom(client), ViewerEvent('gif'), scale: 2);
    await openViewerMenu(tester);
    expect(find.text(MyGifs.promptRemove), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
