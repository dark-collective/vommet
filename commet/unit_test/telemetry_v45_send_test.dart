// Vommet telemetry schema v45: op=send through the real chat. The room is a
// real MatrixRoom on the stub homeserver (roomlist_fixture.dart), so the SDK's
// own Room.sendFileEvent uploads and sends (matrix sdk lib/src/room.dart: a
// MatrixException from uploadContent is rethrown, around line 1004).
import 'dart:convert';

import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/voice_message_telemetry.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';

const plain = "!plain:example.com";
const secret = "!secret:example.com";

http.Response json(int status, Object body) =>
    http.Response(jsonEncode(body), status,
        headers: {"content-type": "application/json"});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  final recorded = <Map<String, Object?>>[];
  final recording = VoiceRecording(
      bytes: Uint8List(1200),
      format: VoiceFormat.oggOpus,
      duration: const Duration(seconds: 3),
      waveform: const [0, 300, 700, 120]);
  var n = 0;
  var uploadFails = false;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await UnicodeEmojis.load();
    uploadFails = false;
    stubResponse = (request) {
      if (!request.url.path.endsWith("/upload")) return null;
      return uploadFails
          ? json(403, {"errcode": "M_FORBIDDEN", "error": "secret text"})
          : json(200, {"content_uri": "mxc://example.com/voice"});
    };
    client = await signedInClient("voice-send-${n++}");
    client.self = MatrixProfile(client, matrix.Profile(userId: me));
    clientManager = ClientManager();
    await sync(client, join: {
      plain: matrix.JoinedRoomUpdate(state: roomState(plain)),
      secret: matrix.JoinedRoomUpdate(state: [
        ...roomState(secret),
        stateEvent("m.room.encryption", {"algorithm": "m.megolm.v1.aes-sha2"}),
      ]),
    });
    recorded.clear();
    VoiceMessageTelemetry.enabled = () => true;
    VoiceMessageTelemetry.record = (e, f) => recorded.add({"e": e, ...f});
  });

  tearDown(() async {
    VoiceMessageTelemetry.enabled = () => false;
    stubResponse = null;
    clientManager = null;
    await client.getMatrixClient().dispose(closeDatabase: true);
  });

  List<Map<String, Object?>> events() =>
      recorded.where((e) => e["op"] == "send").toList();

  Future<bool> send(WidgetTester tester, String room,
      {MatrixClient? overrideClient}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: SizedBox.expand(child: Chat(client.getRoom(room)!))),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    final state = tester.state<ChatState>(find.byType(Chat));
    late bool sent;
    await tester.runAsync(() async {
      sent = await state.sendVoiceMessage(recording,
          overrideClient: overrideClient);
    });
    await tester.pump();
    return sent;
  }

  // The SDK's member lookups leave a one-minute timer, the message box its
  // keyboard height timers.
  Future<void> finish(WidgetTester tester) async {
    final error = tester.takeException();
    expect(error == null || error is MissingPluginException, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  testWidgets("sent: one ok with ms, bytes and encrypted", (tester) async {
    expect(await send(tester, plain), isTrue);
    expect(events(), hasLength(1));
    final e = events().single;
    expect(e["outcome"], "ok");
    expect(e["bytes"], 1200);
    expect(e["ms"], isA<int>());
    expect(e["encrypted"], isFalse);
    await finish(tester);
  });

  testWidgets("upload refused: one send_failed with the errcode, encrypted",
      (tester) async {
    uploadFails = true;
    expect(await send(tester, secret), isFalse);
    expect(events(), hasLength(1));
    final e = events().single;
    expect(e["outcome"], "error");
    expect(e["reason"], "send_failed");
    expect(e["errcode"], "M_FORBIDDEN");
    expect(e["encrypted"], isTrue);
    expect(e.values.join(" "), isNot(contains("secret text")));
    await finish(tester);
  });

  testWidgets("override client without the room: one no_room", (tester) async {
    late MatrixClient other;
    await tester.runAsync(() async {
      other = await signedInClient("voice-send-other-${n++}");
    });
    addTearDown(() => other.getMatrixClient().dispose(closeDatabase: true));
    expect(await send(tester, plain, overrideClient: other), isFalse);
    expect(events(), hasLength(1));
    expect(events().single["outcome"], "error");
    expect(events().single["reason"], "no_room");
    expect(events().single["bytes"], 1200);
    await finish(tester);
  });
}
