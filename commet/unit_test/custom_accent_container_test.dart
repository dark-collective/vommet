import 'dart:async';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/theme_draft.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/call_card.dart';
import 'package:commet/ui/molecules/call_sessions_panel.dart';
import 'package:commet/ui/molecules/ongoing_call_strip.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/config.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';

const customAccent = Color(0xff38d9a9);

class ThemeCallClient extends Fake implements Client {
  @override
  Room? getRoom(String id) => null;
  @override
  List<Space> get spaces => [];
  @override
  Profile? get self => null;
}

class ThemeCallSession extends Fake implements VoipSession {
  final changed = StreamController<void>.broadcast(sync: true);
  @override
  final Client client = ThemeCallClient();
  @override
  String get sessionId => 'custom-theme-call';
  @override
  String get roomId => '!design:example.org';
  @override
  String get roomName => 'Design room';
  @override
  VoipState get state => VoipState.connected;
  @override
  Stream<void> get onStateChanged => changed.stream;
  @override
  Stream<VoipState> get onConnectionStateChanged => const Stream.empty();
  @override
  bool isCameraEnabled = true;
  @override
  bool isSharingScreen = true;
  @override
  bool get supportsScreenshare => true;
  @override
  Future<void> stopCamera() async {
    isCameraEnabled = false;
    changed.add(null);
  }

  @override
  Future<void> stopScreenshare() async {
    isSharingScreen = false;
    changed.add(null);
  }
}

class ThemeCalls extends Fake implements CallManager {
  ThemeCalls(this.focusedCall) {
    currentSessions.add(focusedCall!);
  }
  @override
  final VoipSession? focusedCall;
  @override
  final currentSessions = NotifyingList<VoipSession>.empty(growable: true);
  @override
  Stream<void> get onSelfAudioChanged => const Stream.empty();
  @override
  bool isMutedIn(VoipSession session) => false;
  @override
  bool isDeafenedIn(VoipSession session) => false;
}

class ThemeCallManager extends Fake implements ClientManager {
  ThemeCallManager(VoipSession session) : callManager = ThemeCalls(session);
  @override
  final CallManager callManager;
  @override
  final clients = NotifyingList<Client>.empty(growable: true);
}

Future<ThemeData> accentTheme(ThemeData base) async {
  final draft = ThemeDraft.fromTheme(base, 'Custom mint');
  draft.colors['primary'] = customAccent;
  return (await ThemeJsonConverter.fromJson(draft.toJson(), null))!;
}

Future<ThemeData> loadScheme(
  Map<String, dynamic> scheme, {
  String base = 'dark',
}) async =>
    (await ThemeJsonConverter.fromJson({
      'base': base,
      'colorScheme': scheme,
    }, null))!;

double contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => <String>['wifi'],
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(
        onListen: (_, sink) => sink.success(<String>['wifi']),
      ),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  for (final (name, base) in [
    ('dark', ThemeDark.theme),
    ('light', ThemeLight.theme),
    ('AMOLED', ThemeAmoled.theme),
  ]) {
    test('editor accent reaches missing containers on $name', () async {
      final theme = await accentTheme(base);
      expect(theme.colorScheme.primary, customAccent);
      expect(theme.colorScheme.primaryContainer, customAccent);
      expect(theme.colorScheme.onPrimaryContainer, Colors.black);
      expect(
        contrast(
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  for (final color in [
    '#000000',
    '#ffffff',
    '#160b50',
    '#ffcc00',
    '#777777',
    '#808080',
  ]) {
    test('missing container foreground is readable on $color', () async {
      final s = (await loadScheme({'primary': color})).colorScheme;
      expect(
        contrast(s.primaryContainer, s.onPrimaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  test('accent fallback retains neutral and disabled theme colors', () async {
    final theme = await loadScheme({'primary': '#38d9a9'});
    final base = ThemeDark.theme;
    expect(theme.disabledColor, base.disabledColor);
    expect(theme.colorScheme.onSurface, base.colorScheme.onSurface);
    expect(theme.colorScheme.surfaceContainerHighest,
        base.colorScheme.surfaceContainerHighest);
  });

  test('explicit container pair wins over a different accent', () async {
    final s = (await loadScheme({
      'primary': '#38d9a9',
      'primaryContainer': '#793da6',
      'onPrimaryContainer': '#ffffff',
    }))
        .colorScheme;
    expect(s.primaryContainer, const Color(0xff793da6));
    expect(s.onPrimaryContainer, Colors.white);
  });
  test('explicit foreground survives the missing-fill fallback', () async {
    final s = (await loadScheme({
      'primary': '#38d9a9',
      'onPrimaryContainer': '#123456',
    }))
        .colorScheme;
    expect(s.primaryContainer, customAccent);
    expect(s.onPrimaryContainer, const Color(0xff123456));
  });
  test('an explicit fill alone retains its inherited foreground', () async {
    final s = (await loadScheme({
      'primary': '#38d9a9',
      'primaryContainer': '#793da6',
    }))
        .colorScheme;
    expect(s.primaryContainer, const Color(0xff793da6));
    expect(
      s.onPrimaryContainer,
      ThemeDark.theme.colorScheme.onPrimaryContainer,
    );
  });
  for (final base in ['dark', 'light']) {
    test('no accent override preserves the $base base containers', () async {
      final expected = base == 'dark' ? ThemeDark.theme : ThemeLight.theme;
      expect(
        (await loadScheme({}, base: base)).colorScheme,
        expected.colorScheme,
      );
    });
    test('seed palettes retain their container pair on $base', () async {
      final seed = await loadScheme({'seed': '#ef7b25'}, base: base);
      final override = await loadScheme({
        'seed': '#ef7b25',
        'primary': '#38d9a9',
      }, base: base);
      expect(override.colorScheme.primary, customAccent);
      expect(
        override.colorScheme.primaryContainer,
        seed.colorScheme.primaryContainer,
      );
      expect(
        override.colorScheme.onPrimaryContainer,
        seed.colorScheme.onPrimaryContainer,
      );
    });
  }

  for (final (layout, options) in [
    ('Discord', LayoutOptions.discord),
    ('Telegram', LayoutOptions.telegram),
    (
      'Custom split',
      const LayoutOptions(
        oneChatList: false,
        captionBelow: true,
        limitWidth: true,
        bubbles: true,
        ownSide: OwnBubbleSide.left,
        avatarAtBottom: false,
      ),
    ),
    (
      'Custom unified',
      const LayoutOptions(
        oneChatList: true,
        captionBelow: false,
        limitWidth: false,
        bubbles: false,
        ownSide: OwnBubbleSide.right,
        avatarAtBottom: true,
      ),
    ),
  ]) {
    for (final (name, base) in [
      ('dark', ThemeDark.theme),
      ('light', ThemeLight.theme),
      ('AMOLED', ThemeAmoled.theme),
    ]) {
      for (final phone in [true, false]) {
        testWidgets(
          '$layout $name ${phone ? 'phone large text' : 'desktop'} controls use the loaded accent',
          (tester) async {
            await options.save();
            await layoutStyleCustomPicked.set(layout.startsWith('Custom'));
            final size = Size(phone ? 360 : 1200, 800);
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final theme = await accentTheme(base);
            for (final kind in ['panel', 'card', 'strip']) {
              final session = ThemeCallSession();
              clientManager = ThemeCallManager(session);
              final child = switch (kind) {
                'panel' => CallSessionPanel(session: session),
                'card' => CallCard(session: session),
                _ => const OngoingCallStrip(),
              };
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(phone ? 1.5 : 1),
                    ),
                    child: Scaffold(
                      body: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(width: phone ? 360 : 320, child: child),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump();
              for (final icon in [
                Icons.videocam_rounded,
                if (kind != 'strip') Icons.stop_screen_share_rounded,
              ]) {
                final finder = find.byIcon(icon);
                expect(finder, findsOneWidget, reason: kind);
                expect(tester.widget<Icon>(finder).color, Colors.black);
                expect(
                  tester
                      .element(finder)
                      .findAncestorWidgetOfExactType<Material>()!
                      .color,
                  customAccent,
                );
                await tester.tap(finder);
                await tester.pump();
              }
              expect(session.isCameraEnabled, isFalse);
              if (kind != 'strip') expect(session.isSharingScreen, isFalse);
              final inactive = find.byIcon(Icons.videocam_off_rounded);
              expect(
                tester.widget<Icon>(inactive).color,
                theme.colorScheme.onSurface,
              );
              expect(
                tester
                    .element(inactive)
                    .findAncestorWidgetOfExactType<Material>()!
                    .color,
                theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
              );
              expect(tester.takeException(), isNull, reason: kind);
              await tester.pumpWidget(const SizedBox());
              await tester.pump();
              await session.changed.close();
            }
            clientManager = null;
          },
        );
      }
    }
  }
}
