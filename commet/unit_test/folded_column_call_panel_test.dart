// Vommet issue 1044: in a call, the call panel under the One list chat list
// folded to pictures ("Show chat pictures only") squished its icons into
// each other. The folded column is UnifiedDesktopFit.avatarWidth (72 px)
// wide, plus the folder strip when folders are shown. This pumps what the
// folded column holds at its bottom (unified_main_page.dart navigation:
// Tile.low > ScaledSafeArea > CurrentSessionPanel(compact: true)) with the
// app's real preferences, so the call panel takes the path users get (the
// call cards experiment graduated and is always on).
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/voip/share_quality.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/layout/unified_desktop_layout.dart';
import 'package:commet/ui/molecules/call_sessions_panel.dart';
import 'package:commet/ui/molecules/current_session_panel.dart';
import 'package:commet/ui/molecules/self_voice_controls.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Client extends Fake implements Client {
  @override
  String get identifier => 'client';
  @override
  Room? getRoom(String identifier) => null;
  @override
  List<Space> get spaces => const [];
  @override
  Profile? get self => null;
}

class _Session extends Fake implements VoipSession, ShareQualityTarget {
  _Session({required this.sharing});
  final bool sharing;
  @override
  final Client client = _Client();
  @override
  String get sessionId => 'folded-call';
  @override
  String get roomId => '!lounge:example.org';
  @override
  String get roomName => 'Lounge';
  @override
  VoipState get state => VoipState.connected;
  @override
  bool get isCameraEnabled => false;
  @override
  bool get isSharingScreen => sharing;
  @override
  bool get supportsScreenshare => true;
  @override
  bool get isMicrophoneMuted => false;
  @override
  Future<void> setMicrophoneMute(bool state) async {}
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get onStateChanged => changes.stream;
  final connection = StreamController<VoipState>.broadcast();
  @override
  Stream<VoipState> get onConnectionStateChanged => connection.stream;
}

/// The folded column's width: the 72 px picture column, plus the folder
/// strip and its divider when folders are on.
const double foldedWidth = UnifiedDesktopFit.avatarWidth;
const double foldedWithFolders =
    UnifiedDesktopFit.avatarWidth + FolderStrip.width + 1;

/// Pumps the bottom of the folded column in a call, inside a RepaintBoundary
/// keyed "folded-column".
Future<void> pumpFoldedCall(WidgetTester tester,
    {double width = foldedWidth,
    bool pushToTalk = false,
    bool sharing = false,
    bool noiseSuppression = true}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'vommet_now_playing': false});
  await app.preferences.init();
  await app.preferences.layoutOverride.set('desktop');
  await app.preferences.experimentNoiseSuppression.set(noiseSuppression);
  await app.preferences.voipPushToTalk.set(pushToTalk);
  final previous = app.clientManager;
  final manager = ClientManager()..callManager.playSounds = false;
  app.clientManager = manager;
  manager.callManager.currentSessions.add(_Session(sharing: sharing));
  addTearDown(() {
    manager.callManager.currentSessions.clear();
    app.clientManager = previous;
  });
  tester.view.physicalSize = const Size(400, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
          body: Align(
              alignment: Alignment.bottomLeft,
              child: RepaintBoundary(
                  key: const ValueKey('folded-column'),
                  child: SizedBox(
                      width: width,
                      child: const Tile.low(
                          caulkPadTop: true,
                          caulkClipTopRight: true,
                          caulkBorderTop: true,
                          child: ScaledSafeArea(
                              top: false,
                              child: CurrentSessionPanel(compact: true)))))))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The rectangles of the icons under [of]: the call panel's, or the whole
/// account panel's (with your mic and headphones, SelfVoiceControls).
List<Rect> iconsIn(WidgetTester tester, Finder of) => [
      for (final e
          in find.descendant(of: of, matching: find.byType(Icon)).evaluate())
        if (e.renderObject case final RenderBox box)
          box.localToGlobal(Offset.zero) & box.size
    ];

/// No icon of the folded column's bottom panel (the call panel, your
/// picture, the bell, mic and headphones, settings) overlaps another or
/// sticks out of the column.
void expectFits(WidgetTester tester, double width) {
  expect(tester.takeException(), isNull);
  final call = tester.getRect(find.byType(CallSessionsPanel));
  expect(call.width, lessThanOrEqualTo(width));
  expect(iconsIn(tester, find.byType(CallSessionsPanel)).length,
      greaterThanOrEqualTo(4));
  final panel = tester.getRect(find.byKey(const ValueKey('folded-column')));
  final icons = iconsIn(tester, find.byType(CurrentSessionPanel));
  // Your own mute and deafen are there too.
  expect(
      find.descendant(
          of: find.byType(SelfVoiceControls),
          matching: find.byIcon(Icons.mic_rounded)),
      findsOneWidget);
  expect(
      find.descendant(
          of: find.byType(SelfVoiceControls),
          matching: find.byIcon(Icons.headset_rounded)),
      findsOneWidget);
  for (final icon in icons) {
    expect(icon.left, greaterThanOrEqualTo(panel.left - 0.5),
        reason: 'icon at $icon sticks out of the panel $panel');
    expect(icon.right, lessThanOrEqualTo(panel.right + 0.5),
        reason: 'icon at $icon sticks out of the panel $panel');
  }
  for (var i = 0; i < icons.length; i++) {
    for (var j = i + 1; j < icons.length; j++) {
      final overlap = icons[i].intersect(icons[j]);
      expect(overlap.width > 0.5 && overlap.height > 0.5, isFalse,
          reason: 'icons ${icons[i]} and ${icons[j]} overlap');
    }
  }
}

void main() {
  group('call panel in the folded One list column (Vommet issue 1044)', () {
    for (final (name, width) in [
      ('72 px column', foldedWidth),
      ('with the folder strip', foldedWithFolders),
    ]) {
      testWidgets('$name: in a call, no icon overlaps or sticks out',
          (tester) async {
        await pumpFoldedCall(tester, width: width);
        expectFits(tester, width);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('$name: push to talk on', (tester) async {
        await pumpFoldedCall(tester, width: width, pushToTalk: true);
        expectFits(tester, width);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('$name: sharing the screen, noise suppression on',
          (tester) async {
        await pumpFoldedCall(tester, width: width, sharing: true);
        expectFits(tester, width);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('$name: sharing the screen, noise suppression off',
          (tester) async {
        await pumpFoldedCall(tester,
            width: width, sharing: true, noiseSuppression: false);
        expectFits(tester, width);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('hang up and the call timer stay reachable at 72 px',
        (tester) async {
      await pumpFoldedCall(tester);
      expect(tester.takeException(), isNull);
      expect(
          find.descendant(
              of: find.byType(CallSessionsPanel),
              matching: find.byIcon(Icons.call_end_rounded)),
          findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is Tooltip && w.message?.contains('Lounge') == true),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
