import 'dart:async';
import 'dart:io';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/lightbox_full_screen.dart';
import 'package:commet/ui/molecules/video_player/video_player.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/slider.dart' as tiamat;
import 'package:tiamat/config/style/theme_dark.dart';

class _File extends Fake implements FileProvider {
  int reads = 0;
  bool fail = false;
  @override
  Stream<DownloadProgress>? get onProgressChanged => null;
  @override
  Future<Uint8List?> getFileData() async {
    reads++;
    if (fail) throw const FileSystemException('Unavailable');
    return Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112]);
  }
}

class _Controller extends VideoPlayerController {
  @override
  Future<Size?> getSize() async => const Size(640, 360);
}

class _Picker extends FilePicker {
  int calls = 0;
  String? name;
  Future<String?> Function()? pick;
  @override
  Future<String?> saveFile(
      {String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow = false}) async {
    calls++;
    name = fileName;
    return pick?.call();
  }
}

final _save = find.byTooltip('Save video');
final _menu = find.byKey(const ValueKey('lightbox_menu_button'));
final _navigator = GlobalKey<NavigatorState>();

Future<void> _open(WidgetTester tester, _File file,
    {Size size = const Size(640, 900),
    double scale = 1,
    GlobalKey<VideoPlayerState>? playerKey,
    VideoPlayerController? controller}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
    navigatorKey: _navigator,
    theme: ThemeDark.theme,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Builder(
        builder: (context) => TextButton(
            child: const Text('Open'),
            onPressed: () => Lightbox.show(context,
                video: file,
                videoController: controller ?? _Controller(),
                key: playerKey,
                fileName: 'clip.mp4',
                onPictureInPicture: () {}))),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  late _Picker picker;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.experimentLightboxGallery.set(false);
    await preferences.layoutOverride.set('mobile');
    await preferences.autoRotateVideos.set(false);
    picker = _Picker();
    FilePicker.platform = picker;
    backgroundTaskManager = BackgroundTaskManager();
    LightboxSystemBars.supported = () => true;
    LightboxSystemBars.setHidden = (_) async {};
    LightboxFullScreen.isWindowFullScreen = () async => false;
    LightboxFullScreen.setWindowFullScreen = (_) async {};
  });
  tearDown(() async {
    LightboxFullScreen.exit();
    LightboxSystemBars.supported = () => false;
    for (final subscription in backgroundTaskManager.subscriptions.values) {
      await subscription.cancel();
    }
  });

  for (final style in LayoutStyle.values) {
    testWidgets(
        '${style.name}: narrow/large text and rotated fullscreen retain Save',
        (tester) async {
      addTearDown(tester.view.reset);
      await pickLayoutStyle(style);
      for (final unified in [false, true]) {
        await experimentUnifiedChatList.set(unified);
        await _open(tester, _File(),
            size: Size(BuildConfig.MOBILE ? 320 : 520, 700), scale: 2);
        expect(_save, findsOneWidget);
        expect(_menu, findsOneWidget);
        final target = tester.getSize(_save);
        expect(target.shortestSide, greaterThanOrEqualTo(48));
        final player = find.byType(VideoPlayer);
        final slider =
            find.descendant(of: player, matching: find.byType(tiamat.Slider));
        expect(tester.getTopLeft(slider).dy,
            lessThan(tester.getTopLeft(_save).dy));
        expect(tester.getSize(slider).width, greaterThan(260));
        expect(
            tester.getTopLeft(_save).dx -
                tester.getTopLeft(find.byTooltip('Mute')).dx,
            48);
        await tester.tap(find.byTooltip('Playback speed'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1.5x'));
        await tester.pumpAndSettle();
        expect(tester.state<VideoPlayerState>(player).controller.playbackSpeed,
            1.5);
        await tester.tap(find.byTooltip('Fullscreen'));
        await tester.pumpAndSettle();
        expect(_menu, findsNothing);
        expect(_save, findsOneWidget);
        tester.view.physicalSize = const Size(700, 320);
        await tester.pumpAndSettle();
        expect(_save, findsOneWidget);
        expect(tester.getTopLeft(slider).dy,
            greaterThan(tester.getTopLeft(_save).dy - 5));
        expect(find.byTooltip('Playback speed'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('video_seek_forward')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets(
      'desktop shortcut and menu share one save; busy controls stay visible',
      (tester) async {
    addTearDown(tester.view.reset);
    await preferences.layoutOverride.set('desktop');
    LightboxSystemBars.supported = () => false;
    final file = _File();
    final pending = Completer<String?>();
    picker.pick = () => pending.future;
    await _open(tester, file);
    expect(_save, findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(tester.getSemantics(_save).getSemanticsData().tooltip, 'Save video');
    await tester.tap(_save);
    await tester.pump();
    expect(picker.calls, 1);
    expect(picker.name, 'clip.mp4');
    final busy = find.byTooltip('Saving video');
    expect(
        tester
            .widget<IconButton>(find
                .ancestor(of: busy, matching: find.byType(IconButton))
                .first)
            .onPressed,
        isNull);
    await tester.tap(busy);
    tester.state<VideoPlayerState>(find.byType(VideoPlayer)).onUnhovered();
    await tester.pump(const Duration(seconds: 4));
    expect(
        tester
            .state<VideoPlayerState>(find.byType(VideoPlayer))
            .shouldShowControls,
        isTrue);
    await tester.tap(_menu);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Save as…'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(picker.calls, 1);
    expect(file.reads, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(_save, findsOneWidget);
    expect(backgroundTaskManager.tasks, isEmpty);
    // A canceled picker releases the guard; a later user request works.
    picker.pick = () async => null;
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(picker.calls, 2);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'fullscreen save writes chosen desktop file and reports failures over viewer',
      (tester) async {
    addTearDown(tester.view.reset);
    await preferences.layoutOverride.set('desktop');
    LightboxSystemBars.supported = () => false;
    final file = _File()..fail = true;
    await _open(tester, file);
    expect(_save, findsOneWidget);
    LightboxFullScreen.enter();
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Error'), findsOneWidget);
    expect(picker.calls, 0);
    _navigator.currentState!.pop();
    await tester.pumpAndSettle();
    file.fail = false;
    final directory = await tester
        .runAsync(() => Directory.systemTemp.createTemp('viewer-save-'));
    final path = '${directory!.path}/clip.mp4';
    picker.pick = () async => path;
    await tester.tap(_save);
    for (var i = 0;
        i < 100 &&
            backgroundTaskManager.tasks.last.status !=
                BackgroundTaskStatus.completed;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(backgroundTaskManager.tasks.last.status,
        BackgroundTaskStatus.completed);
    await tester.runAsync(() async {
      expect(await File(path).readAsBytes(), [0, 0, 0, 24, 102, 116, 121, 112]);
      await directory.delete(recursive: true);
    });
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(_save, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing viewer during save does not update disposed controls',
      (tester) async {
    addTearDown(tester.view.reset);
    final pending = Completer<String?>();
    picker.pick = () => pending.future;
    await _open(tester, _File());
    expect(_save, findsOneWidget);
    await tester.tap(_save);
    await tester.pump();
    expect(picker.calls, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saving capability belongs to viewer; timeline and PiP keep old controls',
      (tester) async {
    addTearDown(tester.view.reset);
    final file = _File();
    final pending = Completer<String?>();
    picker.pick = () => pending.future;
    final key = GlobalKey<VideoPlayerState>();
    final controller = _Controller();
    await _open(tester, file, playerKey: key, controller: controller);
    expect(_save, findsOneWidget);
    expect(file.reads, 0);
    Focus.of(tester.element(_save)).requestFocus();
    await tester.pump();
    double opacity() => tester
        .widget<AnimatedOpacity>(find
            .ancestor(
                of: find.byTooltip('Playback speed'),
                matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;
    final state = key.currentState!;
    await tester.tap(_save);
    await tester.pump();
    state.onUnhovered();
    await tester.pump();
    expect(opacity(), 1);
    for (final pip in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox(
                  width: 320,
                  height: 180,
                  child: VideoPlayer(file,
                      key: key,
                      controller: controller,
                      isPictureInPicture: pip,
                      canGoFullscreen: true,
                      onFullscreen: () {})))));
      await tester.pumpAndSettle();
      expect(identical(key.currentState, state), isTrue);
      state.onUnhovered();
      await tester.pump();
      expect(opacity(), 0);
      if (!pip) {
        pending.complete(null);
        await tester.pumpAndSettle();
        expect(opacity(), 0);
      }
      expect(_save, findsNothing);
      expect(find.byTooltip('Playback speed'), findsOneWidget);
      expect(file.reads, 1);
    }
  });
}
