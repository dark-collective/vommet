// Vommet: PlatformCalls names the platform calls waiting for a reply while
// the UI isolate's loop was blocked (Stall_pending_*) and the slow ones
// (Platform_slow_*), by channel and method name only.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/telemetry/platform_calls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MainSpans.reset();
    PlatformCalls.reset();
  });

  ByteData call(String method, [Object? args]) =>
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));

  test("a channel and method make the name", () {
    expect(PlatformCalls.label("flutter/platform", call("Clipboard.getData")),
        "platform__Clipboard_getData");
    expect(
        PlatformCalls.label(
            "plugins.flutter.io/window_manager", call("setTitle", "x")),
        "window_manager__setTitle");
    expect(
        PlatformCalls.label(
            "dev.flutter.pigeon.url_launcher_linux.UrlLauncherApi.launchUrl",
            null),
        "UrlLauncherApi_launchUrl");
    expect(
        PlatformCalls.label(
            "flutter/textinput",
            const JSONMethodCodec()
                .encodeMethodCall(const MethodCall("TextInput.show"))),
        "textinput__TextInput_show");
  });

  test("ids in a channel name are left out", () {
    expect(PlatformCalls.label("app/renderer/12345", null), "renderer");
    expect(PlatformCalls.label("app/0123abcd4567ef", null), "app");
    expect(PlatformCalls.label("///", null), "channel");
  });

  test("a message that is not a method call is not read", () {
    // A plain string message (for instance text being sent) is not a name.
    final text = const StringCodec().encodeMessage("hello there friend")!;
    expect(PlatformCalls.label("flutter/lifecycle", text), "lifecycle");
    final json = const JSONMessageCodec().encodeMessage({"secret": "x"})!;
    expect(PlatformCalls.label("flutter/keyevent", json), "keyevent");
    // A method name that is not an identifier is left out.
    expect(PlatformCalls.label("a/b", call("not a name")), "b");
    expect(
        PlatformCalls.label("a/b",
            ByteData.view(Uint8List.fromList(utf8.encode("garbage")).buffer)),
        "b");
    // Raw bytes that look like a huge standard-codec list are not decoded.
    final raw = Uint8List.fromList([12, 255, 255, 255, 255, 127, 1, 2]);
    expect(PlatformCalls.label("a/b", ByteData.view(raw.buffer)), "b");
    // Only the name of a standard method call is read, not its arguments.
    final big = call("setText", {"text": "x" * 70000});
    expect(PlatformCalls.label("a/b", big), "b__setText");
    // A method name in a view into a larger buffer.
    final bytes = call("show").buffer.asUint8List();
    final padded = Uint8List(bytes.length + 3)
      ..setRange(3, 3 + bytes.length, bytes);
    expect(
        PlatformCalls.label(
            "a/b", ByteData.view(padded.buffer, 3, bytes.length)),
        "b__show");
  });

  test("names are capped in length and number", () {
    final long = PlatformCalls.label("x/${"z" * 50}", call("m${"q" * 40}"));
    expect(long, "${"z" * 24}__m${"q" * 13}");
    expect(MainSpans.nameRe64.hasMatch("Stall_pending_$long"), isTrue);
    for (var i = 0; i < PlatformCalls.maxNames + 5; i++) {
      PlatformCalls.label("ch/c$i", null);
    }
    expect(PlatformCalls.label("ch/new", null), "other");
  });

  test("pending calls are listed once each until they reply", () {
    final a = PlatformCalls.start("p/tray", call("setIcon"));
    final b = PlatformCalls.start("p/tray", call("setIcon"));
    final c = PlatformCalls.start("p/menu", null);
    expect(PlatformCalls.pendingNames()..sort(), ["menu", "tray__setIcon"]);
    PlatformCalls.end(a);
    PlatformCalls.end(c);
    expect(PlatformCalls.pendingNames(), ["tray__setIcon"]);
    PlatformCalls.end(b);
    PlatformCalls.end(b); // twice: no harm
    expect(PlatformCalls.pendingNames(), isEmpty);
    // Fast replies are not counted as slow.
    expect(
        MainSpans.sinceLaunch()
            .where((t) => "${t["name"]}".startsWith("Platform_slow_")),
        isEmpty);
  });

  test("the messenger passes calls and replies through unchanged", () async {
    MainSpans.enabled = true;
    addTearDown(() => MainSpans.enabled = false);
    final inner = _FakeMessenger();
    final timed = TimedBinaryMessenger(inner);
    final reply = timed.send("p/tray", call("setIcon"));
    expect(PlatformCalls.pendingNames(), ["tray__setIcon"]);
    inner.reply.complete(ByteData(1));
    expect((await reply)!.lengthInBytes, 1);
    expect(PlatformCalls.pendingNames(), isEmpty);

    inner.reply = Completer();
    final failing = timed.send("p/tray", null);
    inner.reply.completeError(PlatformException(code: "x"));
    await expectLater(failing, throwsA(isA<PlatformException>()));
    expect(PlatformCalls.pendingNames(), isEmpty);
  });
}

class _FakeMessenger implements BinaryMessenger {
  Completer<ByteData?> reply = Completer();

  @override
  Future<ByteData?>? send(String channel, ByteData? message) => reply.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
