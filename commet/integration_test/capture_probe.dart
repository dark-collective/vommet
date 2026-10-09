// Microphone capture check (#78) as a plain app entry point, for platforms
// where the test must run in a release build (Windows: the debug build's Rust
// link fails, and release builds leave out the integration_test plugin).
//
//   flutter build windows --release -t integration_test/capture_probe.dart \
//     --dart-define=CAPTURE_LOG=<results file>
//
// Runs the check, writes its lines to CAPTURE_LOG and exits 0 on success.

import 'dart:io';

import 'package:commet/main.dart';
import 'package:flutter/widgets.dart';

import 'smoke/capture_check.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var code = 1;
  try {
    await preferences.init();
    final failure = await runCaptureCheck();
    if (failure != null) captureLog("FAIL $failure");
    code = failure == null ? 0 : 1;
  } catch (e, s) {
    captureLog("FAIL ${e.runtimeType}: $e");
    captureLog("$s".split("\n").take(8).join(" | "));
  }
  exit(code);
}
