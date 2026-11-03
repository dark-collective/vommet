// Vommet issue 321: an account that failed to load shows as "Error" and
// could not be removed, because logging it out threw before ClientManager
// took it out of the list.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/error_profile.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<MatrixClient> unloadedClient(String name) async {
  final database =
      await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name);
  final client = MatrixClient(identifier: name, database: database);
  // What loadFromDB does when init throws
  client.self = ErrorProfile(reason: "Exception: database is locked");
  return client;
}

/// A client whose logout fails, as a server logout does when the session is
/// broken or the server can't be reached
class ThrowingLogoutClient extends MatrixClient {
  ThrowingLogoutClient({required super.identifier, required super.database});

  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls++;
    throw Exception("M_UNKNOWN_TOKEN");
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Each test client gets its own in-memory database
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("a client that never loaded is removed and unregistered", () async {
    final manager = ClientManager();
    final client = await unloadedClient("failed-account");
    preferences.addRegisteredMatrixClient("failed-account");
    manager.addClient(client);
    await pumpEventQueue();

    final removed = <StalePeerInfo>[];
    manager.onClientRemoved.stream.listen(removed.add);

    await manager.logoutClient(client);
    await pumpEventQueue();

    expect(manager.clients, isEmpty);
    expect(manager.getClient("failed-account"), isNull);
    expect(preferences.getRegisteredMatrixClients(),
        isNot(contains("failed-account")));
    expect(removed.map((e) => e.displayName), ["Error"]);
  });

  test("a failing logout still removes the account locally", () async {
    final manager = ClientManager();
    final good = await unloadedClient("good-account");
    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), "broken-account");
    final broken =
        ThrowingLogoutClient(identifier: "broken-account", database: database);
    manager.addClient(good);
    manager.addClient(broken);
    await pumpEventQueue();

    final removed = <StalePeerInfo>[];
    manager.onClientRemoved.stream.listen(removed.add);

    await expectLater(manager.logoutClient(broken), completes);
    await pumpEventQueue();

    expect(broken.logoutCalls, 1);
    expect(manager.clients, <Client>[good]);
    expect(manager.getClient("broken-account"), isNull);
    expect(removed.single.index, 1);
  });

  test("tapping Logout twice removes the account once", () async {
    final manager = ClientManager();
    final client = await unloadedClient("failed-account");
    manager.addClient(client);
    await pumpEventQueue();

    final removed = <StalePeerInfo>[];
    manager.onClientRemoved.stream.listen(removed.add);

    await Future.wait(
        [manager.logoutClient(client), manager.logoutClient(client)]);
    await manager.logoutClient(client);
    await pumpEventQueue();

    expect(manager.clients, isEmpty);
    expect(removed, hasLength(1));
  });

  group("ErrorProfile reason", () {
    test("is kept when short", () {
      expect(ErrorProfile(reason: "Exception: database is locked").reason,
          "Exception: database is locked");
    });

    test("is put on one line and cut short", () {
      final reason = ErrorProfile(
              reason: "Exception: first line\n  #0 ${"x" * 400}\n#1 more")
          .reason!;
      expect(reason, startsWith("Exception: first line #0 xxx"));
      expect(reason, isNot(contains("\n")));
      expect(reason.length, ErrorProfile.maxReasonLength);
      expect(reason, endsWith("…"));
    });

    test("is null when there is nothing to show", () {
      expect(ErrorProfile().reason, isNull);
      expect(ErrorProfile(reason: "  \n ").reason, isNull);
    });

    test("the profile still reads as Error", () {
      final profile = ErrorProfile(reason: "boom");
      expect(profile.displayName, "Error");
      expect(profile.identifier, "Error");
    });
  });
}
