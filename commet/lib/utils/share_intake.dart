import 'dart:async';
import 'dart:io';

import 'package:commet/client/room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/share_target/share_target_dialog.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/services.dart';

/// One file another app shared into Vommet, already copied into the cache.
class SharedFile {
  const SharedFile(
      {required this.path, required this.name, this.mimeType, this.size});

  final String path;
  final String name;
  final String? mimeType;
  final int? size;

  /// Size, plus the bytes when small enough to hold in memory (same 50 MB
  /// cut-off as dropped files; larger ones are read from [path] on send).
  Future<(int, Uint8List?)> read() async {
    final f = File(path);
    final length = size ?? await f.length();
    return (length, length < 50000000 ? await f.readAsBytes() : null);
  }
}

/// What one share sheet hand-off carried: files, text (links), or both.
class SharePayload {
  const SharePayload({this.files = const [], this.text});

  final List<SharedFile> files;
  final String? text;

  bool get isEmpty => files.isEmpty && (text == null || text!.trim().isEmpty);

  static SharePayload fromChannel(Map<dynamic, dynamic> map) {
    final files = (map["files"] as List<dynamic>? ?? [])
        .whereType<Map<dynamic, dynamic>>()
        .where((f) => f["path"] is String)
        .map((f) => SharedFile(
              path: f["path"] as String,
              name: f["name"] as String? ?? "shared",
              mimeType: f["mime"] as String?,
              size: (f["size"] as num?)?.toInt(),
            ))
        .toList();
    return SharePayload(files: files, text: map["text"] as String?);
  }
}

/// Vommet: Android share target. ShareReceiverActivity (Kotlin) queues what
/// other apps share; this pulls it over `im.nether.vommet/share`, lets the
/// user pick a room, opens it and hands the payload to that room's [Chat],
/// which adds the files as attachments and the text to the composer.
class ShareIntake {
  static const _channel = MethodChannel("im.nether.vommet/share");

  static final List<SharePayload> _queue = [];
  static bool _picking = false;

  /// Payload waiting for its room's chat to open, keyed by room.
  static (Room, SharePayload)? _delivery;
  static final StreamController<Room> _delivered = StreamController.broadcast();

  /// Fires when a payload was assigned to a room; an already open [Chat] for
  /// that room claims it with [claim].
  static Stream<Room> get onDelivered => _delivered.stream;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == "sharesAvailable") await _pull();
    });
    _pull();
  }

  static Future<void> _pull() async {
    try {
      final list = await _channel.invokeListMethod<dynamic>("takePending");
      for (final item in list ?? const []) {
        if (item is! Map) continue;
        final payload = SharePayload.fromChannel(item);
        if (!payload.isEmpty) _queue.add(payload);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to read shared content");
    }
    _showNext();
  }

  static Future<void> _showNext() async {
    if (_picking || _queue.isEmpty) return;
    _picking = true;
    try {
      // Wait for the main window and the room list; a share can cold-start
      // the app.
      for (var i = 0; i < 240; i++) {
        if (navigator.currentContext != null &&
            clientManager?.rooms.isNotEmpty == true) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      final context = navigator.currentContext;
      if (context == null || clientManager?.rooms.isNotEmpty != true) {
        Log.w("Dropping shared content: no rooms available");
        _queue.clear();
        return;
      }

      final payload = _queue.removeAt(0);
      // ignore: use_build_context_synchronously
      final room = await ShareTargetDialog.show(context, payload);
      if (room != null) deliver(room, payload);
    } finally {
      _picking = false;
    }
    if (_queue.isNotEmpty) _showNext();
  }

  static void deliver(Room room, SharePayload payload) {
    _delivery = (room, payload);
    EventBus.doOpenRoom(room.identifier, clientId: room.client.identifier);
    _delivered.add(room);
  }

  /// Takes the payload meant for [room], if any (at most once).
  static SharePayload? claim(Room room) {
    final d = _delivery;
    if (d == null) return null;
    if (d.$1.identifier != room.identifier ||
        d.$1.client.identifier != room.client.identifier) {
      return null;
    }
    _delivery = null;
    return d.$2;
  }
}
