// Vommet: local data encryption, the master key on Windows, protected with
// DPAPI (CryptProtectData, current user scope) in keys/master.dpapi
// ("VDP1" + the DPAPI blob). Only this Windows user on this machine can
// unprotect it; it needs no prompt and works for every engine. The bindings
// are a few direct crypt32/kernel32 calls (no package:win32 dependency).
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_file_io.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

final class _Blob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _ProtectNative = Int32 Function(Pointer<_Blob>, Pointer<Utf16>,
    Pointer<_Blob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_Blob>);
typedef _ProtectDart = int Function(Pointer<_Blob>, Pointer<Utf16>,
    Pointer<_Blob>, Pointer<Void>, Pointer<Void>, int, Pointer<_Blob>);
typedef _UnprotectNative = Int32 Function(
    Pointer<_Blob>,
    Pointer<Pointer<Utf16>>,
    Pointer<_Blob>,
    Pointer<Void>,
    Pointer<Void>,
    Uint32,
    Pointer<_Blob>);
typedef _UnprotectDart = int Function(Pointer<_Blob>, Pointer<Pointer<Utf16>>,
    Pointer<_Blob>, Pointer<Void>, Pointer<Void>, int, Pointer<_Blob>);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

class _Dpapi {
  _Dpapi._(DynamicLibrary crypt32, DynamicLibrary kernel32)
      : protect = crypt32
            .lookupFunction<_ProtectNative, _ProtectDart>("CryptProtectData"),
        unprotect = crypt32.lookupFunction<_UnprotectNative, _UnprotectDart>(
            "CryptUnprotectData"),
        localFree = kernel32
            .lookupFunction<_LocalFreeNative, _LocalFreeDart>("LocalFree");

  static _Dpapi? _instance;
  static _Dpapi get instance => _instance ??= _Dpapi._(
      DynamicLibrary.open("crypt32.dll"), DynamicLibrary.open("kernel32.dll"));

  final _ProtectDart protect;
  final _UnprotectDart unprotect;
  final _LocalFreeDart localFree;

  static const int uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN
  static final List<int> entropy = "im.nether.chat local data key v1".codeUnits;

  Uint8List _run(List<int> input, bool protecting) {
    final inBlob = calloc<_Blob>();
    final entropyBlob = calloc<_Blob>();
    final outBlob = calloc<_Blob>();
    final inData = calloc<Uint8>(input.length);
    final entropyData = calloc<Uint8>(entropy.length);
    final description = "Vommet local data key".toNativeUtf16();
    try {
      inData.asTypedList(input.length).setAll(0, input);
      entropyData.asTypedList(entropy.length).setAll(0, entropy);
      inBlob.ref
        ..cbData = input.length
        ..pbData = inData;
      entropyBlob.ref
        ..cbData = entropy.length
        ..pbData = entropyData;
      final ok = protecting
          ? protect(inBlob, description, entropyBlob, nullptr, nullptr,
              uiForbidden, outBlob)
          : unprotect(inBlob, nullptr, entropyBlob, nullptr, nullptr,
              uiForbidden, outBlob);
      if (ok == 0) {
        throw KeyStoreException(
            protecting ? "DPAPI couldn't protect the key" : "DPAPI refused");
      }
      final out = Uint8List.fromList(
          outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
      outBlob.ref.pbData
          .asTypedList(outBlob.ref.cbData)
          .fillRange(0, outBlob.ref.cbData, 0);
      localFree(outBlob.ref.pbData.cast());
      return out;
    } finally {
      inData.asTypedList(input.length).fillRange(0, input.length, 0);
      calloc.free(inData);
      calloc.free(entropyData);
      calloc.free(inBlob);
      calloc.free(entropyBlob);
      calloc.free(outBlob);
      calloc.free(description);
    }
  }
}

class DpapiKeyStore extends MasterKeyStore {
  DpapiKeyStore(String keysDirectory)
      : _file = KeyFileIo(p.join(keysDirectory, fileName), _magic);

  static const String fileName = "master.dpapi";
  static const List<int> _magic = [0x56, 0x44, 0x50, 0x31]; // "VDP1"

  final KeyFileIo _file;

  @override
  KeyStoreKind get kind => KeyStoreKind.dpapi;

  @override
  String get name => "Windows DPAPI";

  @override
  Future<StoreAvailability> availability() async {
    if (!Platform.isWindows) return StoreAvailability.unavailable;
    try {
      _Dpapi.instance;
      return StoreAvailability.available;
    } catch (_) {
      return StoreAvailability.unavailable;
    }
  }

  @override
  Future<StoreReadResult> read({bool interactive = false}) async {
    final Uint8List? blob;
    try {
      blob = await _file.read();
    } on FileSystemException catch (e) {
      return StoreUnreachable("can't read the DPAPI key: ${e.message}");
    } on FormatException {
      return const StoreNotAKey("the DPAPI key file is damaged");
    }
    if (blob == null) return const StoreEmpty();
    try {
      final key = _Dpapi.instance._run(blob, false);
      if (key.length != KeyHierarchy.keyLength) {
        return const StoreNotAKey("the DPAPI key file is damaged");
      }
      return StoreFound(key);
    } on KeyStoreException catch (e) {
      // Another Windows user, another machine, or a reset password.
      return StoreUnreachable(e.reason);
    } catch (e) {
      return StoreUnreachable("DPAPI isn't available: ${e.runtimeType}");
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    final Uint8List blob;
    try {
      blob = _Dpapi.instance._run(key, true);
    } on KeyStoreException {
      rethrow;
    } catch (e) {
      throw KeyStoreException("DPAPI isn't available: ${e.runtimeType}");
    }
    try {
      await _file.write(blob);
    } on FileSystemException catch (e) {
      throw KeyStoreException("can't write the DPAPI key: ${e.message}");
    } on KeyFileNotPrivate {
      throw KeyStoreException(
          "the DPAPI key can't be made readable by this user only");
    }
  }

  @override
  Future<void> archive() async {
    try {
      await _file.archive();
    } on FileSystemException catch (e) {
      throw KeyStoreException("can't set the DPAPI key aside: ${e.message}");
    }
  }

  @override
  Future<List<Uint8List>> archivedKeys() async {
    final keys = <Uint8List>[];
    for (final blob in await _file.readArchives()) {
      try {
        final key = _Dpapi.instance._run(blob, false);
        if (key.length == KeyHierarchy.keyLength) keys.add(key);
      } catch (_) {}
    }
    return keys;
  }

  @override
  Future<void> pruneArchives({int keep = MasterKeyStore.archivesKept}) =>
      _file.pruneArchives(keep);

  @override
  Future<void> delete() async {
    try {
      await _file.delete();
    } on FileSystemException catch (e) {
      throw KeyStoreException("can't delete the DPAPI key: ${e.message}");
    }
  }
}
