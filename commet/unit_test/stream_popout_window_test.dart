import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/ui/organisms/call_view/stream_mini_player.dart';
import 'package:commet/ui/organisms/call_view/stream_popout_window.dart';
import 'package:commet/ui/organisms/call_view/stream_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet: a watched stream popped out into its own window
// (StreamPopoutWindow), against a fake native window.

class _FakeBackend implements StreamPopoutBackend {
  final events_ = StreamController<StreamPopoutEvent>.broadcast(sync: true);
  int? nextId = 7;
  int opens = 0;
  int closes = 0;
  final titles = <String>[];
  final fullscreens = <bool>[];

  @override
  Future<int?> open(
      {required String title, int width = 960, int height = 600}) async {
    opens++;
    return nextId;
  }

  @override
  Future<void> close() async => closes++;

  @override
  Future<void> setTitle(String title) async => titles.add(title);

  @override
  Future<void> setFullscreen(bool fullscreen) async =>
      fullscreens.add(fullscreen);

  @override
  Stream<StreamPopoutEvent> get events => events_.stream;
}

class _FakeStream implements VoipStream {
  _FakeStream(this.streamId);

  @override
  final String streamId;

  @override
  String get participantId => "p1";

  @override
  VoipStreamType get type => VoipStreamType.screenshare;

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  String get streamUserId => "@alice:example.org";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSession implements VoipSession {
  _FakeSession(this.streams);

  @override
  VoipState state = VoipState.connected;

  @override
  List<VoipStream> streams;

  final changes = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get onStateChanged => changes.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWatching implements VoipStreamWatching {
  final watched = <VoipStream>{};
  final focusRequests = <VoipStream>[];

  @override
  bool isWatching(VoipStream stream) => watched.contains(stream);

  @override
  Future<void> setWatching(VoipStream stream, bool watching) async {
    if (watching) {
      watched.add(stream);
    } else {
      watched.remove(stream);
    }
  }

  @override
  void requestFocus(VoipStream stream) => focusRequests.add(stream);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeBackend backend;
  late StreamPopoutWindow window;
  late _FakeStream stream;
  late _FakeSession session;
  late _FakeWatching watching;

  setUp(() {
    backend = _FakeBackend();
    window = StreamPopoutWindow(backend, afterFrame: () async {});
    stream = _FakeStream("s1");
    session = _FakeSession([stream]);
    watching = _FakeWatching()..watched.add(stream);
    VoipStreamWatching.register(session, watching);
    StreamMiniPlayer.instance.hide();
  });

  tearDown(() => window.dispose());

  test('open shows the stream in its window; the tile knows', () async {
    final opening = window.open(session, stream);
    // Already marked while the window opens, so the tile says so at once.
    expect(window.isShowing(session, stream), isTrue);
    await opening;
    expect(backend.opens, 1);
    expect(window.viewId, 7);
    expect(window.isShowing(session, _FakeStream("other")), isFalse);
  });

  test('closing the window docks the stream back into the call view', () async {
    await window.open(session, stream);
    backend.events_.add(const StreamPopoutEvent(
        StreamPopoutEventKind.closeRequested,
        viewId: 7));
    await pumpEventQueue();
    expect(window.active, isFalse);
    expect(window.viewId, isNull);
    expect(backend.closes, 1);
    expect(watching.focusRequests, [stream]);
    expect(watching.isWatching(stream), isTrue);
  });

  test('Dock back closes it and shows the stream big', () async {
    await window.open(session, stream);
    await window.dockBack();
    expect(window.active, isFalse);
    expect(backend.closes, 1);
    expect(watching.focusRequests, [stream]);
  });

  test('the call ending closes the window, nothing docks', () async {
    await window.open(session, stream);
    session.state = VoipState.ended;
    session.changes.add(null);
    await pumpEventQueue();
    expect(window.active, isFalse);
    expect(backend.closes, 1);
    expect(watching.focusRequests, isEmpty);
  });

  test('the sharer stopping or you stop watching closes it', () async {
    await window.open(session, stream);
    watching.watched.clear();
    session.changes.add(null);
    await pumpEventQueue();
    expect(window.active, isFalse);
    expect(backend.closes, 1);

    final second = _FakeStream("s2");
    session.streams = [second];
    watching.watched.add(second);
    await window.open(session, second);
    session.streams = [];
    session.changes.add(null);
    await pumpEventQueue();
    expect(window.active, isFalse);
    expect(backend.closes, 2);
  });

  test('follows the sharer to what they share next', () async {
    await window.open(session, stream);
    final next = _FakeStream("s1b");
    session.streams = [next];
    watching.watched.add(next);
    session.changes.add(null);
    await pumpEventQueue();
    expect(window.isShowing(session, next), isTrue);
    expect(backend.closes, 0);
  });

  test('Stop watching closes it and stops watching', () async {
    await window.open(session, stream);
    await window.stopWatching();
    expect(window.active, isFalse);
    expect(watching.isWatching(stream), isFalse);
    expect(watching.focusRequests, isEmpty);
  });

  test('a window gone on its own (app quit) just clears', () async {
    await window.open(session, stream);
    backend.events_
        .add(const StreamPopoutEvent(StreamPopoutEventKind.closed, viewId: 7));
    expect(window.active, isFalse);
    expect(backend.closes, 0);
  });

  test('popping out again before the window closed keeps the window', () async {
    final frame = Completer<void>();
    window.dispose();
    window = StreamPopoutWindow(backend, afterFrame: () => frame.future);
    await window.open(session, stream);
    final closing = window.close();
    await window.open(session, stream);
    frame.complete();
    await closing;
    expect(backend.closes, 0);
    expect(window.isShowing(session, stream), isTrue);
  });

  test('no window: the mini-player instead', () async {
    backend.nextId = null;
    await window.open(session, stream);
    expect(window.active, isFalse);
    expect(StreamMiniPlayer.instance.showing, isTrue);
    expect(StreamMiniPlayer.instance.stream, stream);
    StreamMiniPlayer.instance.hide();
  });

  test('fullscreen follows the window', () async {
    await window.open(session, stream);
    await window.setFullscreen(true);
    expect(backend.fullscreens, [true]);
    backend.events_.add(const StreamPopoutEvent(
        StreamPopoutEventKind.fullscreenChanged,
        viewId: 7,
        fullscreen: true));
    expect(window.fullscreen, isTrue);
  });

  test('the title is sent once the window is open, when it changes', () async {
    window.setTitle("early");
    expect(backend.titles, isEmpty);
    await window.open(session, stream);
    window.setTitle("LIVE Alice — Room");
    window.setTitle("LIVE Alice — Room");
    expect(backend.titles, ["LIVE Alice — Room"]);
  });

  test('window title', () {
    expect(StreamPopoutWindow.windowTitle(name: "Alice"), "LIVE Alice");
    expect(
        StreamPopoutWindow.windowTitle(
            name: "Alice", title: "Firefox", room: "Gaming"),
        "LIVE Alice · Firefox — Gaming");
    expect(StreamPopoutWindow.windowTitle(name: "Alice", room: "Gaming"),
        "LIVE Alice — Gaming");
  });

  test('the stream tile offers the window once installed', () {
    final before = StreamTile.popOutWindow;
    addTearDown(() => StreamTile.popOutWindow = before);
    StreamTile.popOutWindow = null;
    expect(StreamTile.smallActionFor(othersBig: false, phone: false),
        StreamTileSmallAction.miniPlayer);
    StreamTile.popOutWindow = window.open;
    expect(StreamTile.smallActionFor(othersBig: false, phone: false),
        StreamTileSmallAction.popOutWindow);
    expect(StreamTile.smallActionFor(othersBig: false, phone: true),
        StreamTileSmallAction.miniPlayer);
  });

  testWidgets('tile while in its own window: says so, Dock back',
      (tester) async {
    var docked = 0;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 225,
          child: StreamTile(
            name: "Alice",
            background: const ColoredBox(color: Colors.black),
            state: StreamTileState.inOwnWindow,
            onWatch: () {},
            onSmall: () {},
            onShowHere: () => docked++,
          ),
        ),
      ),
    ));
    expect(find.text(StreamTile.streamTileInOwnWindow), findsOneWidget);
    expect(find.text(StreamTile.streamTileDockBack), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("streamTileShowHere")));
    expect(docked, 1);
  });

  testWidgets('host keeps the app as it is with no window', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: StreamPopoutHost(window: window, child: const Text("app"))));
    expect(find.text("app"), findsOneWidget);
    expect(find.byType(StreamPopoutPage), findsNothing);
  });
}
