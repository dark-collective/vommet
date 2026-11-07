// Vommet: platform calls (Dart -> native over a platform channel) that were
// waiting for their reply while the UI isolate's event loop was blocked.
//
// On Linux the UI isolate runs on GTK's main thread (Flutter 3.41's default),
// so a plugin's or the app's own native handler that blocks there (a
// synchronous D-Bus call, a slow GTK call) blocks the Dart event loop as
// well, with no Dart code running: MainSpans then sees "none". Every message
// the app sends to the platform goes through the binding's messenger, so a
// wrapper around it knows which calls were in flight. A call still waiting
// when the loop starts again was waiting through the whole block (no Dart
// ran to send one), which makes it the prime suspect: Stall_pending_<call>.
// Replies that took a second or more are counted too (Platform_slow_<call>),
// which shows the same handlers when the UI isolate runs on its own thread.
//
// Names are code identifiers only: the channel's last path part and, for a
// method call, the method's name (only when the message decodes as a method
// call envelope). Only while diagnostics are on (MainSpans.enabled).

import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/telemetry/main_spans.dart';
import 'package:flutter/services.dart';

class PlatformCalls {
  static final Map<int, _Call> _pending = {};
  static int _nextId = 0;

  /// A reply this slow is counted as Platform_slow_<call>.
  static const slowUs = 1000000;

  /// Distinct call names kept; later ones are "other".
  static const maxNames = 40;
  static final Set<String> _names = {};

  static final Stopwatch _clock = Stopwatch()..start();

  static void install() {
    MainSpans.pendingCalls = pendingNames;
  }

  /// A call waiting this long is dropped (a dialog the user keeps open, a
  /// handler that never replies): it would be blamed for every block.
  static const staleUs = 10 * 60 * 1000000;

  /// The calls waiting for a reply, by name (each name once).
  static List<String> pendingNames() {
    final now = _clock.elapsedMicroseconds;
    _pending.removeWhere((_, c) => now - c.startUs > staleUs);
    return {for (final c in _pending.values) c.name}.toList();
  }

  static int start(String channel, ByteData? message) {
    final id = _nextId++;
    _pending[id] = _Call(label(channel, message), _clock.elapsedMicroseconds);
    return id;
  }

  static void end(int id) {
    final call = _pending.remove(id);
    if (call == null) return;
    final us = _clock.elapsedMicroseconds - call.startUs;
    if (us >= slowUs) MainSpans.note("Platform_slow_${call.name}", 1, us);
  }

  /// For tests.
  static void reset() {
    _pending.clear();
    _names.clear();
  }

  static final _bad = RegExp(r"[^A-Za-z0-9_]+");
  static final _idLike = RegExp(r"[0-9]{3,}|[0-9a-fA-F]{8,}");
  static final _method = RegExp(r"^[A-Za-z][A-Za-z0-9_.]{0,63}$");

  /// `<channel>` or `<channel>__<method>`: at most 40 characters of
  /// `[A-Za-z0-9_]`, starting with a letter.
  static String label(String channel, ByteData? message) {
    var name = _channelName(channel);
    final method = _methodName(message);
    if (method != null) name = "${name}__$method";
    if (name.length > 40) name = name.substring(0, 40);
    if (!_names.contains(name)) {
      if (_names.length >= maxNames) return "other";
      _names.add(name);
    }
    return name;
  }

  static String _channelName(String channel) {
    // The last path part that is not an id (renderer/1234, uuid…). Pigeon
    // channels (dev.flutter.pigeon.<plugin>.<Api>.<method>) keep the last
    // two dotted parts.
    final parts = channel.split("/").where((p) => !_idLike.hasMatch(p));
    var last = parts.isEmpty ? "" : parts.last;
    if (last.startsWith("dev.flutter.pigeon.")) {
      final dotted = last.split(".");
      last = dotted.skip(dotted.length - 2).join("_");
    }
    var name =
        last.replaceAll(_bad, "_").replaceAll(RegExp(r"^[^A-Za-z]+"), "");
    name = name.replaceAll(RegExp(r"_+$"), "");
    if (name.isEmpty) return "channel";
    return name.length > 24 ? name.substring(0, 24) : name;
  }

  // Only the method name is read, never the arguments: a standard codec
  // method call starts with its name as a string value (type 7, a size,
  // UTF-8), a JSON one is an object with a "method" string.
  static String? _methodName(ByteData? message) {
    if (message == null || message.lengthInBytes < 2) return null;
    String? method;
    try {
      final first = message.getUint8(0);
      if (first == 7) {
        var size = message.getUint8(1);
        var at = 2;
        if (size == 254) {
          size = message.getUint16(2, Endian.host);
          at = 4;
        } else if (size == 255) {
          size = message.getUint32(2, Endian.host);
          at = 6;
        }
        if (size > 64 || at + size > message.lengthInBytes) return null;
        method = utf8.decode(
            message.buffer.asUint8List(message.offsetInBytes + at, size));
      } else if (first == 0x7B && message.lengthInBytes <= 65536) {
        final decoded = json.decode(utf8.decode(message.buffer
            .asUint8List(message.offsetInBytes, message.lengthInBytes)));
        if (decoded is Map && decoded["method"] is String) {
          method = decoded["method"] as String;
        }
      }
    } catch (_) {
      return null;
    }
    if (method == null || !_method.hasMatch(method)) return null;
    var name = method.replaceAll(".", "_");
    if (name.length > 20) name = name.substring(0, 20);
    return name;
  }
}

class _Call {
  _Call(this.name, this.startUs);
  final String name;
  final int startUs;
}

/// The binding's messenger, keeping [PlatformCalls] up to date.
class TimedBinaryMessenger implements BinaryMessenger {
  TimedBinaryMessenger(this._inner);

  final BinaryMessenger _inner;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (!MainSpans.enabled) return _inner.send(channel, message);
    final id = PlatformCalls.start(channel, message);
    final Future<ByteData?>? reply;
    try {
      reply = _inner.send(channel, message);
    } catch (_) {
      PlatformCalls.end(id);
      rethrow;
    }
    if (reply == null) {
      PlatformCalls.end(id);
      return null;
    }
    // whenComplete passes the reply (or its error) on unchanged.
    return reply.whenComplete(() => PlatformCalls.end(id));
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      _inner.setMessageHandler(channel, handler);

  @override
  // ignore: deprecated_member_use
  Future<void> handlePlatformMessage(String channel, ByteData? data,
          PlatformMessageResponseCallback? callback) =>
      // ignore: deprecated_member_use
      _inner.handlePlatformMessage(channel, data, callback);
}
