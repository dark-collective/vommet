// Vommet: closing a space closed its streams before cancelling the listeners
// that add to them, and wasn't safe to repeat. (The other half of the fix,
// MatrixClient closing a space replaced by a rejoined one, needs a banned
// space loaded from the archive after a restart; this fixture keeps the
// live ban's SDK object, so it isn't covered here.)
import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const s = "!s:example.com";
const child = "!child:example.com";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  var n = 0;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("space-close-${n++}");
  });

  tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

  test("closing a space twice is harmless and ends its update stream",
      () async {
    await sync(client, join: {
      s: joined(s, children: [child], name: "Space"),
    });
    final space = client.getSpace(s) as MatrixSpace;
    final closed = Completer<void>();
    space.onUpdate.listen((_) {}, onDone: closed.complete);

    await space.close();
    await space.close();
    await closed.future.timeout(const Duration(seconds: 5));
  });
}
