import 'dart:async';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/molecules/video_player/video_pip.dart';
import 'package:commet/ui/molecules/video_player/video_player.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _File extends Fake implements FileProvider {}

class _Backend {
  final controller = VideoPlayerController();
  final seeks = <Duration>[];
  Duration length = const Duration(seconds: 60);
  int playCalls = 0;
  int pauseCalls = 0;
  Future<void> Function(Duration)? seek;

  _Backend() {
    controller.attach(
      pause: () async {
        pauseCalls++;
      },
      play: () async {
        playCalls++;
      },
      replay: () async {},
      getLength: () async => length,
      getSize: () async => const Size(640, 360),
      getVolume: () async => 100,
      seekTo: (value) async {
        await seek?.call(value);
        seeks.add(value);
      },
      setVolume: (_) async {},
    );
  }
}

Finder get _forward => find.byKey(const ValueKey('video_seek_forward'));
Finder get _back => find.byKey(const ValueKey('video_seek_back'));

Future<void> _doubleTap(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 70));
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pump(WidgetTester tester, VideoPlayerController controller,
    {bool pip = false,
    double width = 360,
    double scale = 1,
    VoidCallback? messageDoubleTap,
    VoidCallback? swipe,
    TextDirection direction = TextDirection.ltr}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
        body: Center(
            child: GestureDetector(
      onDoubleTap: messageDoubleTap,
      onVerticalDragEnd: swipe == null ? null : (_) => swipe(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: width,
            height: width * 9 / 16,
            child: VideoPlayer(_File(),
                controller: controller,
                isPictureInPicture: pip,
                canGoFullscreen: true,
                onFullscreen: () {})),
        const SizedBox(width: 360, height: 60, child: Text('Message caption')),
      ]),
    ))),
  ));
  await tester.pumpAndSettle();
}

