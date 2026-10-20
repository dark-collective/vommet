// Vommet: smoke check for the native widget dock (windows/runner/widget_dock.cpp,
// linux/widget_dock.cc), as a plain app entry point: on Windows the check must
// run in a release build (the debug build's Rust link fails, and release
// builds leave out the integration_test plugin), so no test framework here.
//
//   flutter build windows --release -t integration_test/widget_dock_probe.dart
//   DOCK_SMOKE_OUT=<dir> <app exe>
//
// No homeserver: a local page reports a load id, and the check makes sure the
// same page (same id, no second load) answers page messages while docked,
// popped out into its own window and docked back, and that replies carry
// event.source == window.parent. Writes dock-smoke.txt into DOCK_SMOKE_OUT,
// ending in "DOCK-SMOKE PASS" or "DOCK-SMOKE FAIL ...", and exits 0 on success.
// While it holds a state it writes DOCK_SMOKE_OUT/holding (the state's name)
// so the workflow can capture the screen.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/components/widgets/docked/native_widget_dock_backend.dart';
import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _page = """<!doctype html>
<html><body style="margin:0;background:#ff00ff;color:#fff;font:32px sans-serif">
<div id="t">dock smoke</div>
<script>
  const loadId = Math.random().toString(36).slice(2);
  document.getElementById("t").textContent = "dock smoke " + loadId;
  window.addEventListener("message", (e) => {
    window.parent.postMessage({kind: "ack", loadId: loadId,
        source: e.source === window.parent, n: e.data.n}, "*");
  });
  window.parent.postMessage({kind: "hello", loadId: loadId}, "*");
</script></body></html>""";

final _out =
    Platform.environment["DOCK_SMOKE_OUT"] ?? Directory.systemTemp.path;

void _log(String line) {
  stdout.writeln(line);
  File("$_out/dock-smoke.txt")
      .writeAsStringSync("$line\n", mode: FileMode.append, flush: true);
}

class _Failure implements Exception {
  _Failure(this.message);
  final String message;
  @override
  String toString() => message;
}

void _expect(bool ok, String what) {
  if (!ok) throw _Failure(what);
}

Future<String> _script() async {
  var script = await rootBundle.loadString("assets/data/widgets_ipc.js");
  final common = await rootBundle.loadString("assets/data/widgets_common.js");
  script = script.replaceAll("//\${SEND_IPC_CODE}",
      "function sendIpc(msg) { ${WidgetDockBackend.sendIpcCode()} }");
  return script.replaceAll("//\${WIDGETS_COMMON}", common);
}

Future<void> _check() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_page);
    request.response.close();
  });

  final backend = NativeWidgetDockBackend.instance;
  _expect(await backend.isAvailable(), "WebView2 not available");

  const id = "smoke";
  final messages = <Map<String, dynamic>>[];
  final kinds = <WidgetDockEventKind>[];
  final sub = backend.events.where((e) => e.id == id).listen((e) {
    kinds.add(e.kind);
    if (e.kind == WidgetDockEventKind.message) {
      messages.add(jsonDecode(e.message!) as Map<String, dynamic>);
    }
  });

  Future<void> until(bool Function() done, String what) async {
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (!done()) {
      if (DateTime.now().isAfter(end)) throw _Failure("timed out: $what");
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Map<String, dynamic>? ack(int n) =>
      messages.where((m) => m["kind"] == "ack" && m["n"] == n).firstOrNull;

  Future<Map<String, dynamic>> ping(int n) async {
    await backend.evaluate(
        id, "window.onMessagePolyfill(${jsonEncode(jsonEncode({"n": n}))})");
    await until(() => ack(n) != null, "ack $n");
    return ack(n)!;
  }

  Future<void> hold(String label) async {
    _log("DOCK-SMOKE state: $label");
    final marker = File("$_out/holding");
    await marker.writeAsString(label.replaceAll(" ", "-"));
    await Future.delayed(const Duration(seconds: 5));
    await marker.delete();
  }

  await backend.create(
      id: id,
      url: "http://127.0.0.1:${server.port}/",
      script: await _script(),
      title: "Dock smoke");
  final ratio =
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  await backend.setRect(id, Rect.fromLTWH(0, 0, 400 * ratio, 300 * ratio));
  await backend.setVisible(id, true);

  await until(() => messages.any((m) => m["kind"] == "hello"), "hello");
  final loadId = messages.firstWhere((m) => m["kind"] == "hello")["loadId"];
  _log("DOCK-SMOKE loadId $loadId");

  var reply = await ping(1);
  _expect(reply["loadId"] == loadId, "docked: another page answered");
  _expect(reply["source"] == true, "event.source != window.parent");

  final png = await backend.snapshot(id);
  _expect(png != null && png.length > 8, "no snapshot");
  _expect(png![0] == 0x89 && png[1] == 0x50, "snapshot is not a PNG");
  _log("DOCK-SMOKE snapshot ${png.length} bytes");
  await hold("docked");

  await backend.popOut(id);
  await until(() => kinds.contains(WidgetDockEventKind.poppedOut), "poppedOut");
  reply = await ping(2);
  _expect(reply["loadId"] == loadId, "popped out: page reloaded");
  await hold("popped out");

  await backend.dockBack(id);
  await until(() => kinds.contains(WidgetDockEventKind.docked), "docked");
  reply = await ping(3);
  _expect(reply["loadId"] == loadId, "docked back: page reloaded");
  await hold("docked back");

  _expect(messages.where((m) => m["kind"] == "hello").length == 1,
      "the page loaded more than once");

  await backend.destroy(id);
  await sub.cancel();
  await server.close(force: true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      home: Scaffold(
          backgroundColor: Color(0xff102030),
          body: Center(
              child: Text("flutter side",
                  style: TextStyle(color: Colors.white, fontSize: 32))))));
  var code = 1;
  try {
    // Let the window show first.
    await Future.delayed(const Duration(seconds: 2));
    await _check();
    _log("DOCK-SMOKE PASS");
    code = 0;
  } catch (e, s) {
    _log("DOCK-SMOKE FAIL ${e.runtimeType}: $e");
    _log("$s".split("\n").take(8).join(" | "));
  }
  exit(code);
}
