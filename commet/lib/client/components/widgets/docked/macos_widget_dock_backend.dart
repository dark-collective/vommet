import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:commet/client/components/widgets/docked/widget_dock.dart';

/// Vommet: placeholder until the macOS dock lands (its own topic replaces
/// this file). [supported] keeps the experiment hidden on macOS until then.
class MacosWidgetDockBackend implements WidgetDockBackend {
  MacosWidgetDockBackend._();

  static const bool supported = false;

  static final MacosWidgetDockBackend instance = MacosWidgetDockBackend._();

  @override
  Stream<WidgetDockEvent> get events => const Stream.empty();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> create(
      {required String id,
      required String url,
      required String script,
      required String title,
      String? userAgent}) async {}

  @override
  Future<void> setRect(String id, Rect rect) async {}

  @override
  Future<void> setVisible(String id, bool visible) async {}

  @override
  Future<void> evaluate(String id, String script) async {}

  @override
  Future<void> popOut(String id) async {}

  @override
  Future<void> dockBack(String id) async {}

  @override
  Future<Uint8List?> snapshot(String id) async => null;

  @override
  Future<void> focusHost() async {}

  @override
  Future<void> destroy(String id) async {}
}
