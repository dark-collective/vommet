// Vommet: the spellcheck engine (spellbook, in rust/rust/src/spellcheck.rs),
// called over plain FFI like the voice filter. Dictionaries are referred to by
// their native address so a background isolate can open them and the UI
// isolate can use them.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:commet/rust/frb_generated.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

class SpellcheckNative {
  final ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int) _open;
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int) _check;
  final ffi.Pointer<Utf8> Function(
      ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int, int) _suggest;
  final void Function(ffi.Pointer<Utf8>) _freeString;
  final void Function(ffi.Pointer<ffi.Void>) _close;

  SpellcheckNative._(ffi.DynamicLibrary lib)
      : _open = lib.lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, ffi.Size,
                ffi.Pointer<ffi.Uint8>, ffi.Size),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, int,
                ffi.Pointer<ffi.Uint8>, int)>("vommet_spell_open"),
        _check = lib.lookupFunction<
            ffi.Int32 Function(
                ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size),
            int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>,
                int)>("vommet_spell_check"),
        _suggest = lib.lookupFunction<
            ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Size),
            ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Uint8>, int, int)>("vommet_spell_suggest"),
        _freeString = lib.lookupFunction<ffi.Void Function(ffi.Pointer<Utf8>),
            void Function(ffi.Pointer<Utf8>)>("vommet_spell_free_string"),
        _close = lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)>("vommet_spell_close");

  static SpellcheckNative? _instance;

  /// Set once [load] has finished in this isolate.
  static SpellcheckNative? get instance => _instance;

  static Future<SpellcheckNative> load() async {
    return _instance ??= SpellcheckNative._(
        (await loadExternalLibrary(RustLib.kDefaultExternalLibraryLoaderConfig))
            .ffiDynamicLibrary);
  }

  static T _withBytes<T>(
      List<int> bytes, T Function(ffi.Pointer<ffi.Uint8> ptr, int len) f) {
    final ptr = malloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return f(ptr, bytes.length);
    } finally {
      malloc.free(ptr);
    }
  }

  /// The dictionary's address, or 0 if it couldn't be parsed.
  int open(Uint8List aff, Uint8List dic) {
    return _withBytes(
        aff,
        (affPtr, affLen) => _withBytes(dic,
            (dicPtr, dicLen) => _open(affPtr, affLen, dicPtr, dicLen).address));
  }

  /// 1 = correct, 0 = misspelled, -1 = couldn't check.
  int check(int dictionary, String word) {
    return _withBytes(utf8.encode(word),
        (ptr, len) => _check(ffi.Pointer.fromAddress(dictionary), ptr, len));
  }

  List<String> suggest(int dictionary, String word, int max) {
    final result = _withBytes(
        utf8.encode(word),
        (ptr, len) =>
            _suggest(ffi.Pointer.fromAddress(dictionary), ptr, len, max));
    if (result.address == 0) return const [];
    try {
      return result
          .toDartString()
          .split("\n")
          .where((s) => s.isNotEmpty)
          .toList();
    } finally {
      _freeString(result);
    }
  }

  void close(int dictionary) {
    _close(ffi.Pointer.fromAddress(dictionary));
  }

  /// Reads and parses a dictionary off the UI isolate (large ones take ~0.1 s).
  static Future<int> openFiles(String affPath, String dicPath) {
    return Isolate.run(() async {
      final native = await load();
      return native.open(
          File(affPath).readAsBytesSync(), File(dicPath).readAsBytesSync());
    });
  }

  /// Suggestions from each dictionary in turn, off the UI isolate.
  static Future<List<List<String>>> suggestIn(
      List<int> dictionaries, String word, int max) {
    return Isolate.run(() async {
      final native = await load();
      return [for (final d in dictionaries) native.suggest(d, word, max)];
    });
  }
}
