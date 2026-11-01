// Vommet: a watched stream popped out into its own window
// (lib/ui/organisms/call_view/stream_popout_window.dart,
// linux/stream_popout.cc), on the real Linux runner: the window opens a
// second Flutter view on the same engine, the pop-out page draws into it at
// that window's own size, and Dock back closes it again (the view goes) and
// asks the call view to show the stream big. No homeserver and no real
// stream: the "video" is a plain magenta box.
import 'dart:async';
import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/ui/organisms/call_view/stream_popout_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'extensions/wait_for.dart';

class _Client implements Client {
  @override
  Room? getRoom(String identifier) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stream implements VoipStream {
  @override
  String get streamId => "synthetic";

  @override
  String get participantId => "p1";

  @override
  VoipStreamType get type => VoipStreamType.screenshare;

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  String get streamUserId => "@sharer:example.org";

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => ColoredBox(
      key: key,
      color: const Color(0xffff00ff),
      child: const SizedBox(width: 640, height: 360));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  _Session(this.stream);

  final VoipStream stream;
  final changes = StreamController<void>.broadcast();

  @override
  Client get client => _Client();

  @override
  String get roomId => "!room:example.org";

  @override
  VoipState get state => VoipState.connected;

  @override
  List<VoipStream> get streams => [stream];

  @override
  Stream<void> get onStateChanged => changes.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Watching implements VoipStreamWatching {
  final focusRequests = <VoipStream>[];

  @override
  bool isWatching(VoipStream stream) => true;

  @override
  bool isStreamAudioMuted(VoipStream stream) => false;

  @override
  void requestFocus(VoipStream stream) => focusRequests.add(stream);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stream pop-out: own window, own size, Dock back closes it',
      (tester) async {
    final dispatcher = tester.binding.platformDispatcher;
    // The app's window when startGui ran in an earlier test (it holds the
    // channel), else one of our own.
    final window = StreamPopoutWindow.maybeInstance ??
        StreamPopoutWindow(MethodChannelStreamPopoutBackend());
    final stream = _Stream();
    final session = _Session(stream);
    final watching = _Watching();
    VoipStreamWatching.register(session, watching);

    await tester.pumpWidget(MaterialApp(
        home: StreamPopoutHost(
            window: window, child: const Scaffold(body: Text("main window")))));
    final viewsBefore = dispatcher.views.length;

    await window.open(session, stream);
    expect(window.viewId, isNotNull, reason: "the native window opened");
    final id = window.viewId!;
    expect(id, isNot(dispatcher.implicitView!.viewId));

    await tester.waitFor(() {
      final view = dispatcher.view(id: id);
      return view != null &&
          !view.physicalSize.isEmpty &&
          find.byType(StreamPopoutPage).evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 15));
    expect(dispatcher.views.length, viewsBefore + 1);

    // Drawn in the second view, at that window's size, not the main one's.
    final page = find.byType(StreamPopoutPage);
    final pageView = View.of(tester.element(page));
    expect(pageView.viewId, id);
    final popoutView = dispatcher.view(id: id)!;
    final logical = popoutView.physicalSize / popoutView.devicePixelRatio;
    final pageSize = tester.getSize(page);
    expect(pageSize.width, closeTo(logical.width, 2));
    expect(pageSize.height, closeTo(logical.height, 2));
    expect(find.byKey(const ValueKey("streamPopoutVideo_synthetic")),
        findsOneWidget);
    // The main window stays as it was.
    expect(find.text("main window"), findsOneWidget);

    // Dock back, in the pop-out window.
    await tester.tap(find.byKey(const ValueKey("streamPopoutDockBack")));
    await tester.waitFor(() => dispatcher.view(id: id) == null,
        timeout: const Duration(seconds: 15));
    await tester.pump();
    expect(window.active, isFalse);
    expect(find.byType(StreamPopoutPage), findsNothing);
    expect(dispatcher.views.length, viewsBefore);
    expect(watching.focusRequests, [stream]);
  }, skip: !Platform.isLinux);
}
