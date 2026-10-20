// Vommet: smoke test for the native widget dock (windows/runner/widget_dock.cpp,
// linux/widget_dock.cc). No homeserver: a local page reports a load id, and
// the test checks that the same page (same id, no second load) answers page
// messages while docked, popped out into its own window and docked back,
// and that replies carry event.source == window.parent.
//
//   flutter test integration_test/widget_dock_native_runner.dart -d windows
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/components/widgets/docked/native_widget_dock_backend.dart';
import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

Future<String> _script() async {
  var script = await rootBundle.loadString("assets/data/widgets_ipc.js");
  final common = await rootBundle.loadString("assets/data/widgets_common.js");
  script = script.replaceAll("//\${SEND_IPC_CODE}",
      "function sendIpc(msg) { ${WidgetDockBackend.sendIpcCode()} }");
  return script.replaceAll("//\${WIDGETS_COMMON}", common);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("docked widget survives pop out and dock back", (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            backgroundColor: Color(0xff102030),
            body: Center(child: Text("flutter side")))));

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_page);
      request.response.close();
    });

    final backend = NativeWidgetDockBackend.instance;
    expect(await backend.isAvailable(), isTrue);

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
        if (DateTime.now().isAfter(end)) fail("timed out waiting for $what");
        await tester
            .runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
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
      // The workflow captures the screen meanwhile.
      stdout.writeln("DOCK-SMOKE state: $label");
      await tester.runAsync(() => Future.delayed(const Duration(seconds: 4)));
    }

    await backend.create(
        id: id,
        url: "http://127.0.0.1:${server.port}/",
        script: await _script(),
        title: "Dock smoke");
    final ratio = tester.view.devicePixelRatio;
    await backend.setRect(id, Rect.fromLTWH(0, 0, 400 * ratio, 300 * ratio));
    await backend.setVisible(id, true);

    await until(() => messages.any((m) => m["kind"] == "hello"), "hello");
    final loadId = messages.firstWhere((m) => m["kind"] == "hello")["loadId"];
    stdout.writeln("DOCK-SMOKE loadId $loadId");

    var reply = await ping(1);
    expect(reply["loadId"], loadId);
    expect(reply["source"], isTrue, reason: "event.source == window.parent");

    final png = await backend.snapshot(id);
    expect(png, isNotNull);
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    await hold("docked");

    await backend.popOut(id);
    await until(
        () => kinds.contains(WidgetDockEventKind.poppedOut), "poppedOut");
    reply = await ping(2);
    expect(reply["loadId"], loadId);
    await hold("popped out");

    await backend.dockBack(id);
    await until(() => kinds.contains(WidgetDockEventKind.docked), "docked");
    reply = await ping(3);
    expect(reply["loadId"], loadId);
    await hold("docked back");

    expect(messages.where((m) => m["kind"] == "hello").length, 1,
        reason: "the page must not reload");

    await backend.destroy(id);
    await sub.cancel();
    await server.close(force: true);
    stdout.writeln("DOCK-SMOKE PASS");
  });
}
