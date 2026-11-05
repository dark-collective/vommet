// The streams the call view draws a tile for (callTileStreams), which
// call_stats also counts as tiles_shown: the two must agree. tiles_shown
// once counted every stream but screen share audio, so a camera with its
// microphone counted two tiles where the view drew one.
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/components/voip/voip_tiles.dart';
import 'package:commet/ui/organisms/call_view/voip_stream_view.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'roomlist_fixture.dart';
import 'support/fake_voip_session.dart';
import 'support/room_page_fixtures.dart';

class _Watching extends Fake implements VoipStreamWatching {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  FakeVoipStream s(String user, VoipStreamType type) => FakeVoipStream(user,
      user == me ? VoipStreamDirection.outgoing : VoipStreamDirection.incoming,
      type: type);

  group("callTileStreams", () {
    setUp(roomPageSetUp);
    tearDown(roomPageTearDown);

    List<String> tiles(List<VoipStream> streams, {bool watching = false}) {
      final session =
          startCall(roomFor(RoomCase.callInTextRoom), CallCase.empty)
            ..streams.addAll(streams);
      if (watching) VoipStreamWatching.register(session, _Watching());
      return [for (final t in callTileStreams(session)) t.streamId];
    }

    test("a voice alone is a tile", () {
      expect(tiles([s(me, VoipStreamType.audio)]), ["audio-$me"]);
    });

    test("a camera hides the same person's voice tile", () {
      expect(tiles([s(me, VoipStreamType.audio), s(me, VoipStreamType.video)]),
          ["video-$me"]);
    });

    test("screen share audio is never a tile", () {
      expect(
          tiles([
            s(remoteUser, VoipStreamType.screenshare),
            s(remoteUser, VoipStreamType.screenshareAudio),
          ]),
          ["screenshare-$remoteUser"]);
    });

    test("a sharer's voice: hidden without stream watching, kept with it", () {
      final streams = [
        s(remoteUser, VoipStreamType.audio),
        s(remoteUser, VoipStreamType.screenshare),
      ];
      expect(tiles(streams), ["screenshare-$remoteUser"]);
      expect(tiles(streams, watching: true),
          ["audio-$remoteUser", "screenshare-$remoteUser"]);
    });
  });

  group("the call view", () {
    setUp(roomPageSetUp);
    tearDown(roomPageTearDown);

    testWidgets("draws one tile per callTileStreams stream", (tester) async {
      final room = roomFor(RoomCase.callInTextRoom);
      final session = startCall(room, CallCase.empty)
        ..streams.addAll([
          s(me, VoipStreamType.audio),
          s(me, VoipStreamType.video),
          s(remoteUser, VoipStreamType.audio),
          s(remoteUser, VoipStreamType.screenshareAudio),
        ]);
      await pumpRoomPage(tester, room, width: 1014, height: 1060);
      expect(callTileStreams(session), hasLength(2));
      expect(find.byType(VoipStreamView),
          findsNWidgets(callTileStreams(session).length));
      await finishRoomPage(tester);
    });
  });
}
