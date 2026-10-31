import 'dart:async';
import 'dart:math' as math;

import 'package:commet/cache/file_provider.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/video_player/video_player.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_amoled.dart';

class _File extends Fake implements FileProvider {}

// The existing lightbox gesture fixtures only override the player's size.
class _SizeOnlyController extends VideoPlayerController {
  @override
  Future<Size?> getSize() async => const Size(640, 360);
}

void _attach(VideoPlayerController controller,
    {Future<void> Function(double)? speed}) {
  controller.attach(
      pause: () async {},
      play: () async {},
      replay: () async {},
      getLength: () async => const Duration(seconds: 30),
      getSize: () async => const Size(640, 360),
      getVolume: () async => 100,
      seekTo: (_) async {},
      setVolume: (_) async {},
      setPlaybackSpeed: speed);
}

Future<void> _pumpVideo(WidgetTester tester, VideoPlayerController controller,
    {double width = 360,
    double scale = 1,
    bool pip = false,
    ThemeData? theme}) async {
  tester.view.physicalSize = Size(width > 400 ? width + 40 : 400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: width * 9 / 16,
          child: VideoPlayer(_File(),
              controller: controller,
              canGoFullscreen: true,
              onFullscreen: () {},
              onPictureInPicture: pip ? () {} : null),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder get _button => find.byKey(const ValueKey('video_playback_speed_button'));
Finder _entry(String label) =>
    find.widgetWithText(PopupMenuItem<double>, label);

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find
        .ancestor(of: _button, matching: find.byType(AnimatedOpacity))
        .first)
    .opacity;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets('viewer route without Material supports the speed menu',
      (tester) async {
    final controller = VideoPlayerController();
    await tester.pumpWidget(MaterialApp(
      home: Center(
          child: SizedBox(
              width: 360,
              height: 203,
              child: VideoPlayer(_File(),
                  controller: controller,
                  canGoFullscreen: true,
                  onFullscreen: () {}))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    await tester.tap(_entry('1.5x'));
    await tester.pumpAndSettle();
    expect(controller.playbackSpeed, 1.5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('selection while media opens survives the post-open speed restore',
      () async {
    final controller = VideoPlayerController();
    final opened = Completer<void>();
    Future<void> backendQueue = opened.future;
    final rates = <double>[];
    var backendRate = 1.0;
    _attach(controller, speed: (rate) {
      final operation = backendQueue.then((_) {
        backendRate = rate;
        rates.add(rate);
      });
      backendQueue = operation;
      return operation;
    });
    final opening = () async {
      await opened.future;
      await controller.reapplyPlaybackSpeed();
    }();
    final selection = controller.setPlaybackSpeed(1.5);
    await Future<void>.delayed(Duration.zero);
    expect(controller.playbackSpeed, 1);
    opened.complete();
    await Future.wait([opening, selection]);
    expect(rates, [1.5, 1.5]);
    expect(backendRate, 1.5);
    expect(controller.playbackSpeed, backendRate);
  });

  test('a failed pending rate does not poison the restore or next choice',
      () async {
    final controller = VideoPlayerController();
    final rejected = Completer<void>();
    final rates = <double>[];
    _attach(controller, speed: (rate) async {
      rates.add(rate);
      if (rate == 2) await rejected.future;
    });
    final failed =
        expectLater(controller.setPlaybackSpeed(2), throwsStateError);
    final restore = controller.reapplyPlaybackSpeed();
    final selection = controller.setPlaybackSpeed(0.5);
    await Future<void>.delayed(Duration.zero);
    rejected.completeError(StateError('rate rejected'));
    await Future.wait([failed, restore, selection]);
    expect(rates, [2, 1, 0.5]);
    expect(controller.playbackSpeed, 0.5);
  });

  test('speed starts at 1x and can be chosen before a backend attaches',
      () async {
    final controller = VideoPlayerController();
    final changes = <double>[];
    final subscription = controller.onPlaybackSpeedChanged.listen(changes.add);
    expect(controller.playbackSpeed, 1);
    expect(controller.attached, isFalse);
    await controller.setPlaybackSpeed(1.5);
    await Future<void>.delayed(Duration.zero);
    expect(controller.playbackSpeed, 1.5);
    expect(changes, [1.5]);
    _attach(controller);
    expect(controller.playbackSpeed, 1.5);
    await subscription.cancel();
  });

  test('older attachments without a speed setter remain usable', () async {
    final controller = VideoPlayerController();
    controller.attach(
        pause: () async {},
        play: () async {},
        replay: () async {},
        getLength: () async => Duration.zero,
        getSize: () async => const Size(1, 1),
        getVolume: () async => 100,
        seekTo: (_) async {},
        setVolume: (_) async {});
    await controller.setPlaybackSpeed(2);
    expect(controller.playbackSpeed, 2);
    expect(controller.attached, isTrue);
  });

  test('successful changes reach the backend and notify listeners once',
      () async {
    final controller = VideoPlayerController();
    final requested = <double>[];
    final changes = <double>[];
    _attach(controller, speed: (value) async => requested.add(value));
    final subscription = controller.onPlaybackSpeedChanged.listen(changes.add);
    await controller.setPlaybackSpeed(0.5);
    await controller.setPlaybackSpeed(0.5);
    await Future<void>.delayed(Duration.zero);
    expect(requested, [0.5, 0.5]);
    expect(changes, [0.5]);
    expect(controller.playbackSpeed, 0.5);
    await subscription.cancel();
  });

  test('a failed backend change keeps the previous speed', () async {
    final controller = VideoPlayerController();
    await controller.setPlaybackSpeed(1.5);
    _attach(controller, speed: (_) async => throw StateError('rate rejected'));
    await expectLater(controller.setPlaybackSpeed(2), throwsStateError);
    expect(controller.playbackSpeed, 1.5);
  });

  test('invalid speeds never reach the backend', () async {
    final controller = VideoPlayerController();
    final requested = <double>[];
    _attach(controller, speed: (value) async => requested.add(value));
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      await expectLater(
          controller.setPlaybackSpeed(value), throwsArgumentError);
    }
    expect(requested, isEmpty);
    expect(controller.playbackSpeed, 1);
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('$kind opens the ordered menu and applies each speed',
        (tester) async {
      final controller = VideoPlayerController();
      final requested = <double>[];
      _attach(controller, speed: (value) async => requested.add(value));
      await _pumpVideo(tester, controller);
      expect(find.text('1x'), findsOneWidget);
      var selected = '1x';
      for (final (value, label) in [
        (2.0, '2x'),
        (1.5, '1.5x'),
        (1.0, '1x'),
        (0.5, '0.5x'),
      ]) {
        await tester.tap(_button, kind: kind);
        await tester.pumpAndSettle();
        expect(
            tester
                .widgetList<PopupMenuItem<double>>(
                    find.byType(PopupMenuItem<double>))
                .map((item) => item.value),
            [2, 1.5, 1, 0.5]);
        final current = _entry(selected);
        expect(find.descendant(of: current, matching: find.byIcon(Icons.check)),
            findsOneWidget);
        final selectedSemantics = tester.widget<Semantics>(find
            .descendant(
                of: current,
                matching: find.byWidgetPredicate((widget) =>
                    widget is Semantics && widget.properties.selected != null))
            .first);
        expect(selectedSemantics.properties.selected, isTrue);
        final background = tester.widget<ColoredBox>(find
            .descendant(of: current, matching: find.byType(ColoredBox))
            .first);
        expect(background.color,
            Theme.of(tester.element(_button)).colorScheme.primaryContainer);
        await tester.tap(_entry(label), kind: kind);
        await tester.pumpAndSettle();
        expect(controller.playbackSpeed, value);
        expect(find.text(label), findsOneWidget);
        expect(requested.last, value);
        selected = label;
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('AMOLED keeps the selected speed, text, and check readable',
      (tester) async {
    final controller = VideoPlayerController();
    await controller.setPlaybackSpeed(1.5);
    final theme = ThemeAmoled.theme;
    await _pumpVideo(tester, controller, theme: theme);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    final selected = _entry('1.5x');
    final background = tester
        .widget<ColoredBox>(find
            .descendant(of: selected, matching: find.byType(ColoredBox))
            .first)
        .color;
    final foreground = tester
        .widget<Text>(
            find.descendant(of: selected, matching: find.text('1.5x')))
        .style!
        .color!;
    expect(background, isNot(theme.colorScheme.surface));
    final a = background.computeLuminance();
    final b = foreground.computeLuminance();
    expect((math.max(a, b) + 0.05) / (math.min(a, b) + 0.05), greaterThan(4.5));
    final check = tester.widget<Icon>(
        find.descendant(of: selected, matching: find.byIcon(Icons.check)));
    expect(check.color, foreground);
    await tester.tap(selected);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a recreated player reads the same controller speed',
      (tester) async {
    final controller = _SizeOnlyController();
    await controller.setPlaybackSpeed(1.5);
    await _pumpVideo(tester, controller);
    expect(find.text('1.5x'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpVideo(tester, controller);
    expect(find.text('1.5x'), findsOneWidget);
  });

  for (final (width, scale) in [(160.0, 1.0), (200.0, 2.0)]) {
    testWidgets(
        'narrow toolbar $width at text scale $scale keeps PiP and speed',
        (tester) async {
      final controller = VideoPlayerController();
      await controller.setPlaybackSpeed(1.5);
      await _pumpVideo(tester, controller,
          width: width, scale: scale, pip: true);
      expect(find.text('1.5x'), findsOneWidget);
      expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
      final bounds = tester.getRect(find.byType(VideoPlayer));
      for (final control in [
        _button,
        find.byIcon(Icons.picture_in_picture_alt_rounded),
        find.byIcon(Icons.fullscreen_rounded),
      ]) {
        expect(bounds.contains(tester.getCenter(control)), isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(_entry('0.5x'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(_entry('0.5x'));
      await tester.pumpAndSettle();
      expect(controller.playbackSpeed, 0.5);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('the menu keeps controls visible after the pointer leaves video',
      (tester) async {
    final controller = VideoPlayerController();
    await _pumpVideo(tester, controller);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(_button));
    await mouse.down(tester.getCenter(_button));
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(2, 2));
    await tester.pump(const Duration(seconds: 4));
    expect(_entry('0.5x'), findsOneWidget);
    expect(_opacity(tester), 1);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(_opacity(tester), 0);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a rejected selection leaves the displayed speed unchanged',
      (tester) async {
    final controller = VideoPlayerController();
    _attach(controller, speed: (_) async => throw StateError('rate rejected'));
    await _pumpVideo(tester, controller);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    await tester.tap(_entry('2x'));
    await tester.pumpAndSettle();
    expect(find.text('1x'), findsOneWidget);
    expect(controller.playbackSpeed, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
