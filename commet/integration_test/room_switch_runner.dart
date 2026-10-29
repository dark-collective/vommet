// Vommet issue 345: the room-switch leak check on its own
// (.vommet/it/run.sh integration_test/room_switch_runner.dart).

import 'package:commet/generated/l10n.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'matrix/room_switch_leak_test.dart' as room_switch_leak_test;

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await T.load(const Locale("en"));
  await preferences.init();
  room_switch_leak_test.main();
}
