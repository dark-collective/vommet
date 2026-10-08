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
import 'matrix/launch_test.dart' as launch_test;
import 'matrix/login_test.dart' as login_test;
import 'matrix/room_directory_test.dart' as room_directory_test;
import 'matrix/media_mosaic_test.dart' as media_mosaic_test;
import 'matrix/room_banner_test.dart' as room_banner_test;
import 'matrix/utd_vanish_test.dart' as utd_vanish_test;

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await T.load(const Locale("en"));
  await preferences.init();

  launch_test.main();
  login_test.main();
  room_directory_test.main();
  media_mosaic_test.main();
  room_banner_test.main();
  // Encrypted messages decrypt and stay after Retry Decrypt (#16, #102);
  // only the deterministic variant here, the rest run nightly.
  utd_vanish_test.registerVariants(["report:"]);
}
