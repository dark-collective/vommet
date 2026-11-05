import 'dart:io';

import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/main.dart' show preferences;
import 'package:commet/ui/organisms/call_view/call_view.dart';
import 'package:commet/ui/organisms/call_view/stream_popout_window.dart';
import 'package:commet/ui/organisms/call_view/voip_stream_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../unit_test/fixtures/popout_fixtures.dart';
import 'extensions/wait_for.dart';

Future<void> capture(String name) async {
  final helper = Platform.environment['VOMMET_POPOUT_CAPTURE'];
  if (helper == null) return;
  final result = await Process.run('python3', [helper, name]);
  if (result.exitCode != 0)
    throw StateError('Native capture helper failed: ${result.exitCode}');
}

void main({bool isolated = false}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Linux cameras: independent native views, docking, resize, cleanup and reopen',
      (tester) async {
    final binding = tester.binding as IntegrationTestWidgetsFlutterBinding;
    final previousPolicy = binding.framePolicy;
    final previousDeviceEvents = binding.shouldPropagateDevicePointerEvents;
    // Route real X11 pointer events through the production hit-test path. The
    // test-only coordinate adapter assumes the target view still exists even
    // for a late leave packet from a window that has just been destroyed.
    binding.shouldPropagateDevicePointerEvents = true;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    try {
      // In-memory preferences only; never load or log in a real account.
      if (isolated) {
        SharedPreferences.setMockInitialValues({});
        await preferences.init();
      }
      StreamPopoutWindow.install();
      final windows = StreamPopoutWindow.maybeInstance!;
      final a = CameraFixtureStream('fixture-camera-a', 'alex');
      final b = CameraFixtureStream('fixture-camera-b', 'you',
          direction: VoipStreamDirection.outgoing);
      final share = CameraFixtureStream('fixture-screen', 'alex',
          type: VoipStreamType.screenshare);
      final session = CameraFixtureSession([a, b, share]);
      final watching = PopoutFixtureWatching();
      VoipStreamWatching.register(session, watching);
      final dispatcher = tester.binding.platformDispatcher;
      final before = dispatcher.views.length;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: StreamPopoutHost(
              window: windows,
              child: Scaffold(
                  appBar:
                      AppBar(title: const Text('Fixture call · no live media')),
                  body: CallView(session)))));
      await tester.pump();
      expect(find.byType(VoipStreamView), findsWidgets);
      await tester.pump(const Duration(milliseconds: 200));
      await capture('call-before');
      expect(await windows.openCamera(session, a), CameraPopoutResult.opened);
      expect(await windows.openCamera(session, b), CameraPopoutResult.opened);
      await windows.open(session, share);
      await tester
          .waitFor(() => find.byType(StreamPopoutPage).evaluate().length == 3);
      expect(dispatcher.views.length, before + 3);
      final wa = windows.cameraFor(session, a)!;
      final wb = windows.cameraFor(session, b)!;
      final ids = {wa.viewId!, wb.viewId!, windows.viewId!};
      expect(ids.length, 3);
      // Each renderer appears once (the main tile is a placeholder).
      expect(find.byKey(const ValueKey('streamPopoutVideo_fixture-camera-a')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('streamPopoutVideo_fixture-camera-b')),
          findsOneWidget);
      expect(find.byType(CameraPopoutPlaceholder), findsNWidgets(2));
      for (final page in find.byType(StreamPopoutPage).evaluate()) {
        final view = View.of(page);
        final size = tester.getSize(find.byWidget(page.widget));
        expect(size.width,
            closeTo(view.physicalSize.width / view.devicePixelRatio, 2));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await capture('three-windows');
      if (Platform.environment['VOMMET_POPOUT_CAPTURE'] != null) {
        await capture('minimum-window');
        await tester.waitFor(() {
          final view = dispatcher.view(id: wa.viewId!);
          return view != null &&
              (view.physicalSize.width / view.devicePixelRatio - 240).abs() < 2;
        });
      }
      final cameraPage = find.byWidgetPredicate(
          (w) => w is StreamPopoutPage && identical(w.window, wa));
      final oldA = wa.viewId;
      await tester.tap(find.descendant(
          of: cameraPage,
          matching: find.byKey(const ValueKey('streamPopoutDockBack'))));
      await tester.waitFor(() => windows.cameraFor(session, a) == null);
      await tester.waitFor(() => dispatcher.views.length == before + 2);
      expect(windows.cameraFor(session, b), same(wb));
      expect(session.streams, contains(a));
      expect(watching.focusRequests,
          isEmpty); // camera docking doesn't alter screen watching
      await windows.openCamera(session, a);
      await tester.waitFor(() => dispatcher.views.length == before + 3);
      expect(windows.cameraFor(session, a)!.viewId, isNot(oldA));
      await capture('reopened');
      if (Platform.environment['VOMMET_POPOUT_CAPTURE'] != null) {
        await capture('native-close-camera');
        await tester.waitFor(() => windows.cameraFor(session, b) == null);
        await tester.waitFor(() => dispatcher.views.length == before + 2);
        expect(session.streams, contains(b));
      }
      session.streams.remove(a);
      session.changes.add(null);
      await tester.waitFor(() =>
          dispatcher.views.length ==
          before + (windows.cameraFor(session, b) == null ? 1 : 2));
      await windows.closeForClient(session.client);
      await tester.waitFor(() => dispatcher.views.length == before);
      expect(windows.windows, isEmpty);
      expect(a.changes.hasListener, isFalse);
      // The main call view still observes this camera: closing a window must
      // not dispose the session's feed. Its listener goes when that UI unmounts.
      expect(b.changes.hasListener, isTrue);
      expect(tester.takeException(), isNull);
      final disposable = StreamPopoutWindow(windows.backend);
      await tester.pumpWidget(MaterialApp(
          home: StreamPopoutHost(
              window: disposable, child: const Text('shutdown fixture'))));
      expect(b.changes.hasListener, isFalse);
      await disposable.openCamera(session, b);
      await tester.waitFor(() => dispatcher.views.length == before + 1);
      disposable.dispose();
      await tester.waitFor(() => dispatcher.views.length == before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await watching.changed.close();
      await watching.focus.close();
      await tester.pump(const Duration(milliseconds: 100));
    } finally {
      binding.framePolicy = previousPolicy;
      binding.shouldPropagateDevicePointerEvents = previousDeviceEvents;
    }
  }, skip: !Platform.isLinux);
}
