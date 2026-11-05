import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/member.dart';
import 'package:commet/ui/organisms/call_view/stream_popout_window.dart';
import 'package:flutter/material.dart';

class FakePopoutBackend implements StreamPopoutBackend {
  final changes = StreamController<StreamPopoutEvent>.broadcast(sync: true);
  final live = <int>{};
  final closed = <int>[];
  final focused = <int>[];
  final titles = <int, String>{};
  final fullscreens = <int, bool>{};
  final requests = <int, int>{};
  final sizes = <(int, int, int, int)>[];
  Completer<int?>? delayed;
  bool fail = false;
  int opens = 0;
  @override
  Future<int?> open(
      {required String title,
      required int requestId,
      int width = 960,
      int height = 600,
      int minWidth = 0,
      int minHeight = 0}) async {
    final id = ++opens;
    sizes.add((width, height, minWidth, minHeight));
    final actual = delayed == null ? (fail ? null : id) : await delayed!.future;
    if (actual != null) {
      live.add(actual);
      requests[actual] = requestId;
    }
    return actual;
  }

  @override
  Future<void> close(int viewId) async {
    live.remove(viewId);
    closed.add(viewId);
  }

  @override
  Future<void> focus(int viewId) async => focused.add(viewId);
  @override
  Future<void> setTitle(int viewId, String title) async =>
      titles[viewId] = title;
  @override
  Future<void> setFullscreen(int viewId, bool fullscreen) async =>
      fullscreens[viewId] = fullscreen;
  @override
  Stream<StreamPopoutEvent> get events => changes.stream;
}

class CameraFixtureClient implements Client {
  @override
  Room? getRoom(String identifier) => CameraFixtureRoom();
  @override
  T? getComponent<T extends Component>() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CameraFixtureStream implements VoipStream {
  CameraFixtureStream(this.streamId, this.participantId,
      {this.type = VoipStreamType.video,
      this.direction = VoipStreamDirection.incoming});
  @override
  final String streamId;
  @override
  final String participantId;
  @override
  final VoipStreamType type;
  @override
  final VoipStreamDirection direction;
  @override
  String get streamUserId => '@$participantId:example.org';
  @override
  double get audiolevel => 0;
  @override
  bool get isMuted => false;
  @override
  String get stats => 'fixture';
  @override
  double get volume => 1;
  @override
  double? get aspectRatio => 4 / 3;

  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get onStreamChanged => changes.stream;
  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => ColoredBox(
      key: key,
      color: participantId == 'alex' ? Colors.teal : Colors.deepPurple,
      child: const Center(
          child: Icon(Icons.person, size: 96, color: Colors.white)));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CameraFixtureSession implements VoipSession {
  CameraFixtureSession(this.streams, {Client? client})
      : client = client ?? CameraFixtureClient();
  @override
  final Client client;
  @override
  List<VoipStream> streams;
  @override
  VoipState state = VoipState.connected;
  @override
  String get roomId => '!room:example.org';
  @override
  String get sessionId => 'fixture-session';
  @override
  bool get isMicrophoneMuted => false;
  @override
  bool get supportsScreenshare => true;
  @override
  bool get isSharingScreen => false;
  @override
  bool get isCameraEnabled => true;
  @override
  Stream<void> get onUpdateVolumeVisualizers => const Stream.empty();
  @override
  Future<void> updateStats() async {}

  final changes = StreamController<void>.broadcast(sync: true);
  final connections = StreamController<VoipState>.broadcast(sync: true);
  @override
  Stream<void> get onStateChanged => changes.stream;
  @override
  Stream<VoipState> get onConnectionStateChanged => connections.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CameraFixtureMember implements Member {
  CameraFixtureMember(this.identifier);
  @override
  final String identifier;
  @override
  String get displayName => identifier.contains('you') ? 'You' : 'Alex';
  @override
  String get userName => displayName;
  @override
  ImageProvider? get avatar => null;
  @override
  ImageProvider? get largeAvatar => null;
  @override
  Color get defaultColor => Colors.teal;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CameraFixtureRoom implements Room {
  @override
  String get identifier => '!room:example.org';
  @override
  String get displayName => 'Fixture room';
  @override
  Member getMemberOrFallback(String userId) => CameraFixtureMember(userId);
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.teal;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PopoutFixtureWatching implements VoipStreamWatching {
  final changed = StreamController<void>.broadcast(sync: true);
  final focus = StreamController<void>.broadcast(sync: true);
  final focusRequests = <VoipStream>[];
  @override
  bool isWatching(VoipStream stream) => true;
  @override
  bool hasPreview(VoipStream stream) => false;
  @override
  Future<void> setWatching(VoipStream stream, bool watching) async {}
  @override
  bool isStreamAudioMuted(VoipStream stream) => false;
  @override
  List<String> viewersOf(VoipStream stream) => [];
  @override
  VoipStream? takeFocusRequest() => null;
  @override
  void requestFocus(VoipStream stream) => focusRequests.add(stream);
  @override
  Stream<void> get onChanged => changed.stream;
  @override
  Stream<void> get onFocusRequest => focus.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
