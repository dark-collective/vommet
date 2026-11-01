import 'dart:async';
import 'dart:io';

import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';

/// Vommet issues 331 and 883: the Windows runner sends "end" here when the
/// session ends, and takes "quit" from [exitApp]
/// (windows/runner/flutter_window.cpp).
const windowsSessionChannel = BasicMessageChannel<String?>(
  "im.nether.vommet/session",
  StringCodec(),
);

/// Ends the app. Use this instead of dart:io's [exit] on desktop.
///
/// Vommet issue 883: on Windows, [exit] calls ExitProcess on the UI thread
/// while the engine, the plugins and WebView2 still run, and their teardown
/// then crashes with an access violation (which held up Windows shutdown).
/// There the runner closes the window instead, the same teardown as closing
/// a plain Flutter app. [exit] is the fallback when the runner doesn't take
/// the request, or the engine is still running [fallbackAfter] later.
Future<Never> exitApp({
  bool? isWindows,
  BasicMessageChannel<String?> channel = windowsSessionChannel,
  Duration fallbackAfter = const Duration(seconds: 5),
  Never Function(int code) exitProcess = exit,
}) async {
  if (isWindows ?? Platform.isWindows) {
    try {
      final reply =
          await channel.send("quit").timeout(const Duration(seconds: 2));
      if (reply == "ok") {
        // The engine stops this isolate once the window is gone.
        await Future<void>.delayed(fallbackAfter);
        Log.w("Quitting: the window is still open, exiting the process");
      } else {
        Log.w("Quitting: the runner didn't take the quit request");
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to ask the runner to quit");
    }
  }
  exitProcess(0);
}
