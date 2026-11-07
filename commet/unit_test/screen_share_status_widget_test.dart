import 'package:commet/client/client_manager.dart';
import 'package:commet/client/call_manager.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/utils/notifying_list.dart';
import 'dart:async';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/voip/screen_share_status.dart';
import 'package:commet/client/member.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/screen_share_status.dart';
import 'package:commet/ui/atoms/voice_participant_row.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StatusClient extends Fake implements Client {
  @override
  T? getComponent<T extends Component>() => null;
}

class StatusMember extends Fake implements Member {
  StatusMember(this.identifier, this.displayName);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  ImageProvider? get avatar => null;
  @override
  ImageProvider? get largeAvatar => null;
  @override
  Color get defaultColor => Colors.teal;
}

class StatusProvider extends Fake implements ScreenShareStatus {
  final changes = StreamController<void>.broadcast();
  Map<String, int> reports = {};
  @override
  Map<String, int> get screenShares => reports;
  @override
  Stream<void> get onScreenSharesChanged => changes.stream;
}

class StatusRoom extends Fake implements Room {
  final status = StatusProvider();
  @override
  final Client client = StatusClient();
  @override
  String get identifier => '!fixture:example.org';
  @override
  T? getComponent<T extends RoomComponent>() =>
      status is T ? status as T : null;
}

class _Manager extends Fake implements ClientManager {
  @override
  final CallManager callManager = _Calls();
}

class _Calls extends Fake implements CallManager {
  @override
  final NotifyingList<VoipSession> currentSessions =
      NotifyingList.empty(growable: true);
}

class _Session extends Fake implements VoipSession {
  _Session(this.client);
  @override
  final Client client;
  @override
  String get roomId => '!fixture:example.org';
  @override
  VoipState get state => VoipState.connected;
  @override
  List<VoipStream> streams = [];
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get onStateChanged => changes.stream;
}

class _Share extends Fake implements VoipStream {
  @override
  VoipStreamType get type => VoipStreamType.screenshare;
  @override
  String get streamUserId => '@alex:example.org';
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await ScreenShareStatus.experiment.set(true);
  });
  testWidgets(
      'passive badge appears, clears on sync and honors the experiment live',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final room = StatusRoom();
      final member = StatusMember('@alex:example.org', 'Alex Rivera');
      room.status.reports = {
        member.identifier: DateTime.now().millisecondsSinceEpoch + 60000
      };
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 280,
                  child: VoiceParticipantRow(member, room: room)))));
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.byTooltip(VoiceParticipantRow.voiceRowWatchTooltip),
          findsNothing);
      expect(find.bySemanticsLabel('Alex Rivera: screen sharing reported'),
          findsOneWidget);
      room.status.reports.clear();
      room.status.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsNothing);
      room.status.reports = {
        member.identifier: DateTime.now().millisecondsSinceEpoch + 60000
      };
      room.status.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsOneWidget);
      await ScreenShareStatus.experiment.set(false);
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsNothing);
      await ScreenShareStatus.experiment.set(true);
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await room.status.changes.close();
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
      'expiry removes badges without sync and large text fits the participant row',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final room = StatusRoom();
      final now = DateTime.now().millisecondsSinceEpoch;
      room.status.reports = {'@alex:example.org': now + 500};
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                  body: SizedBox(
                      width: 240,
                      child: VoiceParticipantRow(
                          StatusMember('@alex:example.org',
                              'Alex Rivera with a long name'),
                          room: room))))));
      expect(find.text('LIVE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('LIVE'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await room.status.changes.close();
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('redacted names do not leak through badge semantics or tooltip',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final room = StatusRoom();
      room.status.reports = {
        '@alex:example.org': DateTime.now().millisecondsSinceEpoch + 60000
      };
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RedactionScope.withSettings(
                  settings: const RedactionSettings(names: NameRedaction.hide),
                  child: VoiceParticipantRow(
                      StatusMember('@alex:example.org', 'Alex Rivera'),
                      room: room)))));
      expect(find.bySemanticsLabel(RegExp('.*Alex Rivera.*')), findsNothing);
      expect(
          find.byWidgetPredicate((w) =>
              w is Tooltip && w.message?.contains('Alex Rivera') == true),
          findsNothing);
      expect(find.text('LIVE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await room.status.changes.close();
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
      'an already-joined call uses observed tracks, even when reports disagree',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final room = StatusRoom();
      room.status.reports = {
        '@alex:example.org': DateTime.now().millisecondsSinceEpoch + 60000
      };
      final before = clientManager;
      final manager = _Manager();
      clientManager = manager;
      final session = _Session(room.client);
      manager.callManager.currentSessions.add(session);
      addTearDown(() {
        clientManager = before;
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ScreenShareReportsBuilder(
                  room: room,
                  builder: (context, shares) =>
                      Text('shares: ${shares.length}')))));
      expect(find.text('shares: 0'), findsOneWidget);
      session.streams.add(_Share());
      session.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('shares: 1'), findsOneWidget);
      session.streams.clear();
      session.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('shares: 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await session.changes.close();
      await room.status.changes.close();
      manager.callManager.currentSessions.close();
    } finally {
      semantics.dispose();
    }
  });
}
