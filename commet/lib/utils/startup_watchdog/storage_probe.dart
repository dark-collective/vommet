// Vommet: native builds have no browser storage quota (see
// storage_probe_web.dart).

class StorageEstimate {
  final int usage;
  final int quota;
  const StorageEstimate(this.usage, this.quota);
}

Future<StorageEstimate?> readStorageEstimate() async => null;
