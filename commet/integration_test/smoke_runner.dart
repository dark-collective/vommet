// Vommet's cross-platform smoke suite (#78): the same small set of checks on
// every platform. The full suite (vommet_runner.dart) runs on Linux only.
//
// --dart-define=TEST_CA_PEM_B64=<base64 PEM> trusts the test homeserver's
// self-signed CA inside the app, for platforms where the harness can't install
// it system-wide (Android emulator, Windows runner).

import 'dart:convert';
import 'dart:io';

import 'package:commet/generated/l10n.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'matrix/login_test.dart' as login_test;
import 'smoke/smoke_test.dart' as smoke_test;

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const ca = String.fromEnvironment('TEST_CA_PEM_B64');
  if (ca.isNotEmpty) {
    SecurityContext.defaultContext
        .setTrustedCertificatesBytes(base64Decode(ca));
  }

  await T.load(const Locale("en"));
  await preferences.init();

  // Each test restarts the whole app in one process; on the Android emulator
  // the third start took the emulator down (adb offline). The smoke test logs
  // in too, so Android runs only that.
  if (!Platform.isAndroid) login_test.main();
  smoke_test.main();
}
