// Vommet: web stand-in for disk_space_native.dart. The browser has no file
// system to measure or fsync: free space is unknown, syncing is a no-op.
class DiskSpace {
  static int? freeBytes(String path) => null;

  static void Function(String path)? debugOnSyncDirectory;

  static void syncDirectory(String path) {
    debugOnSyncDirectory?.call(path);
  }
}
