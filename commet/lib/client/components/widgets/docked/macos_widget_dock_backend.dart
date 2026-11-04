import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:commet/client/components/widgets/docked/native_widget_dock_backend.dart';
import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:flutter/foundation.dart';

/// Vommet: the AppKit side lives in macos/Runner/WidgetDock.swift. It
/// answers the same `vommet/widget_dock` calls as Linux and Windows, so this
/// reuses their channel client. Only the view differs: a docked widget is
/// the platform view [viewType] (DockedWidgetViewport), which Flutter
/// places and draws its own UI over, so rects, visibility and snapshots
/// aren't needed.
class MacosWidgetDockBackend implements WidgetDockBackend {
  MacosWidgetDockBackend._();

  static const bool supported = true;

  static final MacosWidgetDockBackend instance = MacosWidgetDockBackend._();

  static const viewType = "vommet/widget_dock_view";

  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  final WidgetDockBackend _channel = NativeWidgetDockBackend.instance;

  @override
  Stream<WidgetDockEvent> get events => _channel.events;

  @override
  Future<bool> isAvailable() => _channel.isAvailable();

  @override
  Future<void> create(
          {required String id,
          required String url,
          required String script,
          required String title,
          String? userAgent}) =>
      _channel.create(
          id: id, url: url, script: script, title: title, userAgent: userAgent);

  @override
  Future<void> setRect(String id, Rect rect) async {}

  @override
  Future<void> setVisible(String id, bool visible) async {}

  @override
  Future<void> evaluate(String id, String script) =>
      _channel.evaluate(id, script);

  @override
  Future<void> popOut(String id) => _channel.popOut(id);

  @override
  Future<void> dockBack(String id) => _channel.dockBack(id);

  @override
  Future<Uint8List?> snapshot(String id) async => null;

  @override
  Future<void> focusHost() => _channel.focusHost();

  @override
  Future<void> destroy(String id) => _channel.destroy(id);
}
