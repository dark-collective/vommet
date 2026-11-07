// Vommet issue 1144: real Overview and SDK requests against a stub server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/components/threads/thread_follows.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_main.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'new_home_overview_lazy_test.dart' show showCards;
import 'roomlist_fixture.dart';

const _type = "followed_threads";
const _capture = ValueKey("followed-threads-capture");

Map<String, Object?> _root(String account, String id, {required bool unread}) =>
    {
      "event_id": id,
      "type": "m.room.message",
      "sender": "@mina:example.com",
      "origin_server_ts": 1700000000000,
      "content": {
        "msgtype": "m.text",
        "body": unread
            ? "$account release checklist · ${id.split('!').last.split(':').first}"
            : "$account project notes",
      },
      "unsigned": <String, Object?>{
        "m.relations": {
          "m.thread": {
            "count": 2,
            "current_user_participated": true,
            "latest_event": {
              "event_id": r"$reply-" + id,
              "type": "m.room.message",
              "sender": unread ? "@mina:example.com" : me,
              "origin_server_ts": unread ? 1700000000200 : 1700000000100,
              "content": {
                "msgtype": "m.text",
                "body":
                    "The Linux build is green. I’ll check the installer next.",
              },
            },
          },
        },
      },
    };

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {"content-type": "application/json"});

