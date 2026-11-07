// Vommet issue 129: the secure messaging setup suite, run on its own
// (nightly: integration.yml with target integration_test/secure_setup_runner.dart),
// with the slow tier of cross_signing_test.dart (sliding sync, big account,
// passphrase, start over, Settings › Security, interop with matrix-js-sdk).

import 'package:commet/generated/l10n.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'matrix/secure_setup_test.dart' as secure_setup_test;
import 'matrix/cross_signing_test.dart' as cross_signing_test;

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await T.load(const Locale("en"));
  await preferences.init();

  secure_setup_test.main();
  cross_signing_test.registerSlow();
}
