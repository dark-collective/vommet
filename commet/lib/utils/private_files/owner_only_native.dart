import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:commet/debug/log.dart';
import 'package:ffi/ffi.dart';

typedef _ChmodNative = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Uint32);
typedef _ChmodDart = int Function(ffi.Pointer<Utf8>, int);
typedef _GetuidNative = ffi.Uint32 Function();
typedef _GetuidDart = int Function();
typedef _LstatNative = ffi.Int32 Function(
    ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>);
typedef _LstatDart = int Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>);
typedef _LxstatNative = ffi.Int32 Function(
    ffi.Int32, ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>);
typedef _LxstatDart = int Function(
    int, ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>);

/// Vommet: makes a directory 0700 or a file 0600, so only the user running
/// the app can read the media kept there. dart:io has no chmod, so libc's is
/// called through dart:ffi (Linux, macOS, Android, iOS). Windows has no
/// modes: there the per-user profile's ACLs already keep other users out.
class OwnerOnly {
  static _ChmodDart? _chmod;
  static bool _unavailable = false;

  static _ChmodDart? _lookup() {
    if (_chmod != null || _unavailable) return _chmod;
    try {
      _chmod = ffi.DynamicLibrary.process()
          .lookupFunction<_ChmodNative, _ChmodDart>("chmod");
    } catch (error) {
      _unavailable = true;
      Log.w("chmod unavailable, private files keep the default mode: $error");
    }
    return _chmod;
  }

  /// 0700 on [path]. True when the mode was set (always false on Windows).
  static Future<bool> directory(String path) async => _set(path, 0x1C0);

  /// 0600 on [path]. True when the mode was set (always false on Windows).
  static Future<bool> file(String path) async => _set(path, 0x180);

  /// Whether only the owner can get at [path]: no group or other
  /// permission bits (read from the file system, so a failed or unavailable
  /// chmod shows). Always true on Windows, whose per-user profile ACLs keep
  /// other users out; false when [path] can't be read.
  static Future<bool> isOwnerOnly(String path) async {
    if (Platform.isWindows) return true;
    try {
      final stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.notFound) return false;
      return stat.mode & 0x3F == 0;
    } catch (_) {
      return false;
    }
  }

  static _GetuidDart? _getuid;
  static _LstatDart? _lstat;
  static bool _noOwners = false;

  /// Where st_uid sits in glibc's struct stat, for the Linux ABIs whose
  /// layout is known. Elsewhere [ownerOf] answers null.
  static int? get _uidOffset => switch (ffi.Abi.current()) {
        ffi.Abi.linuxX64 => 28,
        ffi.Abi.linuxArm64 => 24,
        _ => null,
      };

  /// glibc's struct stat version for __lxstat (_STAT_VER), per ABI.
  static int? get _statVersion => switch (ffi.Abi.current()) {
        ffi.Abi.linuxX64 => 1,
        ffi.Abi.linuxArm64 => 0,
        _ => null,
      };

  /// Whether [ownerOf] can answer here: Linux on x64 and arm64, with lstat
  /// (glibc 2.33 or newer, musl) or glibc's older __lxstat.
  static bool get checksOwners {
    if (!Platform.isLinux || _uidOffset == null || _noOwners) return false;
    if (_getuid != null && _lstat != null) return true;
    try {
      final lib = ffi.DynamicLibrary.process();
      _getuid = lib.lookupFunction<_GetuidNative, _GetuidDart>("getuid");
      try {
        _lstat = lib.lookupFunction<_LstatNative, _LstatDart>("lstat");
      } catch (_) {
        // glibc before 2.33 exports lstat only as __lxstat(version, ...).
        final lxstat =
            lib.lookupFunction<_LxstatNative, _LxstatDart>("__lxstat");
        final version = _statVersion!;
        _lstat = (path, buffer) => lxstat(version, path, buffer);
      }
      return true;
    } catch (error) {
      _getuid = null;
      _noOwners = true;
      Log.w("lstat unavailable, file owners can't be checked: $error");
      return false;
    }
  }

  /// The user id the app runs as (Linux only, see [checksOwners]).
  static int? currentUid() => checksOwners ? _getuid!() : null;

  /// The user id owning [path] itself (a link is not followed), or null when
  /// it can't be told (see [checksOwners]) or [path] is missing.
  static int? ownerOf(String path) {
    if (!checksOwners) return null;
    final native = path.toNativeUtf8();
    // Bigger than any struct stat.
    final buffer = malloc<ffi.Uint8>(512);
    try {
      if (_lstat!(native, buffer) != 0) return null;
      return buffer.cast<ffi.Uint32>()[_uidOffset! ~/ 4];
    } finally {
      malloc.free(native);
      malloc.free(buffer);
    }
  }

  static bool _set(String path, int mode) {
    if (Platform.isWindows) return false;
    final chmod = _lookup();
    if (chmod == null) return false;
    final native = path.toNativeUtf8();
    try {
      final result = chmod(native, mode);
      if (result != 0) Log.w("chmod ${mode.toRadixString(8)} failed: $path");
      return result == 0;
    } finally {
      malloc.free(native);
    }
  }
}
