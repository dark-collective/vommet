import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/ui/organisms/call_view/watched_stream_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client implements Client {
  @override
  Room? getRoom(String identifier) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Share implements VoipStream {
  @override
  VoipStreamType get type => VoipStreamType.screenshare;
  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;
  @override
  String get participantId => "p1";
  @override
  String get streamUserId => "@a:example.org";
  @override
  String get streamId => "s1";
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call implements VoipSession {
  @override
  final Client client = _Client();
  @override
  final List<VoipStream> streams = [_Share()];
  @override
  Stream<void> get onStateChanged => const Stream.empty();
  @override
  String get roomId => "!r:example.org";
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Watching implements VoipStreamWatching {
  @override
  Stream<void> get onChanged => const Stream.empty();
  @override
  bool isStreamAudioMuted(VoipStream stream) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late int fullscreens;
  late int stops;

  Future<void> pump(WidgetTester tester) async {
    fullscreens = 0;
    stops = 0;
    final call = _Call();
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Scaffold(
          body: SizedBox(
            width: 400,
            height: 240,
            child: WatchedStreamControls(
              stream: call.streams.first,
              session: call,
              watching: _Watching(),
              onStopWatching: () => stops++,
              onFullscreen: () => fullscreens++,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    ));
  }

  double opacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
      .opacity;

  Future<void> realWait() => Future.delayed(
      WatchedStreamControls.doubleTapWithin + const Duration(milliseconds: 80));

  testWidgets("a tap hides and shows the controls at once", (tester) async {
    await pump(tester);
    expect(opacity(tester), 1);
    await tester.tapAt(const Offset(200, 120));
    await tester.pump();
    expect(opacity(tester), 0);
    await tester.runAsync(realWait);
    await tester.tapAt(const Offset(200, 120));
    await tester.pump();
    expect(opacity(tester), 1);
    expect(fullscreens, 0);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets("a double tap toggles fullscreen", (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(200, 120));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(200, 120));
    await tester.pump();
    expect(fullscreens, 1);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets("on a touch screen Stop watching keeps its label",
      (tester) async {
    await pump(tester);
    // A narrow tile used with a mouse: just the X.
    expect(find.text(WatchedStreamControlsStrings.watchedStreamStopWatching),
        findsNothing);
    await tester.tapAt(const Offset(200, 120));
    await tester.pump();
    expect(find.text(WatchedStreamControlsStrings.watchedStreamStopWatching),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets("after a touch the controls stay up 5 s", (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(200, 120));
    await tester.pump();
    await tester.runAsync(realWait);
    await tester.tapAt(const Offset(200, 120));
    await tester.pump();
    expect(opacity(tester), 1);
    await tester.pump(const Duration(seconds: 4));
    expect(opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(opacity(tester), 0);
  });

  testWidgets("Stop watching works from the touch label", (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(200, 120));
    await tester.pump();
    await tester.runAsync(realWait);
    await tester.tapAt(const Offset(200, 120));
    await tester.pump();
    await tester
        .tap(find.text(WatchedStreamControlsStrings.watchedStreamStopWatching));
    await tester.pump();
    expect(stops, 1);
    await tester.pump(const Duration(seconds: 6));
  });
}
