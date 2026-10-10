// Vommet's integration suite (.vommet/it/run.sh runs this by default).
//
// Starts with the upstream tests that pass against the CI homeserver; the
// rest of upstream's runner.dart (create space, key verification, multi
// account, change space name) targets UI that has since changed and is being
// rewritten. Add fork scenarios here as they land.

import 'package:commet/generated/l10n.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'matrix/login_test.dart' as login_test;

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await T.load(const Locale("en"));
  await preferences.init();

  login_test.main();
}
