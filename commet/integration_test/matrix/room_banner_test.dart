// Vommet: room banners (#6) against the test homeserver.
//
// Another client sets a room banner (the shared state event) and the app
// opens the room. The banner must head the side panel, level with the space
// banner, with the room header ending beside it, and WITHOUT breaking the room
// view (the first version asked for an infinite width there, layout threw and
// the whole room went blank). Closing the panel, or removing the banner
// through sync, must bring back the normal layout. Clicking a banner (room or
// space) opens the full image; a space without a banner has no placeholder.
// The app's own setBanner must write the event other clients read.
//
// With VOMMET_IT_SHOTS set, each state is also captured from the X display
// into $OUT (needs ffmpeg), for design review.

import 'dart:convert';
import 'dart:io';

import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/room_header.dart';
import 'package:commet/ui/atoms/space_header.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/molecules/room_banner.dart';
import 'package:commet/ui/molecules/space_sidebar_list.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_actions_bar.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/ui/organisms/room_members_list/room_members_list.dart';
import 'package:commet/ui/organisms/room_pinned_messages/room_pinned_messages_widget.dart';
import 'package:commet/ui/organisms/space_summary/space_summary_view.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

const _bannerType = "page.codeberg.everypizza.room.banner";

const _png =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";

class _Api {
  _Api(this.base);
  final Uri base;
  final HttpClient _http = HttpClient();
  String? token;

  Future<Map<String, dynamic>> call(String method, String path,
      [Object? body]) async {
    var request = await _http.openUrl(method, base.resolve(path));
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.add("Authorization", "Bearer $token");
    if (body != null) request.write(jsonEncode(body));
    var response = await request.close();
    var text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception("$method $path -> ${response.statusCode} $text");
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> login(String user, String password) async {
    var result = await call("POST", "/_matrix/client/v3/login", {
      "type": "m.login.password",
      "identifier": {"type": "m.id.user", "user": user},
      "password": password,
    });
    token = result["access_token"] as String;
  }

  Future<String> uploadPng([List<int>? data]) async {
    var request = await _http.openUrl(
        "POST", base.resolve("/_matrix/media/v3/upload?filename=banner.png"));
    request.headers.contentType = ContentType("image", "png");
    request.headers.add("Authorization", "Bearer $token");
    request.add(data ?? base64Decode(_png));
    var response = await request.close();
    var text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception("upload -> ${response.statusCode} $text");
    }
    return (jsonDecode(text) as Map<String, dynamic>)["content_uri"] as String;
  }

  Future<String> createRoom(String name) async => (await call(
      "POST",
      "/_matrix/client/v3/createRoom",
      {"preset": "private_chat", "name": name}))["room_id"] as String;

  Future<String> createSpace(String name, List<String> children,
          {String? bannerMxc}) async =>
      (await call("POST", "/_matrix/client/v3/createRoom", {
        "preset": "private_chat",
        "name": name,
        "creation_content": {"type": "m.space"},
        "initial_state": [
          for (final child in children)
            {
              "type": "m.space.child",
              "state_key": child,
              "content": {
                "via": [base.host]
              }
            },
          if (bannerMxc != null)
            {
              "type": _bannerType,
              "state_key": "",
              "content": {"url": bannerMxc, "mimetype": "image/png"}
            },
        ],
      }))["room_id"] as String;

  /// Registers [name] on the open test homeserver and joins [room].
  Future<String> registerAndJoin(String name, String room) async {
    final other = _Api(base);
    final r = await other.call("POST", "/_matrix/client/v3/register", {
      "username": name,
      "password": "pw-$name",
      "auth": {"type": "m.login.dummy"},
    });
    other.token = r["access_token"] as String;
    await other.call(
        "POST", "/_matrix/client/v3/join/${Uri.encodeComponent(room)}", {});
    return r["user_id"] as String;
  }

  Future<void> setPowerLevels(String room, Map<String, int> users) async {
    final path = "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}"
        "/state/m.room.power_levels/";
    final pl = await call("GET", path);
    (pl["users"] as Map<String, dynamic>).addAll(users);
    await call("PUT", path, pl);
  }

  Future<String> send(String room, Map<String, Object?> content) async =>
      (await call(
          "PUT",
          "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/send/"
              "m.room.message/t${DateTime.now().microsecondsSinceEpoch}",
          content))["event_id"] as String;

  Future<void> putState(String room, String type, String stateKey,
          Map<String, Object?> content) =>
      call(
          "PUT",
          "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/state/"
              "$type/${Uri.encodeComponent(stateKey)}",
          content);

