import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/components/user_presence/user_presence_lifecycle_watcher.dart';
import 'package:commet/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';

// Vommet issue 339: going to the background or coming back set presence on
// every account, and an account without an access token threw an uncaught
// "Null check operator" from getPresence.

class _FakePresence implements UserPresenceComponent<Client> {
  _FakePresence({this.fails = false});

  final bool fails;
  final List<UserPresenceStatus> calls = [];

  @override
  Future<void> setStatus(UserPresenceStatus status,
      {String? message, bool clearMessage = false}) async {
    calls.add(status);
    if (fails) throw StateError("homeserver unreachable");
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  _FakeClient({required this.loggedIn, required this.presence});

  final bool loggedIn;
  final _FakePresence presence;

  @override
  bool isLoggedIn() => loggedIn;

  @override
  T? getComponent<T extends Component>() =>
      presence is T ? presence as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdkClient implements matrix.Client {
  _FakeSdkClient({required this.userID});

  @override
  String? userID;

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  @override
  final CachedStreamController<matrix.CachedPresence> onPresenceChanged =
      CachedStreamController();

  @override
  matrix.PresenceType? syncPresence;

  final List<String> requests = [];

  @override
  bool isLogged() => userID != null;

  @override
  Future<matrix.GetPresenceResponse> getPresence(String userId) async {
    requests.add("get $userId");
    return matrix.GetPresenceResponse(presence: matrix.PresenceType.online);
  }

  @override
  Future<void> setPresence(String userId, matrix.PresenceType presence,
      {String? statusMsg}) async {
    requests.add("set $userId ${presence.name}");
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this.matrixClient);

  @override
  final _FakeSdkClient matrixClient;

  @override
  String get identifier => "test-client";

  @override
  bool isLoggedIn() => matrixClient.isLogged();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("UserPresenceLifecycleWatcher.setStatusForClients", () {
    test("skips accounts that aren't signed in", () async {
      final signedOut = _FakePresence(fails: true);
      final signedIn = _FakePresence();

      await UserPresenceLifecycleWatcher.setStatusForClients([
        _FakeClient(loggedIn: false, presence: signedOut),
        _FakeClient(loggedIn: true, presence: signedIn),
      ], UserPresenceStatus.unavailable);

      expect(signedOut.calls, isEmpty);
      expect(signedIn.calls, [UserPresenceStatus.unavailable]);
    });

    test("one account failing doesn't escape or stop the others", () async {
      final failing = _FakePresence(fails: true);
      final working = _FakePresence();

      await expectLater(
          UserPresenceLifecycleWatcher.setStatusForClients([
            _FakeClient(loggedIn: true, presence: failing),
            _FakeClient(loggedIn: true, presence: working),
          ], UserPresenceStatus.online),
          completes);

      expect(failing.calls, [UserPresenceStatus.online]);
      expect(working.calls, [UserPresenceStatus.online]);
    });
  });

  group("MatrixUserPresenceComponent.setStatus", () {
    test("does nothing for an account without an access token", () async {
      final sdk = _FakeSdkClient(userID: null);
      final component = MatrixUserPresenceComponent(_FakeMatrixClient(sdk));

      await component.setStatus(UserPresenceStatus.online);

      expect(sdk.requests, isEmpty);
      await component.onClientClosed();
    });

    test("does nothing once the client has closed", () async {
      final sdk = _FakeSdkClient(userID: "@me:example.org");
      final component = MatrixUserPresenceComponent(_FakeMatrixClient(sdk));
      await component.onClientClosed();

      await component.setStatus(UserPresenceStatus.online);

      expect(sdk.requests, isEmpty);
    });

    test("sets presence for the signed-in user", () async {
      final sdk = _FakeSdkClient(userID: "@me:example.org");
      final component = MatrixUserPresenceComponent(_FakeMatrixClient(sdk));

      await component.setStatus(UserPresenceStatus.unavailable);

      expect(sdk.requests,
          ["get @me:example.org", "set @me:example.org unavailable"]);
      await component.onClientClosed();
    });
  });
}