Future<void> _loadCaptureFonts() async {
  if (Platform.environment["VOMMET_1144_CAPTURES"] == null) return;
  final flutter = Platform.environment["FLUTTER_ROOT"];
  for (final (family, path) in [
    ("RobotoCustom", "assets/font/roboto/Roboto-Regular.ttf"),
    (
      "NunitoSans",
      "assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf"
    ),
    if (flutter != null)
      (
        "MaterialIcons",
        "$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf"
      ),
  ]) {
    final loader = FontLoader(family)
      ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}

Future<void> _saveCapture(WidgetTester tester, String name) async {
  final directory = Platform.environment["VOMMET_1144_CAPTURES"];
  if (directory == null) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_capture));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File("$directory/$name.png").writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final requests = <Uri>[];
  final profileRequests = <Uri>[];
  var failPages = false;
  var failureStatus = 500;
  var failUnfollow = false;
  List<Map<String, Object?>> Function(String)? pageRoots;
  Completer<void>? stalledPages;
  late MatrixClient work;
  late MatrixClient personal;
  late ClientManager manager;

  setUpAll(() async {
    await _loadCaptureFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    work = await signedInClient("Work", respond: (request) async {
      final parts = request.url.pathSegments;
      if (parts.last == "threads") {
        requests.add(request.url);
        if (stalledPages case final stall?) await stall.future;
        if (failPages)
          return _json({
            "errcode": failureStatus == 429 ? "M_LIMIT_EXCEEDED" : "M_UNKNOWN",
            "retry_after_ms": 30000,
          }, status: failureStatus);
        final room = parts[parts.length - 2];
        return _json({
          "chunk": pageRoots?.call(room) ??
              [
                _root("Work", r"$unread-" + room, unread: true),
                _root("Work", r"$read-" + room, unread: false),
              ],
          "next_batch": "more",
        });
      }
      if (parts.length > 2 && parts[parts.length - 2] == "event") {
        requests.add(request.url);
        return _json(_root("Work", parts.last, unread: false));
      }
      if (failUnfollow && parts.last == ThreadFollows.type) {
        return _json({"errcode": "M_FORBIDDEN"}, status: 403);
      }
      if (parts.contains("profile") || parts.contains("m.room.member")) {
        profileRequests.add(request.url);
      }
      return null;
    });
    personal = await signedInClient("Personal",
        respond: (request) => request.url.path.endsWith("/threads")
            ? _json({"chunk": []})
            : null);
    for (final client in [work, personal]) {
      client.self = MatrixProfile(client, matrix.Profile(userId: me));
    }
    await sync(work, join: {
      for (var i = 0; i < 9; i++)
        "!room$i:example.com": joined("!room$i:example.com", name: "Project $i")
          ..state?.addAll([
            if (i != 3)
              stateEvent("m.room.member",
                  {"membership": "join", "displayname": "Mina"},
                  stateKey: "@mina:example.com"),
          ])
          ..accountData = [
            matrix.BasicEvent(type: ThreadFollows.type, content: {
              "threads": {
                for (var j = 0; j < 2; j++)
                  r"$extra-" "$i-$j": {"follow": true, "ts": i * 2 + j},
              },
            }),
          ],
    });
    await sync(personal, join: {
      "!room0:example.com": joined("!room0:example.com", name: "Personal room")
    });
    manager = ClientManager();
    manager.clients.addAll([work, personal]);
  });

  setUp(() {
    failPages = failUnfollow = false;
    failureStatus = 500;
    pageRoots = null;
  });

  tearDownAll(() async {
    await work.matrixClient.dispose(closeDatabase: true);
    await personal.matrixClient.dispose(closeDatabase: true);
  });

  // The SDK was initialized outside the widget's fake clock. Let its stub
  // transport drain without advancing the card's eight-second deadline.
  Future<void> settlePreview(WidgetTester tester) async {
    for (var i = 0;
        i < 40 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpHome(WidgetTester tester, MatrixClient? account,
      {required bool phone, bool settle = true}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: RepaintBoundary(
        key: _capture,
        child: Scaffold(
          body: Column(children: [
            NewHomeHeader(tab: HomeLayoutStore.instance.current, phone: phone),
            Expanded(
              child: NewHomeOverview(
                clientManager: manager,
                filterClient: account,
                phone: phone,
              ),
            ),
          ]),
        ),
      ),
    ));
    if (settle) await settlePreview(tester);
  }

  test("Followed threads is opt-in and saves its row limit", () {
    expect(HomeLayout.defaults.visible.map((card) => card.type),
        isNot(contains(_type)));
    expect(CardInfo.cards.map((card) => card.type), contains(_type));
    final card = HomeCard(_type, count: 9);
    expect(HomeCard.fromJson(card.toJson())?.count, 9);
    expect(HomeCard.fromJson(card.toJson())?.configurable, isTrue);
  });

  testWidgets("size dialog cannot save to a switched Home account",
      (tester) async {
    final store = HomeLayoutStore.instance;
    store.attach(manager);
    showCards([_type]);
    personal.matrixClient.accountData[HomeLayout.accountDataKey] =
        matrix.BasicEvent(
            type: HomeLayout.accountDataKey,
            content: store.tabs.value.toJson());
    final original = store.layout.value.card(_type);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () => editCardSettings(context, manager, original),
          child: const Text("Edit size")),
    ))));
    await tester.tap(find.text("Edit size"));
    await tester.pumpAndSettle();
    expect(find.text("Threads to show"), findsOneWidget);
    addTearDown(() {
      if (!manager.clients.contains(work)) manager.clients.add(work);
      manager.clients.remove(personal);
      manager.clients.add(personal);
      store.attach(manager);
    });
    manager.clients.remove(work);
    store.attach(manager);
    expect(store.account.value, same(personal));
    await tester.tap(find.text("9"));
    await tester.pumpAndSettle();
    expect(store.layout.value.card(_type).count, 5);
  });

  testWidgets("size controls save 3 and 9 and clear the default",
      (tester) async {
    final store = HomeLayoutStore.instance;
    showCards([_type]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () => editCardSettings(
              context, manager, store.layout.value.card(_type)),
          child: const Text("Edit size")),
    ))));
    for (final count in [3, 9, 5]) {
      await tester.tap(find.text("Edit size"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("$count"));
      await tester.pumpAndSettle();
      final card = store.layout.value.card(_type);
      expect(card.count, count);
      expect(card.toJson().containsKey("count"), count != 5);
    }
    store.layout.value =
        store.layout.value.replace(const HomeCard(_type, count: 100));
    await tester.tap(find.text("Edit size"));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.widgetWithText(Row, "5"),
            matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget);
    await tester.tap(find.text("5"));
    await tester.pumpAndSettle();
  });

  for (final style in LayoutStyle.values) {
    final phone = style != LayoutStyle.discord;
    testWidgets("bounded preview opens, filters and isolates accounts ($style)",
        (tester) async {
      await pickLayoutStyle(style);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize =
          phone ? const Size(360, 840) : const Size(1050, 840);
      addTearDown(tester.view.reset);
      showCards([_type, HomeLayout.invites]);
      requests.clear();
      profileRequests.clear();
      await pumpHome(tester, work, phone: phone);
      if (style != LayoutStyle.custom) {
        await _saveCapture(tester, phone ? "phone" : "desktop");
      }
      expect(find.text("Followed threads"), findsOneWidget);
      expect(requests, hasLength(12));
      expect(profileRequests, isEmpty);
      expect(find.textContaining("Work release checklist"), findsNWidgets(5),
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .whereType<String>()
              .join(" / "));
      final pages = requests.where((uri) => uri.path.endsWith("/threads"));
      expect(pages, hasLength(6));
      expect(
          pages.every((uri) =>
              uri.queryParameters["include"] == "participated" &&
              uri.queryParameters["limit"] == "10" &&
              !uri.queryParameters.containsKey("from")),
          isTrue);
      final open = EventBus.openRoom.stream.first;
      await tester.tap(find.textContaining("Work release checklist").first);
      await tester.pumpAndSettle();
      final opened = await open;
      expect(opened.clientId, work.identifier);
      expect(opened.threadId, r"$unread-" + opened.roomId);

      final filter = find.widgetWithText(ChoiceChip, "Unread");
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(requests, hasLength(12));
      expect(find.textContaining("Work release checklist"), findsNWidgets(5));

      failPages = true;
      await tester.tap(find.byTooltip("Refresh followed threads"));
      await tester.pump();
      await settlePreview(tester);
      expect(find.textContaining("couldn’t be checked"), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, "All"));
      await tester.pumpAndSettle();
      expect(find.text("Work project notes"), findsNWidgets(5));
      failPages = false;

      requests.clear();
      stalledPages = Completer<void>();
      await tester.tap(find.byTooltip("Refresh followed threads"));
      await tester.pump();
      expect(requests, hasLength(2));
      await pumpHome(tester, personal, phone: phone, settle: false);
      expect(find.textContaining("Work "), findsNothing);
      stalledPages!.complete();
      stalledPages = null;
      await settlePreview(tester);
      expect(requests, hasLength(2));
      expect(find.textContaining("Work "), findsNothing);
      expect(find.text("No followed activity found in recent rooms."),
          findsOneWidget);
      await pumpHome(tester, null, phone: phone);
      expect(find.text("Select an account to see followed threads."),
          findsOneWidget);

      if (style == LayoutStyle.custom) {
        await pumpHome(tester, work, phone: phone);
        final topic = tester
            .widget<Text>(
              find.textContaining("Work release checklist").first,
            )
            .data;
        failUnfollow = true;
        await tester.tap(find.byTooltip("Thread actions").first);
        await tester.pumpAndSettle();
        await tester.tap(find.text("Unfollow thread"));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(find.text("Couldn’t unfollow this thread."), findsOneWidget);
        expect(find.text(topic!), findsOneWidget);
        failUnfollow = false;
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.byTooltip("Thread actions").first);
        await tester.pumpAndSettle();
        await tester.tap(find.text("Unfollow thread"));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(find.text(topic), findsNothing);
      }
    });
  }
  // Vommet issue 982: the downstream Home card is also a summary consumer.
  testWidgets(
      "Home reports events without presenting control activity as a reply",
      (tester) async {
    final followed = {
      for (final r in work.matrixClient.rooms)
        r.id: r.roomAccountData[ThreadFollows.type]
    };
    for (final r in work.matrixClient.rooms) {
      r.roomAccountData.remove(ThreadFollows.type);
    }
    addTearDown(() {
      for (final r in work.matrixClient.rooms) {
        if (followed[r.id] case final entry?)
          r.roomAccountData[ThreadFollows.type] = entry;
      }
    });
    final counts = <int>[];
    final missing = <int>[];
    final unknown = <int>[];
    for (final phone in [true, false]) {
      await pickLayoutStyle(phone ? LayoutStyle.telegram : LayoutStyle.discord);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize =
          phone ? const Size(360, 780) : const Size(1280, 800);
      addTearDown(tester.view.reset);
      final root = _root("Work", r"$home-zooid", unread: false);
      final info =
          ((root["unsigned"] as Map)["m.relations"] as Map)["m.thread"] as Map;
      info["count"] = 6;
      final latest = info["latest_event"] as Map;
      latest["type"] = "dev.zooid.turn.end";
      latest["content"] = {
        "session_id": "s",
        "produced_output": false,
        "m.relates_to": {"rel_type": "m.thread", "event_id": root["event_id"]}
      };
      pageRoots = (id) => id == "!room8:example.com" ? [root] : [];
      showCards([_type, HomeLayout.invites]);
      await pumpHome(tester, work, phone: phone);
      await _saveCapture(tester, phone ? "982-home-phone" : "982-home-desktop");
      counts.add(find.text("6 events reported").evaluate().length);
      missing.add(
          find.text("No reply preview in loaded activity").evaluate().length);
      expect(find.textContaining("Finished (turn ended)"), findsNothing);
      info.remove("count");
      await tester.tap(find.byTooltip("Refresh followed threads"));
      await tester.pump();
      await settlePreview(tester);
      unknown.add(find.text("Thread activity").evaluate().length);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    expect(counts, [1, 1]);
    expect(missing, [1, 1]);
    expect(unknown, [1, 1]);
  });

  testWidgets(
      "empty, rate-limited, stale and unavailable previews stay bounded",
      (tester) async {
    const roomId = "!room8:example.com";
    final before = {
      for (final r in work.matrixClient.rooms)
        r.id: r.roomAccountData[ThreadFollows.type]
    };
    for (final r in work.matrixClient.rooms) {
      r.roomAccountData.remove(ThreadFollows.type);
    }
    addTearDown(() {
      for (final r in work.matrixClient.rooms) {
        if (before[r.id] case final entry?)
          r.roomAccountData[ThreadFollows.type] = entry;
      }
    });
    showCards([_type, HomeLayout.invites]);
    requests.clear();
    failPages = true;
    failureStatus = 429;
    await pumpHome(tester, work, phone: true);
    expect(find.text("Couldn’t check recent rooms. Try refreshing."),
        findsOneWidget);
    expect(requests, hasLength(6));
    await tester.pump(const Duration(seconds: 29));
    expect(requests, hasLength(6));
    await tester.pump(const Duration(minutes: 2));
    expect(requests, hasLength(6));
    Future<void> refresh() async {
      await tester.tap(find.byTooltip("Refresh followed threads"));
      await tester.pump();
      await settlePreview(tester);
    }

    failureStatus = 403;
    await refresh();
    await tester.pump(const Duration(minutes: 2));
    expect(requests, hasLength(12));
    failPages = false;
    pageRoots = (_) => [];
    await refresh();
    expect(find.text("No followed activity found in recent rooms."),
        findsOneWidget);
    final read = _root("Work", r"$read-proof", unread: false);
    pageRoots = (id) => id == roomId ? [read] : [];
    await refresh();
    expect(find.text("Work project notes"), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, "Unread"));
    await tester.pumpAndSettle();
    expect(find.text("Work project notes"), findsNothing);
    expect(find.text("No unread replies in this preview."), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, "All"));
    await tester.pumpAndSettle();
    failPages = true;
    await refresh();
    expect(find.text("Work project notes"), findsOneWidget);
    expect(find.text("Refresh incomplete. Showing the previous preview."),
        findsOneWidget);
    failPages = false;
    final missing = _root("Work", r"$missing", unread: false);
    final spoiler = _root("Work", r"$spoiler", unread: false);
    final encrypted = _root("Work", r"$encrypted", unread: false);
    final removed = _root("Work", r"$removed", unread: false);
    Map<String, dynamic> info(Map<String, Object?> root) =>
        (root["unsigned"] as Map)["m.relations"]["m.thread"]
            as Map<String, dynamic>;
    info(missing).remove("latest_event");
    spoiler["content"] = {
      "msgtype": "m.text",
      "body": "hidden-secret",
      "formatted_body": '<span data-mx-spoiler>hidden-secret</span>'
    };
    encrypted["type"] = "m.room.encrypted";
    encrypted["content"] = {
      "algorithm": "m.megolm.v1.aes-sha2",
      "session_id": "unknown",
      "ciphertext": "ciphertext"
    };
    (info(encrypted)["latest_event"] as Map)["content"] = {
      "msgtype": "m.image",
      "body": "media-secret",
      "m.spoiler": true,
    };
    info(removed).clear();
    (removed["unsigned"] as Map)["redacted_because"] =
        stateEvent("m.room.redaction", {}).toJson();
    pageRoots =
        (id) => id == roomId ? [missing, spoiler, encrypted, removed] : [];
    await refresh();
    expect(find.text("Reply preview unavailable."), findsOneWidget);
    expect(find.text("Spoiler"), findsOneWidget);
    expect(find.text("Encrypted preview unavailable."), findsOneWidget);
    expect(find.textContaining(": Spoiler"), findsOneWidget);
    expect(find.textContaining("media-secret"), findsNothing);
    expect(find.text("Message deleted"), findsNothing);
    expect(find.textContaining("hidden-secret"), findsNothing);
    expect(find.text("Work project notes"), findsOneWidget);
    expect(profileRequests, isEmpty);
    final live = _root("Work", r"$live-proof", unread: true);
    (live["content"] as Map)["body"] = "Lifecycle topic";
    pageRoots = (id) => id == roomId ? [live] : [];
    await refresh();
    final requestsBeforeSync = requests.length;
    await tester.runAsync(() => sync(work, join: {
          roomId: matrix.JoinedRoomUpdate(ephemeral: [
            matrix.BasicEvent(
              type: "m.receipt",
              content: {
                r"$reply-$live-proof": {
                  "m.read": {
                    me: {
                      "ts": 1700000000300,
                      "thread_id": r"$live-proof",
                    }
                  }
                }
              },
            )
          ]),
        }));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, "Unread"));
    await tester.pumpAndSettle();
    expect(find.text("No unread replies in this preview."), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, "All"));
    await tester.pumpAndSettle();
    expect(find.text("Lifecycle topic"), findsOneWidget);
    final sdkRoom = work.matrixClient.getRoomById(roomId)!;
    work.matrixClient.onTimelineEvent.add(matrix.Event(
      room: sdkRoom,
      type: "m.room.redaction",
      eventId: r"$delete-live",
      senderId: me,
      content: {},
      redacts: r"$live-proof",
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000000400),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Lifecycle topic"), findsNothing);
    expect(requests.length, requestsBeforeSync);
    await refresh();
    expect(find.text("Lifecycle topic"), findsOneWidget);
    addTearDown(
        () => sync(work, join: {roomId: joined(roomId, name: "Project 8")}));
    await tester.runAsync(() => sync(work, leave: {roomId: left("leave")}));
    await tester.pumpAndSettle();
    expect(find.text("Lifecycle topic"), findsNothing);
  });

  testWidgets("customizing and signout discard pending previews",
      (tester) async {
    showCards([_type, HomeLayout.invites]);
    requests.clear();
    newHomeCustomizing.value = true;
    await pumpHome(tester, work, phone: false);
    expect(find.text("Recent replies in threads you follow"), findsOneWidget);
    expect(requests, isEmpty);
    newHomeCustomizing.value = false;
    await tester.pump();
    await settlePreview(tester);
    stalledPages = Completer<void>();
    await tester.tap(find.byTooltip("Refresh followed threads"));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.runAsync(() => work.matrixClient.clear());
    await tester.pumpAndSettle();
    expect(find.text("Select an account to see followed threads."),
        findsOneWidget);
    stalledPages!.complete();
    stalledPages = null;
    await settlePreview(tester);
    expect(find.textContaining("Work release checklist"), findsNothing);
    expect(find.text("Select an account to see followed threads."),
        findsOneWidget);
  });
}