  String _statePath(String room) =>
      "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/state/$_bannerType/";

  Future<void> setBanner(String room, Map<String, Object?> content) =>
      call("PUT", _statePath(room), content);

  Future<Map<String, dynamic>> getBanner(String room) =>
      call("GET", _statePath(room));
}

Finder get _bannerImage =>
    find.descendant(of: find.byType(RoomBanner), matching: find.byType(Image));

/// Pump for a while so late layout errors surface in takeException.
Future<void> _settle(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump();
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

final _shots = Platform.environment["VOMMET_IT_SHOTS"]?.isNotEmpty == true;
final _out = Platform.environment["OUT"] ?? Directory.systemTemp.path;

/// For screenshots, a banner worth looking at (a wide gradient); otherwise
/// the tiny PNG.
Future<List<int>> _bannerBytes() async {
  if (!_shots) return base64Decode(_png);
  final path = "$_out/banner-source.png";
  for (final source in [
    "gradients=s=1500x500:c0=0x3b1d6e:c1=0xc23b8c:c2=0xf2a65a:n=3",
    "testsrc2=s=1500x500",
  ]) {
    final r = await Process.run("ffmpeg", [
      "-y", "-loglevel", "error", "-f", "lavfi", "-i", source, //
      "-frames:v", "1", path,
    ]);
    if (r.exitCode == 0) return File(path).readAsBytes();
  }
  return base64Decode(_png);
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_shots) return;
  await _settle(tester, const Duration(milliseconds: 1500));
  final r = await Process.run("ffmpeg", [
    "-y", "-loglevel", "error", "-f", "x11grab", "-video_size", "1920x1080", //
    "-i", Platform.environment["DISPLAY"] ?? ":99", "-frames:v", "1",
    "$_out/shot-$name.png",
  ]);
  // ignore: avoid_print
  print("BANNER shot $name exit=${r.exitCode} ${r.stderr}");
}

/// The space view's banner box (upstream's shape: rounded bottom corners).
Finder get _spaceBannerBox => find.descendant(
    of: find.byType(SpaceSummaryView),
    matching: find.byWidgetPredicate((w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).borderRadius ==
            const BorderRadius.only(
                bottomLeft: Radius.circular(15),
                bottomRight: Radius.circular(15))));

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f.first);

/// The banner heads a panel that runs to the top, level with the header.
void _expectBannerColumn(WidgetTester tester) {
  final banner = _rect(tester, find.byType(RoomBanner));
  final header = _rect(tester, find.byType(RoomHeader));
  // ignore: avoid_print
  print("BANNER layout banner=$banner header=$header");
  expect(banner.top, lessThanOrEqualTo(header.top + 1),
      reason: "the banner starts level with the room header");
  expect(header.right, lessThanOrEqualTo(banner.left + 1),
      reason: "the room header ends beside the banner");
  expect(banner.height, 100, reason: "the space banner's height");
}

/// Upstream's layout: the header spans the chat and the panel.
void _expectNormalLayout(WidgetTester tester) {
  expect(_bannerImage, findsNothing);
  final header = _rect(tester, find.byType(RoomHeader));
  final chat = _rect(tester, find.byType(Chat));
  // ignore: avoid_print
  print("BANNER layout header=$header chat=$chat");
  expect(header.right, greaterThan(chat.right),
      reason: "the room header spans the chat and the side panel");
}

Future<void> _openLightbox(WidgetTester tester, Finder target,
    {bool secondary = false}) async {
  if (secondary) {
    await tester.tap(target, buttons: kSecondaryButton);
  } else {
    await tester.tap(target);
  }
  await tester.waitFor(() => find.byType(Lightbox).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10));
  expect(tester.takeException(), isNull);
}

