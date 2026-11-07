import 'dart:io';
import 'dart:ui' as ui;

import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const _captureKey = ValueKey('capture');
const _toggleKey = ValueKey('NewHomeRoomsCollapseAll');

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['VOMMET_1249_CAPTURES'];
  if (directory == null) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$directory/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  late ClientManager manager;

  setUpAll(() async {
    final flutter = Platform.environment['FLUTTER_ROOT'];
    if (flutter != null &&
        Platform.environment['VOMMET_1249_CAPTURES'] != null) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(File(
                '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then(ByteData.sublistView));
      await loader.load();
      final textFont = FontLoader('Roboto')
        ..addFont(File('assets/font/roboto/Roboto-Regular.ttf')
            .readAsBytes()
            .then(ByteData.sublistView));
      await textFont.load();
    }
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient('rooms-header-actions');
    await sync(client, join: {
      '!a:example.com': joined('!a:example.com',
          name: 'Studio',
          children: ['!nested:example.com', '!chat:example.com']),
      '!b:example.com': joined('!b:example.com',
          name: 'A much longer space name for the community book club',
          children: ['!books:example.com']),
      '!nested:example.com': joined('!nested:example.com',
          name: 'Nested space', children: ['!nested-chat:example.com']),
      '!chat:example.com': joined('!chat:example.com', name: 'General'),
      '!nested-chat:example.com':
          joined('!nested-chat:example.com', name: 'Design'),
      '!books:example.com': joined('!books:example.com', name: 'Reading'),
      '!solo:example.com': joined('!solo:example.com', name: 'Standalone chat'),
    });
    manager = ClientManager()..addClient(client);
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  for (final (name, size, phone, standalone) in [
    ('desktop', const Size(3840, 1496), false, true),
    ('phone', const Size(360, 840), true, true),
    ('phone without standalone rooms', const Size(360, 840), true, false),
  ]) {
    testWidgets('Rooms header actions share the trailing edge on $name',
        (tester) async {
      if (!standalone) {
        await tester.runAsync(
            () => sync(client, leave: {'!solo:example.com': left('leave')}));
      }
      await newHomeRoomsCollapsed.set([]);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        builder: standalone
            ? null
            : (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.6)),
                  child: child!,
                ),
        home: RepaintBoundary(
          key: _captureKey,
          child: Scaffold(
            body: NewHomeRooms(
                clientManager: manager, filterClient: null, phone: phone),
          ),
        ),
      ));
      await tester.pump();
      final toggle = find.byKey(_toggleKey);
      final open = find.byTooltip('Open space');
      expect(open, findsNWidgets(3));
      if (standalone) await _capture(tester, name);

      void expectAligned(int spaces) {
        expect(open, findsNWidgets(spaces));
        final toggleRect = tester.getRect(toggle);
        var hasAdjacentAction = false;
        for (var index = 0; index < spaces; index++) {
          final action = tester.getRect(open.at(index));
          if (!standalone &&
              (action.center.dy - toggleRect.center.dy).abs() < 1) {
            hasAdjacentAction = true;
            expect(action.right, lessThanOrEqualTo(toggleRect.left));
          } else {
            expect(action.right, closeTo(toggleRect.right, 0.01));
          }
        }
        expect(hasAdjacentAction, !standalone);
        expect(toggleRect.right, closeTo(size.width - (phone ? 12 : 24), 0.01));
        expect(tester.takeException(), isNull);
      }

      expectAligned(3);
      await tester.tap(toggle);
      await tester.pump();
      expectAligned(2);
      expect(find.text('General'), findsNothing);
      await tester.tap(toggle);
      await tester.pump();
      expectAligned(3);
      expect(find.text('General'), findsOneWidget);
    });
  }
}