Future<void> _hide(WidgetTester tester) async {
  tester.state<VideoPlayerState>(find.byType(VideoPlayer)).onUnhovered();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test('relative seek clamps both ends and preserves playback state', () async {
    final backend = _Backend();
    backend.controller.setProgress(const Duration(seconds: 55));
    expect(await backend.controller.seekRelative(const Duration(seconds: 10)),
        true);
    backend.controller.setProgress(const Duration(seconds: 4));
    await backend.controller.seekRelative(const Duration(seconds: -10));
    expect(backend.seeks, [const Duration(seconds: 60), Duration.zero]);
    expect(backend.playCalls, 0);
    expect(backend.pauseCalls, 0);
    await backend.controller.play();
    await backend.controller.seekRelative(const Duration(seconds: 10));
    expect(backend.playCalls, 1);
    expect(backend.pauseCalls, 0);
  });

  test('rapid queued seeks accumulate despite stale backend progress',
      () async {
    final backend = _Backend();
    backend.controller.setProgress(const Duration(seconds: 20));
    final gate = Completer<void>();
    backend.seek = (_) => gate.future;
    final first = backend.controller.seekRelative(const Duration(seconds: 10));
    final second = backend.controller.seekRelative(const Duration(seconds: 10));
    final third = backend.controller.seekRelative(const Duration(seconds: -10));
    await Future<void>.delayed(Duration.zero);
    backend.controller.setProgress(const Duration(seconds: 20));
    gate.complete();
    await Future.wait([first, second, third]);
    expect(backend.seeks.map((d) => d.inSeconds), [30, 40, 30]);
  });

  test('unattached and unknown duration never seek or load media', () async {
    expect(
        await VideoPlayerController().seekRelative(const Duration(seconds: 10)),
        false);
    final backend = _Backend()..length = Duration.zero;
    expect(await backend.controller.seekRelative(const Duration(seconds: 10)),
        false);
    expect(backend.seeks, isEmpty);
    expect(backend.playCalls, 0);
  });

  // Vommet issue 920: a rebuilt player must not seek a disposed one.
  test('detach clears the disposed player, not a newer one', () async {
    final controller = VideoPlayerController();
    var oldSeeks = 0;
    var newSeeks = 0;
    void attach(Object owner, void Function() onSeek) => controller.attach(
          owner: owner,
          pause: () async {},
          play: () async {},
          replay: () async {},
          getLength: () async => const Duration(seconds: 60),
          getSize: () async => const Size(640, 360),
          getVolume: () async => 100,
          seekTo: (_) async => onSeek(),
          setVolume: (_) async {},
        );
    final old = Object();
    final current = Object();
    attach(old, () => oldSeeks++);
    attach(current, () => newSeeks++);
    controller.detach(old);
    expect(controller.attached, true);
    expect(await controller.seekRelative(const Duration(seconds: 10)), true);
    controller.detach(current);
    expect(controller.attached, false);
    expect(await controller.seekRelative(const Duration(seconds: 10)), false);
    expect(oldSeeks, 0);
    expect(newSeeks, 1);
  });

  test('failed seek does not poison subsequent requests', () async {
    final backend = _Backend();
    backend.controller.setProgress(const Duration(seconds: 20));
    backend.seek = (_) async => throw StateError('backend rejected');
    await expectLater(
        backend.controller.seekRelative(const Duration(seconds: 10)),
        throwsStateError);
    backend.seek = null;
    await backend.controller.seekRelative(const Duration(seconds: -10));
    expect(backend.seeks, [const Duration(seconds: 10)]);
  });

  testWidgets('buttons seek immediately and expose 48px labeled targets',
      (tester) async {
    final backend = _Backend();
    backend.controller.setProgress(const Duration(seconds: 20));
    var messages = 0;
    await _pump(tester, backend.controller, messageDoubleTap: () => messages++);
    final semantics = tester.ensureSemantics();
    expect(tester.getSemantics(_forward).getSemanticsData().tooltip,
        'Forward 10 seconds');
    expect(tester.getSize(_forward).shortestSide, greaterThanOrEqualTo(48));
    await tester.tap(_forward);
    await tester.pump();
    expect(backend.seeks, [const Duration(seconds: 30)]);
    await tester.tap(_back);
    await tester.pump();
    expect(backend.seeks.last, const Duration(seconds: 20));
    expect(backend.playCalls, 0);
    expect(backend.pauseCalls, 0);
    expect(messages, 0);
    semantics.dispose();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pause and speed controls bypass message double-tap delay',
      (tester) async {
    final backend = _Backend();
    var messages = 0;
    await _pump(tester, backend.controller, messageDoubleTap: () => messages++);
    final state = tester.state<VideoPlayerState>(find.byType(VideoPlayer));
    state.playing = true;
    state.onHovered();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(backend.pauseCalls, 1);
    expect(backend.playCalls, 0);
    await tester.tap(find.byKey(const ValueKey('video_playback_speed_button')));
    await tester.pump();
    expect(find.byType(PopupMenuItem<double>), findsNWidgets(4));
    expect(messages, 0);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('seek buttons stay disabled until duration is known',
      (tester) async {
    final backend = _Backend()..length = Duration.zero;
    await _pump(tester, backend.controller);
    expect(tester.widget<IconButton>(_forward).onPressed, isNull);
    backend.length = const Duration(seconds: 60);
    backend.controller.setProgress(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(_forward).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [160.0, 200.0, 360.0, 640.0]) {
    testWidgets('controls fit width $width at double text scale',
        (tester) async {
      final backend = _Backend();
      await _pump(tester, backend.controller,
          width: width, scale: 2, pip: width < 200);
      expect(tester.takeException(), isNull);
      if (width >= 200) {
        final rect = tester.getRect(find.byType(VideoPlayer));
        expect(tester.getRect(_forward).bottom,
            lessThanOrEqualTo(rect.bottom - 50));
        await tester.tap(_forward);
        await tester.pump();
      } else {
        expect(_forward, findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('PiP canvas expands without seeking', (tester) async {
    final backend = _Backend();
    var expanded = 0;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => VideoPip.show(VideoPipRequest(
                        player: (_) => VideoPlayer(_File(),
                            controller: backend.controller,
                            isPictureInPicture: true),
                        onExpand: () => expanded++)),
                    child: const Text('Open PiP'))))));
    await tester.tap(find.text('Open PiP'));
    await tester.pumpAndSettle();
    expect(_forward, findsNothing);
    expect(find.byKey(const ValueKey('video_seek_zone_1')), findsNothing);
    final rect = tester.getRect(find.byType(VideoPlayer));
    await _doubleTap(tester, rect.topLeft + const Offset(40, 30));
    expect(expanded, 1);
    expect(backend.seeks, isEmpty);
    VideoPip.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('outer thirds own double taps; caption keeps message action',
      (tester) async {
    final backend = _Backend();
    backend.controller.setProgress(const Duration(seconds: 20));
    var messages = 0;
    await _pump(tester, backend.controller, messageDoubleTap: () => messages++);
    await _hide(tester);
    final rect = tester.getRect(find.byType(VideoPlayer));
    await _doubleTap(tester, rect.topLeft + const Offset(35, 35));
    expect(
        backend.seeks.map((d) => d.inSeconds), BuildConfig.MOBILE ? [10] : []);
    if (BuildConfig.MOBILE) expect(messages, 0);
    await tester.pump(const Duration(milliseconds: 400));
    await _doubleTap(tester, tester.getCenter(find.text('Message caption')));
    expect(messages, BuildConfig.MOBILE ? 1 : 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  if (BuildConfig.MOBILE) {
    testWidgets('seeking keeps physical left/right in an RTL layout',
        (tester) async {
      final backend = _Backend();
      backend.controller.setProgress(const Duration(seconds: 20));
      await _pump(tester, backend.controller, direction: TextDirection.rtl);
      expect(
          tester.getCenter(_back).dx, lessThan(tester.getCenter(_forward).dx));
      await _hide(tester);
      final rect = tester.getRect(find.byType(VideoPlayer));
      await _doubleTap(tester, rect.topLeft + const Offset(35, 30));
      expect(backend.seeks, [const Duration(seconds: 10)]);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('unloaded canvas consumes double taps without opening media',
        (tester) async {
      var messages = 0;
      final controller = VideoPlayerController();
      await _pump(tester, controller, messageDoubleTap: () => messages++);
      await _hide(tester);
      final rect = tester.getRect(find.byType(VideoPlayer));
      await _doubleTap(tester, rect.topLeft + const Offset(35, 30));
      expect(messages, 0);
      expect(controller.attached, false);
      expect(tester.state<VideoPlayerState>(find.byType(VideoPlayer)).inited,
          false);
      expect(find.text('−10 seconds'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('single taps reveal; center double taps do not seek',
        (tester) async {
      final backend = _Backend();
      var messages = 0;
      await _pump(tester, backend.controller,
          messageDoubleTap: () => messages++);
      await _hide(tester);
      final rect = tester.getRect(find.byType(VideoPlayer));
      final point = rect.topLeft + const Offset(35, 30);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 350));
      expect(
          tester
              .state<VideoPlayerState>(find.byType(VideoPlayer))
              .shouldShowControls,
          true);
      await _hide(tester);
      await _doubleTap(tester, Offset(rect.center.dx, rect.top + 25));
      expect(backend.seeks, isEmpty);
      expect(messages, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'hidden controls do not intercept double taps or vertical swipes',
        (tester) async {
      final backend = _Backend();
      var swipes = 0;
      await _pump(tester, backend.controller, swipe: () => swipes++);
      await _hide(tester);
      final rect = tester.getRect(find.byType(VideoPlayer));
      await _doubleTap(tester, Offset(rect.right - 35, rect.center.dy));
      expect(backend.seeks, [const Duration(seconds: 10)]);
      expect(find.text('+10 seconds'), findsOneWidget);
      await tester.dragFrom(
          Offset(rect.left + 35, rect.center.dy), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(swipes, 1);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('+10 seconds'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('viewer seeks without zooming; slider still drags',
        (tester) async {
      final backend = _Backend();
      backend.controller.setProgress(const Duration(seconds: 20));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => Lightbox.show(context,
                          video: _File(),
                          aspectRatio: 16 / 9,
                          videoController: backend.controller),
                      child: const Text('Open viewer'))))));
      await tester.tap(find.text('Open viewer'));
      await tester.pumpAndSettle();
      await _hide(tester);
      final rect = tester.getRect(find.byType(VideoPlayer));
      await _doubleTap(tester, Offset(rect.right - 35, rect.top + 25));
      expect(backend.seeks, [const Duration(seconds: 30)]);
      final feedback = find.text('+10 seconds');
      final paragraph = tester.renderObject<RenderParagraph>(feedback);
      final theme = Theme.of(tester.element(feedback));
      expect(paragraph.text.style!.fontFamily,
          theme.textTheme.labelMedium!.fontFamily);
      expect(paragraph.text.style!.decoration, TextDecoration.none);
      final transform = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      expect(transform.value.getMaxScaleOnAxis(), 1);
      tester.state<VideoPlayerState>(find.byType(VideoPlayer)).onHovered();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider), const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(backend.seeks.length, greaterThan(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
