import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';

/// Vommet: the native side lives in linux/widget_dock.cc (GTK, WebKit) and
/// windows/runner/widget_dock.cpp (Win32, WebView2); both take the same
/// calls on the same channel.
class NativeWidgetDockBackend implements WidgetDockBackend {
  NativeWidgetDockBackend._() {
    _channel.setMethodCallHandler(_onCall);
  }

  static final NativeWidgetDockBackend instance = NativeWidgetDockBackend._();

  static const _channel = MethodChannel("vommet/widget_dock");

  final _events = StreamController<WidgetDockEvent>.broadcast();

  @override
  Stream<WidgetDockEvent> get events => _events.stream;

  Future<dynamic> _onCall(MethodCall call) async {
    final args = call.arguments as Map;
    final id = args["id"] as String;
    final kind = switch (call.method) {
      "message" => WidgetDockEventKind.message,
      "poppedOut" => WidgetDockEventKind.poppedOut,
      "docked" => WidgetDockEventKind.docked,
      "focused" => WidgetDockEventKind.focused,
      "closed" => WidgetDockEventKind.closed,
      _ => null,
    };
    if (kind == null) {
      Log.w("Unknown widget dock event: ${call.method}");
      return;
    }
    _events.add(WidgetDockEvent(kind, id, message: args["message"] as String?));
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>("isAvailable") ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> create(
      {required String id,
      required String url,
      required String script,
      required String title,
      String? userAgent}) {
    return _channel.invokeMethod("create", {
      "id": id,
      "url": url,
      "script": script,
      "title": title,
      if (userAgent != null) "userAgent": userAgent,
    });
  }

  @override
  Future<void> setRect(String id, Rect rect) {
    return _channel.invokeMethod("setRect", {
      "id": id,
      "x": rect.left,
      "y": rect.top,
      "width": rect.width,
      "height": rect.height,
    });
  }

  @override
  Future<void> setVisible(String id, bool visible) =>
      _channel.invokeMethod("setVisible", {"id": id, "visible": visible});

  @override
  Future<void> evaluate(String id, String script) =>
      _channel.invokeMethod("evaluate", {"id": id, "script": script});

  @override
  Future<void> popOut(String id) => _channel.invokeMethod("popOut", {"id": id});

  @override
  Future<void> dockBack(String id) =>
      _channel.invokeMethod("dockBack", {"id": id});

  @override
  Future<Uint8List?> snapshot(String id) =>
      _channel.invokeMethod<Uint8List>("snapshot", {"id": id});

  @override
  Future<void> focusHost() => _channel.invokeMethod("focusFlutter");

  @override
  Future<void> destroy(String id) =>
      _channel.invokeMethod("destroy", {"id": id});
}
