// Vommet: free disk space and directory fsync, for the local data
// encryption migration. Native platforms only (dart:ffi); a few direct libc
// and kernel32 calls, no plugin.
//
// Everything here is best effort: when the free space can't be read (an
// unknown platform, a 32-bit build, a failing call) [DiskSpace.freeBytes]
// returns null and the caller goes on, relying on SQLITE_FULL / I/O errors.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _StatNative = Int32 Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _StatDart = int Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FdNative = Int32 Function(Int32);
typedef _FdDart = int Function(int);
typedef _FreeSpaceNative = Int32 Function(
    Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _FreeSpaceDart = int Function(
    Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

class DiskSpace {
  /// Bytes available to this (unprivileged) user on the file system that
  /// holds [path] (an existing file or directory), or null when unknown.
  static int? freeBytes(String path) {
    try {
      if (Platform.isWindows) return _windowsFree(path);
      if (sizeOf<IntPtr>() != 8) return null;
      if (Platform.isLinux || Platform.isAndroid) return _statvfsFree(path);
      if (Platform.isMacOS || Platform.isIOS) return _statfsFree(path);
    } catch (_) {}
    return null;
  }

  /// For tests: called with every directory [syncDirectory] syncs.
  static void Function(String path)? debugOnSyncDirectory;

  /// fsyncs the directory [path] so a rename in it is durable (POSIX; a
  /// no-op on Windows, where renames are journaled by NTFS). Never throws.
  static void syncDirectory(String path) {
    debugOnSyncDirectory?.call(path);
    if (Platform.isWindows) return;
    try {
      final libc = DynamicLibrary.process();
      final open = libc.lookupFunction<_OpenNative, _OpenDart>("open");
      final fsync = libc.lookupFunction<_FdNative, _FdDart>("fsync");
      final close = libc.lookupFunction<_FdNative, _FdDart>("close");
      final native = path.toNativeUtf8();
      try {
        // O_RDONLY is 0 on every POSIX platform.
        final fd = open(native, 0);
        if (fd < 0) return;
        fsync(fd);
        close(fd);
      } finally {
        malloc.free(native);
      }
    } catch (_) {}
  }

  // glibc and bionic, 64-bit: struct statvfs starts with unsigned long
  // f_bsize, f_frsize, then fsblkcnt_t f_blocks, f_bfree, f_bavail.
  static int? _statvfsFree(String path) {
    final statvfs = DynamicLibrary.process()
        .lookupFunction<_StatNative, _StatDart>("statvfs");
    return _withBuffer(path, statvfs, (buf) {
      final frsize = buf.cast<Uint64>()[1];
      final avail = buf.cast<Uint64>()[4];
      return frsize * avail;
    });
  }

  // Darwin, 64-bit inodes: struct statfs starts with uint32_t f_bsize,
  // int32_t f_iosize, then uint64_t f_blocks, f_bfree, f_bavail.
  static int? _statfsFree(String path) {
    final name = Abi.current() == Abi.macosX64 ? r"statfs$INODE64" : "statfs";
    final statfs =
        DynamicLibrary.process().lookupFunction<_StatNative, _StatDart>(name);
    return _withBuffer(path, statfs, (buf) {
      final bsize = buf.cast<Uint32>()[0];
      final avail = buf.cast<Uint64>()[3];
      return bsize * avail;
    });
  }

  static int? _withBuffer(
      String path, _StatDart call, int Function(Pointer<Uint8> buffer) read) {
    // Larger than either struct (statfs is 2168 bytes on Darwin).
    const size = 4096;
    final buffer = calloc<Uint8>(size);
    final native = path.toNativeUtf8();
    try {
      if (call(native, buffer) != 0) return null;
      final free = read(buffer);
      return free < 0 ? null : free;
    } finally {
      calloc.free(buffer);
      malloc.free(native);
    }
  }

  static int? _windowsFree(String path) {
    final getFree = DynamicLibrary.open("kernel32.dll")
        .lookupFunction<_FreeSpaceNative, _FreeSpaceDart>(
            "GetDiskFreeSpaceExW");
    final dir =
        FileSystemEntity.isDirectorySync(path) ? path : File(path).parent.path;
    final native = dir.toNativeUtf16();
    final available = calloc<Uint64>();
    try {
      if (getFree(native, available, nullptr, nullptr) == 0) return null;
      return available.value;
    } finally {
      calloc.free(available);
      malloc.free(native);
    }
  }
}
