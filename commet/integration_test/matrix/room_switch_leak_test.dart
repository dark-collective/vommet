// Vommet issue 345: switching rooms gets slower the longer the app stays open.
//
// Every room opened left its whole view behind (chat, timeline view with a
// key per event, header menu), kept alive by listeners on app-wide streams
// that were never cancelled; each later event on those streams ran in all of
// them. This opens a few rooms over and over and checks, with the VM
// service's instance counts after a full GC, that only the open room's view
// is still alive. It also logs switch times per batch.
//
// Run on its own: .vommet/it/run.sh integration_test/room_switch_runner.dart

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service.dart' as vm;
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart' as vm_io;

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

void _log(String s) {
  // ignore: avoid_print
  print("ROOMSWITCH $s");
}

class _Api {
  _Api(this.base);
  final Uri base;
  final HttpClient _http = HttpClient();
  String? token;
  int _txn = 0;

  Future<Map<String, dynamic>> call(String method, String path,
      [Object? body]) async {
    var request = await _http.openUrl(method, base.resolve(path));
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.add("Authorization", "Bearer $token");
    if (body != null) request.write(jsonEncode(body));
    var response = await request.close();
    var text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception("$method $path -> ${response.statusCode} $text");
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> login(String user, String password) async {
    var result = await call("POST", "/_matrix/client/v3/login", {
      "type": "m.login.password",
      "identifier": {"type": "m.id.user", "user": user},
      "password": password,
    });
    token = result["access_token"] as String;
  }

  Future<String> createRoom(String name) async =>
      (await call("POST", "/_matrix/client/v3/createRoom", {
        "preset": "public_chat",
        "name": name,
      }))["room_id"] as String;

  Future<void> send(String room, String body) => call(
      "PUT",
      "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/send/m.room.message/"
          "${DateTime.now().microsecondsSinceEpoch}-${_txn++}",
      {"msgtype": "m.text", "body": body});
}

/// Live instance counts per class name, after a full GC.
Future<Map<String, int>> _liveCounts(
    vm.VmService service, String isolateId, Set<String> classes) async {
  final p = await service.getAllocationProfile(isolateId, gc: true);
  final out = {for (final c in classes) c: 0};
  for (final m in p.members ?? const <vm.ClassHeapStats>[]) {
    final name = m.classRef?.name;
    final uri = m.classRef?.library?.uri ?? "";
    if (name == null || !classes.contains(name)) continue;
    if (!uri.startsWith("package:commet/")) continue;
    out[name] = out[name]! + (m.instancesCurrent ?? 0);
  }
  return out;
}

const _views = {
  "ChatState",
  "RoomTimelineWidgetViewState",
  "_RoomQuickAccessMenuViewDesktopState",
};

void main() {
  testWidgets("room views are released after switching (Vommet issue 345)",
      (tester) async {
    final info = await developer.Service.getInfo();
    final uri = info.serverWebSocketUri;
    if (uri == null) {
      markTestSkipped("no VM service");
      return;
    }
    final service = await vm_io.vmServiceConnectUri(uri.toString());
    addTearDown(service.dispose);
    final isolates = (await service.getVM()).isolates!;
    final isolateId = isolates
        .firstWhere((i) => i.name?.contains("main") ?? false,
            orElse: () => isolates.first)
        .id!;

    final tag = RandomUtils.getRandomString(6).toLowerCase();
    final me = _Api(Uri.https(tester.homeserver));
    await me.login(tester.username, tester.password);
    final rooms = <String>[];
    for (var i = 0; i < 3; i++) {
      final r = await me.createRoom("Room switch $i $tag");
      for (var m = 0; m < 10; m++) {
        await me.send(r, "message $m in room $i");
      }
      rooms.add(r);
    }

    final app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();
    final client = app.clientManager.clients.first;
    await tester.waitFor(() => rooms.every(client.hasRoom),
        timeout: const Duration(seconds: 60), skipPumpAndSettle: true);

    var switches = 0;
    Future<void> switchRooms(int n) async {
      final times = <int>[];
      for (var s = 0; s < n; s++) {
        final clock = Stopwatch()..start();
        EventBus.doOpenRoom(rooms[switches++ % rooms.length],
            clientId: client.identifier);
        await tester.pump();
        await tester.pump();
        for (var w = 0;
            w < 100 && find.byType(MessageInput).evaluate().isEmpty;
            w++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        times.add(clock.elapsedMicroseconds);
        await tester.pump(const Duration(milliseconds: 50));
      }
      times.sort();
      _log("after $switches switches: switch ms "
          "p50=${(times[times.length ~/ 2] / 1000).toStringAsFixed(1)} "
          "max=${(times.last / 1000).toStringAsFixed(1)}");
    }

    await switchRooms(6);
    final before = await _liveCounts(service, isolateId, _views);
    _log("live views after $switches switches: $before");
    await switchRooms(30);
    final after = await _liveCounts(service, isolateId, _views);
    _log("live views after $switches switches: $after");

    for (final c in _views) {
      // The open room's view, and at most one more still being torn down.
      expect(after[c], lessThanOrEqualTo(2),
          reason: "$c: ${after[c]} alive after $switches room switches "
              "(${before[c]} after 6)");
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
