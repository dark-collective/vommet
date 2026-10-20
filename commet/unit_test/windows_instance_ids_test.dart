import 'dart:io';

import 'package:commet/config/app_config.dart';
import 'package:test/test.dart';

// Vommet issue 355: the ids a second launch uses to find the running
// instance on Windows must be Vommet's own, not a running Commet's.
void main() {
  test("Windows single-instance pipe is Vommet's own", () {
    expect(AppConfig.windowsPipeName, r"\\.\pipe\im.nether.chat");
    expect(AppConfig.windowsPipeName.toLowerCase(), isNot(contains("commet")));
  });

  test("Windows runner window class is Vommet's own and matches its lookup",
      () {
    const cls = "VOMMET_FLUTTER_RUNNER_WIN32_WINDOW";
    final window = File("windows/runner/win32_window.cpp").readAsStringSync();
    final runner = File("windows/runner/main.cpp").readAsStringSync();
    expect(window, contains('kWindowClassName[] = L"$cls"'));
    expect(runner, contains('::FindWindow(L"$cls"'));
    expect(window + runner, isNot(contains("COMMETCHAT_")));
  });
}
