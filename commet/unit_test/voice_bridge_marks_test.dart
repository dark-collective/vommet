// Vommet issue 853: voice bridge people get the plain Discord logo after
// their name in calls, and a user card that says messages don't reach them.
import 'package:commet/client/client.dart';
import 'package:commet/client/member.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/bridged_user_marker.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/atoms/voice_participant_row.dart';
import 'package:commet/ui/organisms/user_profile/user_profile_view.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Member implements Member {
  _Member(this.identifier, this.displayName);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.teal;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  _Room(this.client);
  @override
  final Client client;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const voice = "@nether-voicebridge_123456789:nether.im";
const telegram = "@telegram_123456:t2bot.io";
const plain = "@juniper:example.org";

Widget _app(Widget child) =>
    MaterialApp(home: Material(child: SizedBox(width: 220, child: child)));

final _discord = find.byWidgetPredicate(
    (w) => w is Icon && w.icon == Icons.discord && w.size != null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets("sidebar: Discord mark for a voice bridge person, kept visible",
      (tester) async {
    final room = _Room(_Client());
    await tester.pumpWidget(_app(VoiceParticipantRow(
        _Member(voice, "Kestrel ${"with a very long name " * 6}"),
        room: room)));
    expect(find.byType(BridgeNetworkIcon), findsOneWidget);
    expect(_discord, findsOneWidget);
    // Not pushed out: the whole mark lies inside the row.
    final row = tester.getRect(find.byType(VoiceParticipantRow));
    final mark = tester.getRect(find.byType(BridgeNetworkIcon));
    expect(mark.right, lessThanOrEqualTo(row.right));
    expect(mark.width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets("sidebar: no mark for a Matrix person by default",
      (tester) async {
    await tester.pumpWidget(_app(VoiceParticipantRow(_Member(plain, "Juniper"),
        room: _Room(_Client()))));
    expect(find.byType(BridgeNetworkIcon), findsNothing);
    expect(find.byType(UnverifiedNetworkIcon), findsNothing);
    expect(find.byType(MatrixMark), findsNothing);
  });

  testWidgets("sidebar and call tile: no mark while names are redacted",
      (tester) async {
    await tester.pumpWidget(_app(RedactionScope.withSettings(
        settings: const RedactionSettings(names: NameRedaction.hide),
        child: Column(children: [
          VoiceParticipantRow(_Member(voice, "Kestrel"),
              room: _Room(_Client())),
          BridgedUserMarker(
              client: _Client(), userId: voice, size: 12, inCall: true),
        ]))));
    expect(find.byType(BridgeNetworkIcon), findsNothing);
    expect(find.byType(UnverifiedNetworkIcon), findsNothing);
    expect(find.byType(MatrixMark), findsNothing);
  });

  testWidgets("sidebar: no mark with the master switch off", (tester) async {
    await BridgedUsers.mark.set(false);
    await tester.pumpWidget(_app(VoiceParticipantRow(_Member(voice, "Kestrel"),
        room: _Room(_Client()))));
    expect(find.byType(BridgeNetworkIcon), findsNothing);
    expect(find.byType(UnverifiedNetworkIcon), findsNothing);
  });

  Widget card(String userId, String name) {
    final client = _Client();
    final isVoice =
        BridgedUsers.of(client, userId, ignoreSetting: true)?.network ==
            BridgeNetwork.voiceBridge;
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UserProfileView(
            displayName: name,
            identifier: userId,
            clientId: "test",
            userColor: Colors.teal,
            doSafeArea: false,
            isSelf: false,
            onMessageButtonClicked: () async {},
            bridgedChip:
                BridgedUserChip(client: client, userId: userId, name: name),
            cantMessageReason: isVoice ? bridgedVoiceOnlyExplained(name) : null,
          ),
        ),
      ),
    );
  }

  testWidgets("card: voice bridge person can't be messaged", (tester) async {
    await tester.pumpWidget(card(voice, "Kestrel"));
    await tester.pumpAndSettle();
    expect(find.text("Discord · voice only"), findsOneWidget);
    expect(
        find.text("Kestrel is in the call from Discord. They hear you and "
            "you hear them, but messages here don't reach them."),
        findsOneWidget);
    final button = tester.widget<OutlinedButton>(find.descendant(
        of: find.byKey(const ValueKey("userProfileCantMessage")),
        matching: find.byType(OutlinedButton),
        matchRoot: true));
    expect(button.onPressed, isNull);
    expect(find.text("Can't message them"), findsOneWidget);
  });

  testWidgets("card: a Telegram person keeps the message button",
      (tester) async {
    await tester.pumpWidget(card(telegram, "Robin"));
    await tester.pumpAndSettle();
    expect(find.text("Can't message them"), findsNothing);
    expect(find.text("Discord · voice only"), findsNothing);
    expect(find.text("Message"), findsOneWidget);
  });
}
