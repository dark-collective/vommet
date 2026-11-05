// Vommet: smoke test for the macOS widget dock (macos/Runner/WidgetDock.swift)
// through the real app pieces: the vommet/widget_dock channel and the
// DockedWidgetViewport platform view. No homeserver: a local page reports a
// load id; the same page (no second load) must answer page messages while
// docked in the viewport, popped out into its own window and docked back,
// with event.source == window.parent, and show in the viewport again.
//
//   flutter test integration_test/widget_dock_macos_runner.dart -d macos
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/components/widgets/docked/macos_widget_dock_backend.dart';
import 'package:commet/client/components/widgets/docked/native_widget_dock_backend.dart';
import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:commet/ui/organisms/docked_widget/docked_widget_panel.dart';
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

  testWidgets("macOS docked widget survives pop out and dock back",
      (tester) async {
    expect(WidgetDockBackend.forPlatform(), MacosWidgetDockBackend.instance);
    final backend = MacosWidgetDockBackend.instance;
    // Snapshots aren't part of the macOS backend; the native side still
    // answers them, which tells whether the view shows.
    final channel = NativeWidgetDockBackend.instance;
    expect(await backend.isAvailable(), isTrue);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_page);
      request.response.close();
    });

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
        await tester.pump();
      }
    }

    Map<String, dynamic>? ack(int n) =>
        messages.where((m) => m["kind"] == "ack" && m["n"] == n).firstOrNull;

    Future<void> ping(int n, Object loadId) async {
      await backend.evaluate(
          id, "window.onMessagePolyfill(${jsonEncode(jsonEncode({"n": n}))})");
      await until(() => ack(n) != null, "ack $n");
      expect(ack(n)!["loadId"], loadId, reason: "ack $n from the same load");
      expect(ack(n)!["source"], isTrue, reason: "event.source");
    }

    Future<void> shows(String label) async {
      final png = await tester.runAsync(() => channel.snapshot(id));
      expect(png, isNotNull, reason: "snapshot while $label");
      expect(png!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
      // The workflow captures the screen meanwhile.
      stdout.writeln("DOCK-SMOKE state: $label");
      await tester.runAsync(() => Future.delayed(const Duration(seconds: 4)));
    }

    await backend.create(
        id: id,
        url: "http://127.0.0.1:${server.port}/",
        script: await _script(),
        title: "Dock smoke");
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            backgroundColor: Color(0xff102030),
            body: Center(
                child: SizedBox(
                    width: 480,
                    height: 320,
                    child: DockedWidgetViewport(id: id))))));

    await until(() => messages.any((m) => m["kind"] == "hello"), "hello");
    final loadId = messages.firstWhere((m) => m["kind"] == "hello")["loadId"];
    stdout.writeln("DOCK-SMOKE loadId $loadId");
    await ping(1, loadId);
    await shows("docked");

    await backend.popOut(id);
    await until(
        () => kinds.contains(WidgetDockEventKind.poppedOut), "poppedOut");
    await ping(2, loadId);
    await shows("popped out");

    await backend.dockBack(id);
    await until(() => kinds.contains(WidgetDockEventKind.docked), "docked");
    await ping(3, loadId);
    await shows("docked back");

    // Another room: the viewport goes, then comes back.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 480,
                    height: 320,
                    child: DockedWidgetViewport(id: id))))));
    await tester.pump();
    await ping(4, loadId);
    await shows("after a room switch");

    expect(messages.where((m) => m["kind"] == "hello").length, 1,
        reason: "the page must not reload");

    await backend.destroy(id);
    await sub.cancel();
    await server.close(force: true);
    stdout.writeln("DOCK-SMOKE PASS");
  });
}
