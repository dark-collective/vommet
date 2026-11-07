// Vommet issue 91: real picker and native media constraints, without PCM capture.
import 'dart:async';

import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/webrtc_screencapture_source.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart' show preferences;
import 'package:commet/telemetry/screenshare_audio_telemetry.dart';
import 'package:commet/ui/organisms/call_view/screen_share_audio_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const sources91 = [
  {'applicationName': 'Spotify', 'binary': 'spotify'},
  {'applicationName': 'mpv', 'binary': ''},
  {'applicationName': 'Firefox', 'binary': 'firefox'},
  {'applicationName': 'Discord', 'binary': 'discord'},
  {'applicationName': 'Vommet', 'binary': 'vommet', 'isSelf': true},
];

class _DelayedQualityStore extends InMemorySharedPreferencesStore {
  _DelayedQualityStore() : super.empty();

  final save = Completer<void>();
  bool savingQuality = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.vommet_share_quality') {
      savingQuality = true;
      await save.future;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('FlutterWebRTC.Method');
  setUpAll(() async {
    await (FontLoader('RobotoCustom')
          ..addFont(rootBundle.load('assets/font/roboto/Roboto-Regular.ttf')))
        .load();
  });
  late Future<Object?> Function() list;
  late List<MethodCall> calls;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    ScreenShareAudio.lastChoice = ScreenShareAudio.system;
    Helper.screenCaptureAudioOptions = null;
    calls = [];
    list = () async => sources91;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getLoopbackAudioSources':
          return list();
        case 'getDesktopSources':
          return {
            'sources': [
              {
                'id': 'window:91',
                'name': 'Movie',
                'type': 'window',
                'thumbnailSize': {'width': 200, 'height': 200},
              }
            ]
          };
        case 'getDisplayMedia':
          return {'streamId': 'share91', 'audioTracks': [], 'videoTracks': []};
        default:
          return null;
      }
    });
  });
  tearDown(() {
    ScreenShareAudio.lastChoice = ScreenShareAudio.system;
    Helper.screenCaptureAudioOptions = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpPicker(WidgetTester tester) async {
    var value = ScreenShareAudio.system;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
            body: Center(
          child: SizedBox(
              width: 500,
              child: StatefulBuilder(
                  builder: (context, update) => ScreenShareAudioPicker(
                      value: value,
                      onChanged: (a) {
                        value = a;
                        update(() {});
                      }))),
        ))));
    await tester.pump();
  }

  Future<void> selectMode(WidgetTester tester, String mode) async {
    final dropdown =
        find.byWidgetPredicate((w) => w is tiamat.DropdownSelector).first;
    await tester.ensureVisible(dropdown);
    await tester.pump();
    await tester.tap(dropdown);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(mode), findsWidgets);
    await tester.tap(find.text(mode).last);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> check(WidgetTester tester, String label) async {
    final row = find
        .ancestor(of: find.text(label), matching: find.byType(CheckboxListTile))
        .first;
    final scrollable = tester.state<ScrollableState>(find
        .descendant(
            of: find.byType(ScreenShareAudioPicker),
            matching: find.byType(Scrollable))
        .last);
    await scrollable.position
        .ensureVisible(tester.renderObject(row), alignment: .5);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
  }

  ScreenShareAudio choice(WidgetTester tester) => tester
      .widget<ScreenShareAudioPicker>(find.byType(ScreenShareAudioPicker))
      .value;

  testWidgets('two checked apps reach the real getDisplayMedia payload',
      (tester) async {
    await pumpPicker(tester);
    await selectMode(tester, 'Selected apps');
    await check(tester, 'Spotify');
    await check(tester, 'mpv');
    // Same bridge as MatrixLivekitVoipSession, using the pinned plugin's real
    // mediaDevices implementation. The fake boundary is the OS method call.
    Helper.screenCaptureAudioOptions = choice(tester).toCaptureOptions();
    await navigator.mediaDevices
        .getDisplayMedia({'audio': true, 'video': true});
    final constraints = (calls
        .lastWhere((c) => c.method == 'getDisplayMedia')
        .arguments as Map)['constraints'] as Map;
    expect(constraints['audio'], {
      'include': [
        {'application.name': 'mpv'},
        {'application.process.binary': 'spotify'}
      ]
    });
    expect((constraints['audio'] as Map).containsKey('exclude'), isFalse);
    expect(find.text('Vommet'), findsNothing);
    final fields = ScreenShareAudioTelemetry.fields(
        audio: choice(tester),
        audioTrack: true,
        wayland: false,
        sources: sources91,
        stats: {});
    expect(fields['mode'], 'app');
    expect(fields.containsKey('app_id'), isFalse);
    expect(fields.values, isNot(contains('spotify')));
  });

  testWidgets(
      'app identities use native case rules and selections stay independent',
      (tester) async {
    list = () async => [
          {'applicationName': 'Player', 'binary': 'Player.EXE'},
          {'applicationName': 'Player clone', 'binary': 'player.exe'},
          {'applicationName': 'Player', 'binary': 'other.exe'},
          {'applicationName': 'Player', 'binary': 'other.exe'},
        ];
    await pumpPicker(tester);
    await selectMode(tester, 'Selected apps');
    final windows = PlatformUtils.isWindows;
    final binaries = ['Player.EXE', if (!windows) 'player.exe', 'other.exe'];
    expect(find.byType(CheckboxListTile), findsNWidgets(binaries.length));
    for (final binary in binaries) {
      final row = find
          .ancestor(
              of: find.text(binary), matching: find.byType(CheckboxListTile))
          .first;
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();
    }
    final frozen = choice(tester);
    expect(frozen.toCaptureOptions(windows: false)!['include'],
        hasLength(binaries.length));
    expect(frozen.toCaptureOptions(windows: true)!['include'], hasLength(2));
    await check(tester, windows ? 'Player.EXE' : 'Player clone');
    expect(frozen.toCaptureOptions(windows: false)!['include'],
        hasLength(binaries.length));
    await check(tester, windows ? 'Player.EXE' : 'Player clone');
    expect(choice(tester), frozen);
    expect(choice(tester).hashCode, frozen.hashCode);
  });

  testWidgets(
      'empty include is safe; single/none/all and mode memory still work',
      (tester) async {
    await pumpPicker(tester);
    await selectMode(tester, 'Selected apps');
    expect(() => choice(tester).toCaptureOptions(), throwsStateError);
    expect(find.text('Select an app or choose No audio.'), findsOneWidget);
    await check(tester, 'Spotify');
    expect(
        choice(tester).toCaptureOptions(),
        const ScreenShareAudio.app(
                'application.process.binary', 'spotify', 'Spotify')
            .toCaptureOptions());
    await selectMode(tester, 'No audio');
    expect(choice(tester).toCaptureOptions(), isNull);
    await selectMode(tester, 'All apps (except voice chat apps)');
    expect(choice(tester), ScreenShareAudio.system);
    expect(choice(tester).toCaptureOptions(windows: true)!['exclude'],
        anyElement(equals({'application.process.binary': 'Discord.exe'})));
    await selectMode(tester, 'Selected apps');
    expect(choice(tester).toCaptureOptions()!['include'], hasLength(1));
    await check(tester, 'Spotify');
    expect(() => choice(tester).toCaptureOptions(), throwsStateError);
  });

  testWidgets(
      'quiet choices survive refresh/error and stale results cannot replace the list',
      (tester) async {
    await pumpPicker(tester);
    await selectMode(tester, 'Selected apps');
    await check(tester, 'Spotify');
    final old = Completer<Object?>();
    list = () => old.future;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    list = () async => [];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(find.textContaining('Not currently listed'), findsOneWidget);
    old.complete(sources91);
    await tester.pump();
    expect(find.text('Firefox'), findsNothing);
    expect(choice(tester).toCaptureOptions()!['include'], hasLength(1));
    list = () async => throw PlatformException(code: 'unavailable');
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(find.text('Could not list audio apps. Refresh to retry.'),
        findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);
    list = () async => sources91;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(find.textContaining('Not currently listed'), findsNothing);
    await check(tester, 'Discord');
    expect(
        find.textContaining("May send another call's audio"), findsOneWidget);
    expect(choice(tester).toCaptureOptions()!['include'],
        anyElement(equals({'application.process.binary': 'discord'})));
  });

  testWidgets('refresh shows progress and ignores stale and disposed errors',
      (tester) async {
    await pumpPicker(tester);
    await selectMode(tester, 'Selected apps');
    final stale = Completer<Object?>();
    list = () => stale.future;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final latest = Completer<Object?>();
    list = () => latest.future;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    stale.completeError(PlatformException(code: 'stale'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Could not list audio apps'), findsNothing);

    latest.complete(sources91);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Spotify'), findsOneWidget);

    final disposed = Completer<Object?>();
    list = () => disposed.future;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    disposed.completeError(PlatformException(code: 'disposed'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Go live commits the checked audio from before quality saves',
      (tester) async {
    final previousStore = SharedPreferencesStorePlatform.instance;
    final delayed = _DelayedQualityStore();
    SharedPreferencesStorePlatform.instance = delayed;
    addTearDown(() {
      if (!delayed.save.isCompleted) delayed.save.complete();
      SharedPreferencesStorePlatform.instance = previousStore;
    });

    ScreenCaptureSource? result;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result =
                        await WebrtcScreencaptureSource.showSelectSourcePrompt(
                            context);
                  },
                  child: const Text('Share'),
                ),
              )),
    ));
    await tester.tap(find.text('Share'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await selectMode(tester, 'Selected apps');
    await check(tester, 'Spotify');
    await tester.tap(find.text('Go live'));
    await tester.pump();
    expect(delayed.savingQuality, isTrue);
    expect(result, isNull);

    await check(tester, 'Spotify');
    expect(find.text('Select an app or choose No audio.'), findsOneWidget);
    delayed.save.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final audio = (result as WebrtcScreencaptureSource).audio;
    expect(audio.toCaptureOptions()!['include'], [
      {'application.process.binary': 'spotify'}
    ]);
    expect(ScreenShareAudio.lastChoice, audio);
  });

  testWidgets('audio-only Cancel and Continue preserve last-choice boundaries',
      (tester) async {
    ScreenShareAudio? result;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await tiamat.PopupDialog.show<ScreenShareAudio>(
                          context,
                          content: const ScreenShareAudioDialog());
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await selectMode(tester, 'Selected apps');
    expect(
        tester
            .widget<tiamat.Button>(
                find.widgetWithText(tiamat.Button, 'Continue'))
            .onTap,
        isNull);
    await check(tester, 'Spotify');
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(result, isNull);
    expect(ScreenShareAudio.lastChoice, ScreenShareAudio.system);
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await selectMode(tester, 'Selected apps');
    await check(tester, 'mpv');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(result!.toCaptureOptions()!['include'], [
      {'application.name': 'mpv'}
    ]);
    // The production source prompt, not this dialog, commits lastChoice.
    expect(ScreenShareAudio.lastChoice, ScreenShareAudio.system);
  });

  final layouts = {
    'discord': LayoutOptions.discord,
    'telegram': LayoutOptions.telegram,
    'custom': const LayoutOptions(
        oneChatList: true,
        captionBelow: false,
        limitWidth: true,
        bubbles: false,
        ownSide: OwnBubbleSide.left,
        avatarAtBottom: true)
  };
  for (final layout in layouts.entries) {
    for (final size in [const Size(1200, 900), const Size(360, 640)]) {
      testWidgets('source selection/cancel/commit at $size / ${layout.key}',
          (tester) async {
        await layout.value.save();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        ScreenCaptureSource? result;
        await tester.pumpWidget(MaterialApp(
            theme: ThemeDark.theme,
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          result = await WebrtcScreencaptureSource
                              .showSelectSourcePrompt(context);
                        },
                        child: const Text('Share'))))));
        await tester.tap(find.text('Share'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await selectMode(tester, 'Selected apps');
        expect(
            tester
                .widget<FilledButton>(find.byType(FilledButton).last)
                .onPressed,
            isNull);
        await check(tester, 'Spotify');
        expect(
            tester
                .widget<FilledButton>(find.byType(FilledButton).last)
                .onPressed,
            isNotNull);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(result, isNull);
        expect(ScreenShareAudio.lastChoice, ScreenShareAudio.system);
        await tester.tap(find.text('Share'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await selectMode(tester, 'Selected apps');
        await check(tester, 'Spotify');
        await tester.tap(find.text('Go live'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
            (result as WebrtcScreencaptureSource)
                .audio
                .toCaptureOptions()!['include'],
            [
              {'application.process.binary': 'spotify'}
            ]);
        expect(ScreenShareAudio.lastChoice,
            (result as WebrtcScreencaptureSource).audio);
      });
    }
  }
}
