import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart' show preferences;
import 'package:commet/ui/organisms/call_view/call_view.dart';
import 'package:commet/ui/organisms/call_view/stream_mini_player.dart';
import 'package:commet/ui/organisms/call_view/stream_popout_window.dart';
import 'package:commet/ui/organisms/call_view/voip_stream_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'fixtures/popout_fixtures.dart';

void main() {
  late FakePopoutBackend backend;
  late StreamPopoutWindow windows;
  late CameraFixtureStream a, b;
  late CameraFixtureSession session;
  setUp(() {
    backend = FakePopoutBackend();
    windows = StreamPopoutWindow(backend, afterFrame: () async {});
    a = CameraFixtureStream('a', 'alex');
    b = CameraFixtureStream('b', 'you',
        direction: VoipStreamDirection.outgoing);
    session = CameraFixtureSession([a, b]);
    StreamMiniPlayer.instance.hide();
  });
  tearDown(() async {
    windows.dispose();
    await pumpEventQueue();
    await backend.changes.close();
  });

  test('two cameras and a screen share coexist; commands address one view',
      () async {
    final share =
        CameraFixtureStream('s', 'alex', type: VoipStreamType.screenshare);
    session.streams.add(share);
    await windows.open(session, share);
    await windows.openCamera(session, a);
    await windows.openCamera(session, b);
    expect(windows.windows.length, 3);
    expect(backend.live, {1, 2, 3});
    final first = windows.cameraFor(session, a)!;
    final second = windows.cameraFor(session, b)!;
    first.setTitle('Alex');
    second.setTitle('You');
    await first.setFullscreen(true);
    expect(backend.titles, {2: 'Alex', 3: 'You'});
    expect(backend.fullscreens, {2: true});
    await first.dockBack();
    expect(backend.live, {1, 3});
    expect(windows.cameraFor(session, b), second);
    expect(session.streams, containsAll([a, b, share]));
    expect(backend.sizes[1], (400, 300, 240, 180));
    expect(a.changes.hasListener, isFalse);
  });
  test(
      'same camera opens once, focuses its own view, including concurrent opens',
      () async {
    final done = backend.delayed = Completer<int?>();
    final first = windows.openCamera(session, a);
    final second = windows.openCamera(session, a);
    expect(backend.opens, 1);
    done.complete(10);
    await first;
    await second;
    await windows.openCamera(session, a);
    expect(backend.opens, 1);
    expect(backend.focused, [10]);
  });
  test('close while opening destroys the late result without attaching',
      () async {
    final done = backend.delayed = Completer<int?>();
    final opening = windows.openCamera(session, a);
    final closing = windows.cameraFor(session, a)!.close();
    done.complete(10);
    await opening;
    await closing;
    expect(backend.live, isEmpty);
    expect(windows.windows, isEmpty);
    expect(backend.closed, [10]);
  });
  test('old close and events cannot close or retitle a rapid reopen', () async {
    final frame = Completer<void>();
    windows.dispose();
    windows = StreamPopoutWindow(backend, afterFrame: () => frame.future);
    await windows.openCamera(session, a);
    final old = windows.cameraFor(session, a)!;
    final oldRequest = backend.requests[1];
    final closing = old.dockBack();
    await windows.openCamera(session, a);
    final next = windows.cameraFor(session, a)!;
    backend.changes.add(StreamPopoutEvent(StreamPopoutEventKind.closeRequested,
        viewId: 1, requestId: oldRequest));
    old.setTitle('stale');
    frame.complete();
    await closing;
    expect(backend.live, {2});
    expect(windows.cameraFor(session, a), next);
  });
  test(
      'track replacement follows device, not a same-name participant; ending closes',
      () async {
    await windows.openCamera(session, a);
    await windows.openCamera(session, b);
    final next = CameraFixtureStream('new', 'alex');
    session.streams = [next, b];
    session.changes.add(null);
    await pumpEventQueue();
    expect(windows.cameraFor(session, next)?.stream, next);
    expect(a.changes.hasListener, isFalse);
    expect(next.changes.hasListener, isTrue);
    session.streams = [b];
    next.changes.add(null);
    await pumpEventQueue();
    expect(backend.live, {2});
    expect(next.changes.hasListener, isFalse);
  });
  test(
      'call leave closes only its session, account close needs no session signal',
      () async {
    final another = CameraFixtureSession([a]);
    await windows.openCamera(session, a);
    await windows.openCamera(session, b);
    await windows.openCamera(another, a);
    session.state = VoipState.ended;
    session.connections.add(VoipState.ended);
    await pumpEventQueue();
    expect(backend.live, {3});
    await windows.closeForClient(another.client);
    expect(backend.live, isEmpty);
    expect(another.changes.hasListener, isFalse);
    expect(a.changes.hasListener, isFalse);
  });
  test('native close docks once, never stops capture or audio', () async {
    final focus = <VoipStream>[];
    final sub =
        windows.cameraFocusRequests.listen((request) => focus.add(request.$2));
    await windows.openCamera(session, a);
    backend.changes.add(const StreamPopoutEvent(
        StreamPopoutEventKind.closeRequested,
        viewId: 1));
    backend.changes.add(const StreamPopoutEvent(
        StreamPopoutEventKind.closeRequested,
        viewId: 1));
    await pumpEventQueue();
    expect(backend.closed, [1]);
    expect(focus, [a]);
    expect(session.streams, [a, b]);
    await sub.cancel();
  });
  test(
      'open failure stays in call, no camera mini-player or retained listeners',
      () async {
    backend.fail = true;
    expect(await windows.openCamera(session, a), CameraPopoutResult.failed);
    expect(windows.windows, isEmpty);
    expect(StreamMiniPlayer.instance.showing, isFalse);
    expect(a.changes.hasListener, isFalse);
  });
  test(
      'dispose closes all windows and releases session and track subscriptions',
      () async {
    await windows.openCamera(session, a);
    await windows.openCamera(session, b);
    windows.dispose();
    await pumpEventQueue();
    expect(backend.live, isEmpty);
    expect(session.changes.hasListener, isFalse);
    expect(session.connections.hasListener, isFalse);
    expect(a.changes.hasListener, isFalse);
  });
  testWidgets(
      'minimum camera controls at 200% text remain labeled and operable',
      (tester) async {
    var docked = 0;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
                child: SizedBox(
                    width: 216,
                    height: 60,
                    child: CameraPopoutControls(
                        fullscreen: false,
                        onFullscreen: () {},
                        onDockBack: () => docked++))))));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Dock back'), findsOneWidget);
    await tester.tap(find.byTooltip('Dock back'));
    expect(docked, 1);
  });
  testWidgets(
      'actual camera page has only view controls and keyboard reveals hidden controls',
      (tester) async {
    await windows.openCamera(session, a);
    final window = windows.cameraFor(session, a)!;
    await tester.pumpWidget(MaterialApp(
        home: StreamPopoutPage(window: window, session: session, stream: a)));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('streamPopoutStopWatching')), findsNothing);
    expect(find.byKey(const ValueKey('streamPopoutDockBack')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('placeholder docks without rendering a duplicate camera',
      (tester) async {
    var docked = 0;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Center(
            child: SizedBox(
                width: 240,
                height: 180,
                child: CameraPopoutPlaceholder(onDockBack: () => docked++)))));
    await tester.ensureVisible(find.text('Dock back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dock back'));
    expect(docked, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'shared CallView supports camera pop-out in every style, navigation mode and size',
      (tester) async {
    // unit_test/ is not recognized as a test directory by the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    StreamPopoutWindow.install(backend: backend);
    final installed = StreamPopoutWindow.maybeInstance!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      installed.dispose();
      await tester.pump();
      tester.view.reset();
    });
    for (final style in LayoutStyle.values) {
      await pickLayoutStyle(style);
      for (final unified in [false, true]) {
        await experimentUnifiedChatList.set(unified);
        for (final size in [const Size(390, 740), const Size(1000, 640)]) {
          await preferences.layoutOverride
              .set(size.width < 500 ? 'mobile' : 'desktop');
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(MaterialApp(
              theme: ThemeDark.theme,
              home: MediaQuery(
                  data: MediaQueryData(
                      size: size,
                      accessibleNavigation: true,
                      textScaler:
                          TextScaler.linear(size.width < 500 ? 1.5 : 1)),
                  child: Scaffold(body: CallView(session)))));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: '$style/$unified/$size');
          expect(find.byKey(const ValueKey('cameraPopOut')), findsNWidgets(2));
          await tester.tap(find.byKey(const ValueKey('cameraPopOut')).last);
          await tester.pump();
          expect(find.byType(CameraPopoutPlaceholder), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('cameraPopOut')).first);
          await tester.pump();
          expect(find.byType(CameraPopoutPlaceholder), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          final closing = installed.closeForClient(session.client);
          await tester.pump();
          await closing;
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    installed.dispose();
    tester.view.reset();
  });
}