Future<void> _closeLightbox(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(Lightbox))).pop();
  await tester.waitFor(() => find.byType(Lightbox).evaluate().isEmpty,
      timeout: const Duration(seconds: 10));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Room banner: heads the side panel, cleared by sync',
      (WidgetTester tester) async {
    var tag = RandomUtils.getRandomString(6).toLowerCase();

    var api = _Api(Uri.https(tester.homeserver));
    await api.login(tester.username, tester.password);
    var roomId = await api.createRoom("Banner $tag");
    var plainId = await api.createRoom("Plain $tag");
    var mxc = await api.uploadPng(await _bannerBytes());
    await api.setBanner(roomId, {"url": mxc, "mimetype": "image/png"});
    // Enough rooms that the space's room list scrolls under its header.
    // One at a time: parallel createRoom calls race on the test homeserver
    // ("sender's membership `leave` is not `join`").
    var filler = <String>[
      for (var i = 0; i < 24; i++) await api.createRoom("Filler $tag $i"),
    ];
    var spaceId = await api.createSpace(
        "Space $tag", [roomId, plainId, ...filler],
        bannerMxc: mxc);
    var bareSpaceId = await api.createSpace("Bare $tag", [plainId]);

    var app = await tester.setupApp();
    // The collapsing banners, member sections and panes are an experiment.
    await preferences.experimentBannerLayout.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    var client = app.clientManager.clients.first;
    await tester.waitFor(
        () =>
            client.hasRoom(roomId) &&
            client.hasRoom(plainId) &&
            client.hasSpace(spaceId) &&
            client.hasSpace(bareSpaceId),
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true);
    var room = client.getRoom(roomId)!;
    await tester.waitFor(
        () => room.getComponent<RoomBannerComponent>()?.banner != null,
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true);

    final main = tester.state<MainPageState>(find.byType(MainPage));

    // A space with a banner: click opens it full size.
    main.selectSpace(client.getSpace(spaceId));
    await tester
        .waitFor(() => find.byType(SpaceSummaryView).evaluate().isNotEmpty);
    await _shot(tester, "1-space-with-banner");
    await _openLightbox(tester, _spaceBannerBox);
    await _shot(tester, "2-space-banner-lightbox");
    await _closeLightbox(tester);
    // ...and right-click on the sidebar's space header.
    await _openLightbox(tester, find.byType(SpaceHeader), secondary: true);
    await _closeLightbox(tester);
    // The name opens the space menu.
    await tester.tap(find.descendant(
        of: find.byType(SpaceHeader), matching: find.text("Space $tag")));
    await tester.waitFor(
        () => find.text("Space settings").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10));
    expect(find.text("Copy space link"), findsOneWidget);
    expect(find.text("Leave space"), findsOneWidget);
    // Says what it invites to, so it isn't confused with the room's.
    expect(find.text("Invite people to space"), findsOneWidget);
    expect(find.text("View space banner"), findsOneWidget);
    // The menu opens under the header, inside the sidebar.
    final menuItem = _rect(tester, find.text("Space settings"));
    final header = _rect(tester, find.byType(SpaceHeader));
    expect(menuItem.right, lessThanOrEqualTo(header.right));
    expect(menuItem.top, greaterThanOrEqualTo(header.bottom));
    await _shot(tester, "1b-space-menu");
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.waitFor(() => find.text("Space settings").evaluate().isEmpty,
        timeout: const Duration(seconds: 10));

    // Scrolling the room list collapses the banner to the plain row, which
    // stays at the top with the name, its menu and the invite icon.
    final roomList = find.descendant(
        of: find.byType(SpaceSidebarList), matching: find.byType(Scrollable));
    // A touch drag: desktop lists don't scroll on mouse drags.
    await tester.drag(roomList.first, const Offset(0, -300));
    await _settle(tester, const Duration(milliseconds: 600));
    final collapsed = _rect(tester, find.byType(SpaceHeader));
    // ignore: avoid_print
    print("BANNER space header after scrolling: $collapsed");
    expect(collapsed.height, closeTo(SpaceHeader.compactHeight, 1));
    expect(collapsed.top, closeTo(0, 1));
    expect(
        find.descendant(
            of: find.byType(SpaceHeader), matching: find.byType(Opacity)),
        findsNothing,
        reason: "the banner image has faded out completely");
    await _shot(tester, "1c-space-list-scrolled");
    await tester.tap(find.descendant(
        of: find.byType(SpaceHeader), matching: find.text("Space $tag")));
    await tester.waitFor(
        () => find.text("Space settings").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.waitFor(() => find.text("Space settings").evaluate().isEmpty,
        timeout: const Duration(seconds: 10));
    await tester.drag(roomList.first, const Offset(0, 600));
    await _settle(tester, const Duration(milliseconds: 600));

    // The room with a banner, panel open.
    EventBus.doOpenRoom(roomId, clientId: client.identifier);
    await tester.waitFor(() => _bannerImage.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    await _settle(tester, const Duration(seconds: 2));

    // The regression: a layout error here blanks the chat beside the panel.
    expect(tester.takeException(), isNull);
    expect(find.byType(Chat), findsOneWidget);
    expect(find.byType(RoomMembersListWidget), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(RoomBanner), matching: find.text("Banner $tag")),
        findsOneWidget);
    _expectBannerColumn(tester);
    // Symmetry: the room banner is as wide as the space banner opposite.
    expect(_rect(tester, find.byType(RoomBanner)).width,
        closeTo(_rect(tester, find.byType(SpaceHeader)).width, 1));
    await _shot(tester, "3-room-banner-panel-open");

    // The member pane resizes by dragging its edge and resets on double-click.
    final handles = find.byType(PaneResizeHandle);
    expect(handles, findsNWidgets(2), reason: "left and right pane edges");
    final rightHandle = handles.last;
    final before = _rect(tester, find.byType(RoomBanner)).width;
    await tester.drag(rightHandle, const Offset(-80, 0),
        kind: PointerDeviceKind.mouse);
    await _settle(tester, const Duration(milliseconds: 500));
    expect(
        _rect(tester, find.byType(RoomBanner)).width, greaterThan(before + 50),
        reason: "dragging left widens the panel (less the drag slop)");
    _expectBannerColumn(tester);
    await _shot(tester, "3b-room-pane-widened");
    await tester.tap(rightHandle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(rightHandle);
    await _settle(tester, const Duration(milliseconds: 800));
    expect(_rect(tester, find.byType(RoomBanner)).width, closeTo(before, 1),
        reason: "double-click resets the width");
    expect(PaneWidths.right.value, PaneWidths.right.defaultValue);

    await _openLightbox(tester, find.byType(RoomBanner));
    await _shot(tester, "4-room-banner-lightbox");
    await _closeLightbox(tester);

    // Closing the panel restores the normal layout; reopening brings it back.
    EventBus.toggleRoomSidePanel.add(null);
    await tester.waitFor(() => find.byType(RoomBanner).evaluate().isEmpty,
        timeout: const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
    _expectNormalLayout(tester);
    await _shot(tester, "5-room-banner-panel-closed");
    EventBus.toggleRoomSidePanel.add(null);
    await tester.waitFor(() => _bannerImage.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10));
    _expectBannerColumn(tester);

    // A room without a banner: upstream's layout, no gap.
    EventBus.doOpenRoom(plainId, clientId: client.identifier);
    await tester.waitFor(
        () =>
            find.byType(RoomMembersListWidget).evaluate().isNotEmpty &&
            _bannerImage.evaluate().isEmpty,
        timeout: const Duration(seconds: 20));
    await _settle(tester, const Duration(seconds: 1));
    _expectNormalLayout(tester);
    await _shot(tester, "6-room-without-banner");

    // Another client removes the banner: sync must clear it.
    EventBus.doOpenRoom(roomId, clientId: client.identifier);
    await tester.waitFor(() => _bannerImage.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    await api.setBanner(roomId, {});
    await tester.waitFor(() => _bannerImage.evaluate().isEmpty,
        timeout: const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
    expect(find.byType(Chat), findsOneWidget);
    _expectNormalLayout(tester);

    // A space without a banner: no placeholder box.
    main.selectSpace(client.getSpace(bareSpaceId));
    await tester
        .waitFor(() => find.byType(SpaceSummaryView).evaluate().isNotEmpty);
    expect(_spaceBannerBox, findsNothing,
        reason: "no banner box when the space has no banner");
    await _shot(tester, "7-space-without-banner");

    await _settle(tester, const Duration(seconds: 3));
  });

  // The settings page hands the cropped image to setBanner; the native file
  // picker in front of it can't be driven under Xvfb, so this calls the
  // component directly and checks what other clients would read.
  testWidgets('Room banner: setBanner writes the shared state event',
      (WidgetTester tester) async {
    var tag = RandomUtils.getRandomString(6).toLowerCase();

    var api = _Api(Uri.https(tester.homeserver));
    await api.login(tester.username, tester.password);
    var roomId = await api.createRoom("Banner set $tag");

    var app = await tester.setupApp();
    // The collapsing banners, member sections and panes are an experiment.
    await preferences.experimentBannerLayout.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    var client = app.clientManager.clients.first;
    await tester.waitFor(() => client.hasRoom(roomId),
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    var banners = client.getRoom(roomId)!.getComponent<RoomBannerComponent>()!;
    expect(banners.canEditBanner, isTrue, reason: "the room's creator");

    EventBus.doOpenRoom(roomId, clientId: client.identifier);
    await _settle(tester, const Duration(seconds: 1));
    expect(_bannerImage, findsNothing);

    await banners.setBanner(Uint8List.fromList(base64Decode(_png)),
        mimeType: "image/png");

    var content = await api.getBanner(roomId);
    expect(content["url"], startsWith("mxc://"));
    expect(content["mimetype"], "image/png");

    await tester.waitFor(() => _bannerImage.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    expect(tester.takeException(), isNull);
    expect(find.byType(Chat), findsOneWidget);

    await banners.removeBanner();
    expect(await api.getBanner(roomId), isEmpty);
    await tester.waitFor(() => _bannerImage.evaluate().isEmpty,
        timeout: const Duration(seconds: 20));

    await _settle(tester, const Duration(seconds: 3));
  });

  // Operator report (10-07): scrolling a big room's member list left it
  // blank. Scroll a 150-member list with and without a banner and require
  // members on screen and no framework error after every step.
  testWidgets('Room banner: a long member list still scrolls',
      (WidgetTester tester) async {
    var tag = RandomUtils.getRandomString(6).toLowerCase();

    var api = _Api(Uri.https(tester.homeserver));
    await api.login(tester.username, tester.password);
    var roomId = (await api.call("POST", "/_matrix/client/v3/createRoom",
        {"preset": "public_chat", "name": "Crowd $tag"}))["room_id"] as String;
    var mxc = await api.uploadPng(await _bannerBytes());
    await api.setBanner(roomId, {"url": mxc, "mimetype": "image/png"});

    var members = <String>[];
    for (var batch = 0; batch < 15; batch++) {
      members.addAll(await Future.wait([
        for (var i = 0; i < 10; i++)
          api.registerAndJoin("crowd${tag}_${batch * 10 + i}", roomId)
      ]));
    }
    // Some roles, so the list has role headers like a real room.
    await api.setPowerLevels(roomId, {
      members[0]: 100,
      members[1]: 50,
      members[2]: 50,
      members[3]: 10,
    });

    var app = await tester.setupApp();
    // The collapsing banners, member sections and panes are an experiment.
    await preferences.experimentBannerLayout.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    var client = app.clientManager.clients.first;
    await tester.waitFor(() => client.hasRoom(roomId),
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);

    Finder panels() => find.descendant(
        of: find.byType(RoomMembersListWidget),
        matching: find.byType(UserPanel));
    final list = find.descendant(
        of: find.byType(RoomMembersListWidget),
        matching: find.byType(Scrollable));

    Future<void> scrollThrough(String label) async {
      await tester.waitFor(() => panels().evaluate().length > 5,
          timeout: const Duration(seconds: 30));
      // Discord-style section headers ("Owner — 2", "Members — 147", ...).
      final headers = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(RoomMembersListWidget),
              matching: find.textContaining(" — ")))
          .map((t) => t.data)
          .toList();
      // ignore: avoid_print
      print("BANNER crowd $label sections: $headers");
      expect(headers, isNotEmpty, reason: "the list has section headers");
      await _shot(tester, "crowd-$label-top");
      final seen = <String>{
        ...tester.widgetList<UserPanel>(panels()).map((p) => p.userId)
      };
      // Section sizes as the headers show them (the latest seen for each).
      final counts = <String, int>{};
      void readCounts() {
        for (final t in tester.widgetList<Text>(find.descendant(
            of: find.byType(RoomMembersListWidget),
            matching: find.textContaining(" — ")))) {
          final parts = t.data!.split(" — ");
          counts[parts.first] = int.parse(parts.last);
        }
      }

      readCounts();
      for (var step = 0; step < 30; step++) {
        await tester.drag(list.first, const Offset(0, -400));
        await _settle(tester, const Duration(milliseconds: 600));
        final shown = panels().evaluate().length;
        // ignore: avoid_print
        print("BANNER crowd $label step $step: $shown member rows built");
        expect(tester.takeException(), isNull, reason: "$label step $step");
        expect(shown, greaterThan(0),
            reason: "$label: member list went blank at step $step");
        seen.addAll(
            tester.widgetList<UserPanel>(panels()).map((p) => p.userId));
        readCounts();
      }
      // Every member is in a section: the headers count them all, whatever is
      // loaded. (Presence changes while the test scrolls, so members move
      // between Online and Offline and a viewport sample can miss some.)
      final room = client.getRoom(roomId)!;
      // ignore: avoid_print
      print("BANNER crowd $label: ${seen.length} distinct rows seen; "
          "sections $counts; membersList "
          "${room.membersList().length}");
      // Auto-loading: rows past the first batch of 100 got built.
      expect(seen.length, greaterThan(100),
          reason: "$label: the list should load more members as it scrolls");
      expect(counts.values.fold(0, (a, b) => a + b), greaterThanOrEqualTo(151),
          reason: "$label: every member (150 + alice) is in a section");
      if (label == "banner") {
        // The banner collapsed to the compact bar and stayed at the top.
        final banner = _rect(tester, find.byType(RoomBanner));
        // ignore: avoid_print
        print("BANNER crowd collapsed banner=$banner");
        expect(banner.height, closeTo(RoomBannerView.compactHeight, 1));
        expect(banner.top, closeTo(0, 1));
        // The room's name and menu stay usable in the collapsed bar.
        await tester.tap(find.descendant(
            of: find.byType(RoomBanner), matching: find.text("Crowd $tag")));
        await tester.waitFor(
            () => find.text("Room settings").evaluate().isNotEmpty,
            timeout: const Duration(seconds: 10));
        expect(find.text("Copy room link"), findsOneWidget);
        expect(find.text("Invite people to room"), findsOneWidget);
        expect(find.text("View room banner"), findsOneWidget);
        // The menu opens under the banner, inside its column.
        final item = _rect(tester, find.text("Room settings"));
        final bar = _rect(tester, find.byType(RoomBanner));
        expect(item.left, greaterThanOrEqualTo(bar.left));
        expect(item.top, greaterThanOrEqualTo(bar.bottom));
        await _shot(tester, "crowd-room-menu");
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.waitFor(
            () => find.text("Room settings").evaluate().isEmpty,
            timeout: const Duration(seconds: 10));
      }
      await _shot(tester, "crowd-$label-scrolled");
      for (var step = 0; step < 30; step++) {
        await tester.drag(list.first, const Offset(0, 400));
        await _settle(tester, const Duration(milliseconds: 300));
      }
    }

    EventBus.doOpenRoom(roomId, clientId: client.identifier);
    await tester.waitFor(() => _bannerImage.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    // Sync loads members lazily; opening the panel fetches the rest. Wait for
    // the full list before counting sections.
    await tester.waitFor(
        () => client.getRoom(roomId)!.membersList().length >= 151,
        timeout: const Duration(seconds: 60));
    await _settle(tester, const Duration(seconds: 2));
    await scrollThrough("banner");

    await api.setBanner(roomId, {});
    await tester.waitFor(() => _bannerImage.evaluate().isEmpty,
        timeout: const Duration(seconds: 30));
    await scrollThrough("plain");

    // Leave the room and let the 150 rows' presence lookups finish, so none
    // reaches the database after teardown closes it.
    tester.state<MainPageState>(find.byType(MainPage)).selectHome();
    await _settle(tester, const Duration(seconds: 8));
  });

  // Design review only (no layout assertions yet): the same banners in the
  // phone layout, 400 x 700, with both drawers open.
  testWidgets('Room banner: phone layout screenshots',
      (WidgetTester tester) async {
    var tag = RandomUtils.getRandomString(6).toLowerCase();

    var api = _Api(Uri.https(tester.homeserver));
    await api.login(tester.username, tester.password);
    var roomId = (await api.call("POST", "/_matrix/client/v3/createRoom",
        {"preset": "public_chat", "name": "Phone $tag"}))["room_id"] as String;
    var mxc = await api.uploadPng(await _bannerBytes());
    await api.setBanner(roomId, {"url": mxc, "mimetype": "image/png"});
    var spaceId = await api.createSpace("Space $tag", [roomId], bannerMxc: mxc);
    var bareId = await api.createSpace("Bare $tag", [roomId]);
    for (var batch = 0; batch < 4; batch++) {
      await Future.wait([
        for (var i = 0; i < 10; i++)
          api.registerAndJoin("phone${tag}_${batch * 10 + i}", roomId)
      ]);
    }

    var app = await tester.setupApp();
    // The collapsing banners, member sections and panes are an experiment.
    await preferences.experimentBannerLayout.set(true);
    await preferences.layoutOverride.set("mobile");
    // Resize the real window: overriding tester.view only draws offscreen.
    final desktopSize = await windowManager.getSize();
    await windowManager.setSize(const Size(400, 700));
    // Restored in the test body below; this only covers a failure.
    addTearDown(() => windowManager.setSize(desktopSize));
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    var client = app.clientManager.clients.first;
    await tester.waitFor(
        () =>
            client.hasRoom(roomId) &&
            client.hasSpace(spaceId) &&
            client.hasSpace(bareId),
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true);
    await tester.waitFor(
        () =>
            client
                .getRoom(roomId)!
                .getComponent<RoomBannerComponent>()
                ?.banner !=
            null,
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true);

    final main = tester.state<MainPageState>(find.byType(MainPage));
    OverlappingPanelsState panels() =>
        tester.state<OverlappingPanelsState>(find.byType(OverlappingPanels));

    main.selectSpace(client.getSpace(spaceId));
    await _settle(tester, const Duration(seconds: 2));
    await _shot(tester, "phone-1-space-with-banner");
    panels().reveal(RevealSide.left);
    await _shot(tester, "phone-2-space-list");
    final spaceName = find.descendant(
        of: find.byType(SpaceHeader), matching: find.text("Space $tag"));
    await tester.waitFor(() => spaceName.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    await tester.tap(spaceName);
    await tester.waitFor(
        () => find.text("Space settings").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10));
    await _shot(tester, "phone-2b-space-menu");
    Navigator.of(tester.element(find.text("Space settings"))).pop();
    await _settle(tester, const Duration(seconds: 1));

    EventBus.doOpenRoom(roomId, clientId: client.identifier);
    await _settle(tester, const Duration(seconds: 2));
    panels().reveal(RevealSide.right);
    await tester.waitFor(() => _bannerImage.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    expect(tester.takeException(), isNull);
    await _shot(tester, "phone-3-member-drawer");
    // Scrolled: the banner goes, the room actions pin to the top.
    final memberList = find.descendant(
        of: find.byType(RoomMembersListWidget),
        matching: find.byType(Scrollable));
    for (var i = 0; i < 3; i++) {
      await tester.drag(memberList.first, const Offset(0, -300));
      await _settle(tester, const Duration(milliseconds: 500));
    }
    // One pinned row: the banner has slid away under the actions row, and
    // the room's name with its menu has faded into the row's left side.
    final bar = _rect(tester, find.byType(RoomActionsBar));
    // ignore: avoid_print
    print("BANNER phone after scrolling: actions bar=$bar");
    expect(bar.top, lessThan(10),
        reason: "the actions row is pinned at the top");
    expect(find.byType(RoomBanner), findsNothing,
        reason: "the banner has scrolled away");
    expect(
        find.descendant(
            of: find.byType(RoomActionsBar), matching: find.text("Phone $tag")),
        findsOneWidget,
        reason: "the room's name is in the row");
    expect(tester.takeException(), isNull);
    await _shot(tester, "phone-3b-member-drawer-scrolled");

    main.selectSpace(client.getSpace(bareId));
    main.clearRoomSelection();
    await _settle(tester, const Duration(seconds: 2));
    panels().reveal(RevealSide.main);
    await _shot(tester, "phone-4-space-without-banner");
    panels().reveal(RevealSide.left);
    await _shot(tester, "phone-5-bare-space-list");
    expect(tester.takeException(), isNull);

    // Back to the desktop layout here, not in teardown: switching layouts
    // while the drawers animate disposes them mid-animation.
    panels().reveal(RevealSide.main);
    await _settle(tester, const Duration(seconds: 2));
    await preferences.layoutOverride.set(null);
    await windowManager.setSize(desktopSize);
    await _settle(tester, const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  // With the experiment off (the default): no drag handles, and the banner
  // keeps its full height while the member list scrolls.
  testWidgets('Room banner: layout experiment off',
      (WidgetTester tester) async {
    var tag = RandomUtils.getRandomString(6).toLowerCase();

    var api = _Api(Uri.https(tester.homeserver));
    await api.login(tester.username, tester.password);
    var roomId = (await api.call("POST", "/_matrix/client/v3/createRoom", {
      "preset": "public_chat",
      "name": "Plainlayout $tag"
    }))["room_id"] as String;
    var mxc = await api.uploadPng(await _bannerBytes());
    await api.setBanner(roomId, {"url": mxc, "mimetype": "image/png"});
    for (var batch = 0; batch < 3; batch++) {
      await Future.wait([
        for (var i = 0; i < 10; i++)
          api.registerAndJoin("off${tag}_${batch * 10 + i}", roomId)
      ]);
    }

    var app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();
    expect(preferences.experimentBannerLayout.value, isFalse);

    var client = app.clientManager.clients.first;
    await tester.waitFor(() => client.hasRoom(roomId),
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    EventBus.doOpenRoom(roomId, clientId: client.identifier);
    await tester.waitFor(() => _bannerImage.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    await _settle(tester, const Duration(seconds: 2));

    expect(find.byType(PaneResizeHandle), findsNothing);
    final list = find.descendant(
        of: find.byType(RoomMembersListWidget),
        matching: find.byType(Scrollable));
    for (var i = 0; i < 3; i++) {
      await tester.drag(list.first, const Offset(0, -300));
      await _settle(tester, const Duration(milliseconds: 500));
    }
    final banner = _rect(tester, find.byType(RoomBanner));
    // ignore: avoid_print
    print("BANNER experiment off, banner after scrolling: $banner");
    expect(banner.height, closeTo(RoomBannerView.fullHeight, 1));
    expect(tester.takeException(), isNull);
    await _shot(tester, "experiment-off-scrolled");

    await _settle(tester, const Duration(seconds: 3));
  });

  // The member panel's tabs (with the experiment): Media shows the room's
  // pictures, Files its other attachments, Pins the pinned messages; and a
  // member in the room's call shows "In voice".
  testWidgets('Member panel: tabs and In voice', (WidgetTester tester) async {
    var tag = RandomUtils.getRandomString(6).toLowerCase();

    var api = _Api(Uri.https(tester.homeserver));
    await api.login(tester.username, tester.password);
    var roomId = (await api.call("POST", "/_matrix/client/v3/createRoom", {
      "preset": "private_chat",
      "name": "Voice $tag",
      "creation_content": {"type": "org.matrix.msc3417.call"},
    }))["room_id"] as String;
    for (var n = 1; n <= 2; n++) {
      final url = await api.uploadPng();
      await api.send(roomId, {
        "msgtype": "m.image",
        "body": "picture_$n.png",
        "url": url,
        "info": {"mimetype": "image/png", "size": 70, "w": 1, "h": 1},
      });
    }
    final fileUrl = await api.uploadPng();
    await api.send(roomId, {
      "msgtype": "m.file",
      "body": "notes_$tag.txt",
      "filename": "notes_$tag.txt",
      "url": fileUrl,
      "info": {"mimetype": "text/plain", "size": 1234},
    });
    final me = "@${tester.username}:localhost";
    await api
        .putState(roomId, "org.matrix.msc3401.call.member", "_${me}_ITDEVICE", {
      "application": "m.call",
      "call_id": "",
      "scope": "m.room",
      "device_id": "ITDEVICE",
      "expires": 3600000,
      "focus_active": {
        "type": "livekit",
        "focus_selection": "oldest_membership"
      },
      "foci_preferred": [
        {"type": "livekit", "livekit_service_url": "https://localhost/lk"}
      ],
    });

    var app = await tester.setupApp();
    await preferences.experimentBannerLayout.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    var client = app.clientManager.clients.first;
    await tester.waitFor(() => client.hasRoom(roomId),
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    // Open it as a text chat, so the member panel shows beside it.
    EventBus.doOpenRoom(roomId,
        clientId: client.identifier, bypassSpecialRoomType: true);
    await tester.waitFor(
        () => find
            .byKey(const ValueKey("member-panel-tab-media"))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 20));
    await _settle(tester, const Duration(seconds: 2));

    await tester.waitFor(() => find.text("In voice").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    await _shot(tester, "tabs-1-members-in-voice");

    await tester.tap(find.byKey(const ValueKey("member-panel-tab-media")));
    await tester.waitFor(
        () =>
            find
                .descendant(
                    of: find.byType(RoomMediaGrid),
                    matching: find.byType(Image))
                .evaluate()
                .length >=
            2,
        timeout: const Duration(seconds: 30));
    await _settle(tester, const Duration(seconds: 2));
    await _shot(tester, "tabs-2-media");

    await tester.tap(find.byKey(const ValueKey("member-panel-tab-files")));
    await tester.waitFor(
        () => find.text("notes_$tag.txt").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
    await _shot(tester, "tabs-3-files");

    await tester.tap(find.byKey(const ValueKey("member-panel-tab-pins")));
    await tester.waitFor(
        () => find.byType(RoomPinnedMessagesWidget).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    await _settle(tester, const Duration(seconds: 1));
    await _shot(tester, "tabs-4-pins");

    await tester.tap(find.byKey(const ValueKey("member-panel-tab-members")));
    await tester.waitFor(() => find.text("In voice").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10));
    expect(tester.takeException(), isNull);

    await _settle(tester, const Duration(seconds: 3));
  });
}
