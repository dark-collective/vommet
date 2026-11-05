import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/member.dart';
import 'package:commet/ui/organisms/call_view/stream_tile.dart';
import 'package:commet/ui/organisms/call_view/vommet_call_view_streams.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet issue 864: a right-click on a stream tile gives its sharer's menu
// (their mic and stream volume) instead of the room's voice guide.

class _Stream implements VoipStream {
  _Stream(this.type, this.streamId);
  @override
  final VoipStreamType type;
  @override
  final String streamId;
  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;
  @override
  String get participantId => "p1";
  @override
  String get streamUserId => "@a:example.org";
  @override
  double get volume => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call implements VoipSession {
  @override
  final List<VoipStream> streams = [
    _Stream(VoipStreamType.audio, "mic"),
    _Stream(VoipStreamType.screenshare, "share"),
    _Stream(VoipStreamType.screenshareAudio, "shareAudio"),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Watching implements VoipStreamWatching {
  @override
  Stream<void> get onChanged => const Stream.empty();
  @override
  bool isWatching(VoipStream stream) => true;
  @override
  bool isStreamAudioMuted(VoipStream stream) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Member implements Member {
  @override
  String get identifier => "@a:example.org";
  @override
  String get displayName => "Pell";
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.blueGrey;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets("right-click on a stream tile opens the sharer's menu",
      (tester) async {
    final call = _Call();
    VoipStreamWatching.register(call, _Watching());
    final share = call.streams[1];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // Stands in for the room's GuideArea.
        body: tiamat.ContextMenu(
          items: const [tiamat.ContextMenuItem(text: "Voice guide")],
          child: Center(
            child: SizedBox(
              width: 360,
              height: 202,
              child: vommetWithStreamMenu(call, share, _Member(),
                  child: StreamTile(
                    name: "Pell",
                    background: const ColoredBox(color: Colors.blueGrey),
                    state: StreamTileState.idle,
                    small: StreamTileSmallAction.miniPlayer,
                    onWatch: () {},
                    onSmall: () {},
                  )),
            ),
          ),
        ),
      ),
    ));

    final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(StreamTile)));
    await tester.pump();
    await mouse.down(tester.getCenter(find.byType(StreamTile)));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.text("Voice guide"), findsNothing);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.screen_share), findsOneWidget);
  });
}
