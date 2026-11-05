import 'package:commet/generated/l10n.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'matrix/unread_two_devices_test.dart' as unread_two_devices_test;

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await T.load(const Locale("en"));
  await preferences.init();
  unread_two_devices_test.main();
}
