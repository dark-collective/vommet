// The real Library page with a direct chat holding the other person's pack
// and one of ours: the "Room and space packs" section and the Move/Copy
// list show only ours.

import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/library/library_page.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

const _me = "@me:example.org";
const _them = "@alex:example.org";

/// Android phone and desktop widths.
const phone = Size(412, 915);
const desktop = Size(1280, 800);

Future<void> setUpLibrary() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // MatrixClient's calls component listens for WebRTC events
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(const EventChannel("FlutterWebRTC.Event"),
          MockStreamHandler.inline(onListen: (_, __) {}));
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
}

matrix.Room _room(matrix.Client mx, String id, String name) {
  final room =
      matrix.Room(id: id, client: mx, membership: matrix.Membership.join);
  room.setState(matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomPowerLevels,
      content: {
        "users": {_me: 100, _them: 100}
      },
      senderId: _them,
      stateKey: ""));
  room.setState(matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomName,
      content: {"name": name},
      senderId: _them,
      stateKey: ""));
  mx.rooms.add(room);
  return room;
}

// Images without a url, so nothing is fetched.
void _pack(matrix.Room room, String key, String name, String sender) =>
    room.setState(matrix.StrippedStateEvent(
        type: ImagePackTypes.roomPack,
        content: {
          "pack": {"display_name": name},
          "images": {
            "$key-cat": {"body": "cat"}
          },
        },
        senderId: sender,
        stateKey: key));

/// The Library page of an account with a DM with Alex (Alex's pack "Their
/// pack" and our "My pack") and a group room with "Group pack", at [size].
Future<void> pumpLibrary(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = (await tester.runAsync(() async {
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), "library-dm-packs-page");
    return MatrixClient(
        identifier: "library-dm-packs-page", database: database);
  }))!;
  final mx = client.matrixClient;
  mx.setUserId(_me);
  final dm = _room(mx, "!dm:example.org", "Alex");
  final group = _room(mx, "!group:example.org", "Book club");
  mx.accountData["m.direct"] = matrix.BasicEvent(type: "m.direct", content: {
    _them: [dm.id]
  });
  _pack(dm, "theirs", "Their pack", _them);
  _pack(dm, "mine", "My pack", _me);
  _pack(group, "group", "Group pack", _them);

  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    debugShowCheckedModeBanner: false,
    // Around the navigator, so a render also holds dialogs.
    builder: (context, child) =>
        RepaintBoundary(key: const ValueKey("library"), child: child),
    home: LibraryPage(client: client),
  ));
  await tester.pump();
}

/// Opens "Group pack", selects its image and opens "Copy to…".
Future<void> openCopyTo(WidgetTester tester) async {
  await tester.tap(find.text("Group pack"));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
      of: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == "group-cat"),
      matching: find.byType(InkWell)));
  await tester.pumpAndSettle();
  await tester.tap(find.text("Copy to…"));
  await tester.pumpAndSettle();
}

void main() {
  setUp(setUpLibrary);

  for (final (name, size) in [("phone", phone), ("desktop", desktop)]) {
    testWidgets("$name: the sidebar lists our DM pack, not Alex's",
        (tester) async {
      await pumpLibrary(tester, size);
      expect(find.text("ROOM AND SPACE PACKS"), findsOneWidget);
      expect(find.text("Alex"), findsOneWidget);
      expect(find.text("My pack"), findsOneWidget);
      expect(find.text("Group pack"), findsOneWidget);
      expect(find.textContaining("Their pack"), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("Copy to doesn't offer Alex's DM pack", (tester) async {
    await pumpLibrary(tester, phone);
    await openCopyTo(tester);
    expect(find.text("Copy to"), findsOneWidget);
    expect(find.textContaining("My pack"), findsOneWidget);
    expect(find.textContaining("Their pack"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
