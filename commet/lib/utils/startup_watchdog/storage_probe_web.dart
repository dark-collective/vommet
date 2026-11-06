// Vommet: what the browser lets this site store (navigator.storage.estimate).

import 'dart:js_interop';

import 'package:commet/utils/startup_watchdog/storage_probe.dart'
    show StorageEstimate;
import 'package:web/web.dart' as web;

export 'package:commet/utils/startup_watchdog/storage_probe.dart'
    show StorageEstimate;

Future<StorageEstimate?> readStorageEstimate() async {
  try {
    final e = await web.window.navigator.storage.estimate().toDart;
    // IndexedDB-era numbers can come back as doubles under dart2wasm.
    return StorageEstimate(e.usage.toInt(), e.quota.toInt());
  } catch (_) {
    return null;
  }
}
