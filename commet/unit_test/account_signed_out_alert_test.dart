// Vommet issue 427: an account whose session ended (signed out from another
// device, token revoked) stopped working with no word to the user. It now
// raises an "Account signed out" alert, once, that goes away when the account
// is removed.
import 'package:commet/client/alert.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<MatrixClient> newClient(String name) async {
  final database =
      await MatrixSdkDriftDatabase.init(NativeDatabase.memory(), name);
  return MatrixClient(identifier: name, database: database);
}

List<Alert> signedOutAlerts(ClientManager manager) =>
    manager.alertManager.alerts
        .where((a) => a.title == MatrixClient.matrixClientAccountSignedOutTitle)
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late ClientManager manager;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    manager = ClientManager();
    clientManager = manager;
  });

  tearDown(() => clientManager = null);

  test("a session that ends raises one alert naming the account", () async {
    final client = await newClient("ended-account");
    final state = client.getMatrixClient().onLoginStateChanged;

    state.add(matrix.LoginState.loggedIn);
    state.add(matrix.LoginState.loggedOut);
    state.add(matrix.LoginState.loggedOut);
    await pumpEventQueue();

    final alerts = signedOutAlerts(manager);
    expect(alerts, hasLength(1));
    expect(alerts.single.type, AlertType.warning);
    expect(alerts.single.message, startsWith("ended-ac..."));
    expect(alerts.single.action, isNotNull);
  });

  test("a client that never had a session raises no alert", () async {
    final client = await newClient("new-account");
    client
        .getMatrixClient()
        .onLoginStateChanged
        .add(matrix.LoginState.loggedOut);
    await pumpEventQueue();

    expect(signedOutAlerts(manager), isEmpty);
  });

  test("removing the account clears its alert and raises no new one", () async {
    final client = await newClient("ended-account");
    preferences.addRegisteredMatrixClient("ended-account");
    manager.addClient(client);
    final state = client.getMatrixClient().onLoginStateChanged;
    state.add(matrix.LoginState.loggedIn);
    state.add(matrix.LoginState.loggedOut);
    await pumpEventQueue();
    expect(signedOutAlerts(manager), hasLength(1));

    await manager.logoutClient(client);
    await pumpEventQueue();

    expect(manager.clients, isEmpty);
    expect(signedOutAlerts(manager), isEmpty);
  });

  test("logging out on purpose raises no alert", () async {
    final client = await newClient("leaving-account");
    preferences.addRegisteredMatrixClient("leaving-account");
    manager.addClient(client);
    client
        .getMatrixClient()
        .onLoginStateChanged
        .add(matrix.LoginState.loggedIn);
    await pumpEventQueue();

    await manager.logoutClient(client);
    await pumpEventQueue();

    expect(signedOutAlerts(manager), isEmpty);
  });
}
