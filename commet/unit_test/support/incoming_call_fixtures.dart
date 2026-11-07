// Vommet issue 1098: call SDK-boundary fixtures shared with captures.
import 'dart:async';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/matrix/components/room_call/matrix_room_call_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_voip_session.dart';

class AlertClients extends Fake implements ClientManager {
  @override
  late CallManager callManager;
  @override
  final clients = NotifyingList<Client>.empty(growable: true);
  @override
  final onClientAdded = StreamController<int>.broadcast();
  @override
  final onClientRemoved = StreamController<StalePeerInfo>.broadcast();
}

class AlertClient extends Fake implements Client {
  AlertClient(this.identifier);
  @override
  final String identifier;
  @override
  Profile? get self => null;
  @override
  Room? getRoom(String id) => null;
  @override
  T? getComponent<T extends Component>() => null;
}

// Extend the shared SDK-boundary fake instead of another session interface.
class AlertCall extends FakeVoipSession {
  AlertCall(Client client,
      {String room = '!dm:example.org',
      String caller = 'Alex Rivera',
      VoipState state = VoipState.incoming})
      : super(client, room,
            state: state,
            remoteUserId: '@alex:example.org',
            remoteUserName: caller,
            roomName: 'Alex DM');
  int accepts = 0;
  int declines = 0;
  Completer<void>? wait;
  bool fail = false;
  // A session API can complete before its separate state stream advances.
  bool keepIncoming = false;
  @override
  Future<void> acceptCall(
      {bool withMicrophone = false, bool withCamera = false}) async {
    accepts++;
    await wait?.future;
    if (fail) throw StateError('private server error');
    if (!keepIncoming) setState(VoipState.connecting);
  }

  @override
  Future<void> declineCall() async {
    declines++;
    await wait?.future;
    if (fail) throw StateError('private server error');
    if (!keepIncoming) setState(VoipState.ended);
  }
}

// Only Matrix/SDK dependencies are faked; tests use the real invite adapter.
class AlertInviteClient extends AlertClient implements MatrixClient {
  AlertInviteClient() : super('@lee:invite.example.org');
}

class _InviteMember extends Fake implements Member {
  @override
  String get displayName => 'Alex Rivera';
}

class _InviteRoom extends Fake implements MatrixRoom {
  @override
  String get identifier => '!invite:example.org';
  @override
  String get displayName => 'Alex DM';
  @override
  Member getMemberOrFallback(String id) => _InviteMember();
}

class AlertRoomCallComponent extends Fake implements MatrixRoomCallComponent {
  @override
  final MatrixClient client = AlertInviteClient();
  @override
  final MatrixRoom room = _InviteRoom();
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get onParticipantsChanged => changes.stream;
  Object? failure;
  VoipSession? result;
  Completer<VoipSession?>? wait;
  int joins = 0;
  @override
  Future<VoipSession?> joinCall() async {
    joins++;
    if (wait != null) return wait!.future;
    if (failure != null) throw failure!;
    return result;
  }
}
