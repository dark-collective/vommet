// Vommet issue 1044: the call panel under the room list folded to pictures.
import 'dart:async';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/voip/share_quality.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/call_sessions_panel.dart';
import 'package:commet/ui/molecules/talk_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  String get identifier => 'client';
  @override
  Room? getRoom(String identifier) => null;
}

class _ClientManager extends Fake implements ClientManager {
  @override
  StreamController<int> onClientAdded = StreamController.broadcast();
  @override
  StreamController<StalePeerInfo> onClientRemoved =
      StreamController.broadcast();
  @override
  late CallManager callManager = CallManager(this)..playSounds = false;
}

class _Session extends Fake implements VoipSession, ShareQualityTarget {
  _Session({this.sharing = false});
  final bool sharing;
  @override
  final Client client = _Client();
  @override
  String get sessionId => 'compact-call';
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
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get onStateChanged => changes.stream;
  final connection = StreamController<VoipState>.broadcast();
  @override
  Stream<VoipState> get onConnectionStateChanged => connection.stream;
}

const _camera = ValueKey('compact-call-camera');
const _screen = ValueKey('compact-call-screenshare');
const _noise = ValueKey('compact-call-noise');
const _hangUp = ValueKey('compact-call-hang-up');

Future<void> _pump(WidgetTester tester, double width,
    {bool sharing = false}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                  width: width,
                  child: CallSessionPanel(
                      session: _Session(sharing: sharing), compact: true))))));
  await tester.pump();
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.experimentNoiseSuppression.set(true);
  });

  testWidgets('72 px column: two controls a row, room name in the tooltip',
      (tester) async {
    await _pump(tester, 64);
    expect(tester.takeException(), isNull);
    final camera = tester.getRect(find.byKey(_camera));
    final screen = tester.getRect(find.byKey(_screen));
    final hangUp = tester.getRect(find.byKey(_hangUp));
    expect(screen.top, camera.top);
    expect(screen.left, greaterThanOrEqualTo(camera.right));
    expect(hangUp.top, greaterThan(camera.bottom));
    expect(camera.width, greaterThan(20));
    expect(find.text('Lounge', findRichText: true), findsNothing);
    expect(
        find.byWidgetPredicate(
            (w) => w is Tooltip && w.message?.contains('Lounge') == true),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with the folder strip: one row and the room name',
      (tester) async {
    await _pump(tester, 140);
    expect(tester.takeException(), isNull);
    final top = tester.getRect(find.byKey(_camera)).top;
    for (final key in [_screen, _noise, _hangUp]) {
      expect(tester.getRect(find.byKey(key)).top, top);
    }
    expect(find.textContaining('Lounge'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sharing: noise suppression and stream settings in one menu',
      (tester) async {
    await _pump(tester, 64, sharing: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_noise), findsNothing);
    final more = find.byKey(const ValueKey('compact-call-more'));
    expect(tester.getRect(more).width, greaterThan(20));
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('compact-call-more-noise')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('compact-call-more-stream')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sharing without noise suppression: a full stream settings cell',
      (tester) async {
    await preferences.experimentNoiseSuppression.set(false);
    await _pump(tester, 64, sharing: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('compact-call-more')), findsNothing);
    final gear = tester
        .getRect(find.byKey(const ValueKey('compact-call-stream-settings')));
    expect(gear.width, tester.getRect(find.byKey(_hangUp)).width);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('push to talk fills the 72 px column under the controls',
      (tester) async {
    clientManager = _ClientManager();
    addTearDown(() => clientManager = null);
    await preferences.voipPushToTalk.set(true);
    await _pump(tester, 64);
    expect(tester.takeException(), isNull);
    final talk = tester.getRect(find.byType(TalkButton));
    final camera = tester.getRect(find.byKey(_camera));
    final hangUp = tester.getRect(find.byKey(_hangUp));
    expect(talk.top, greaterThan(hangUp.bottom));
    expect(talk.left, camera.left);
    expect(talk.width, closeTo(56, 0.5));
    expect(find.text('Hold to talk'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
