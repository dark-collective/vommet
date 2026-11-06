import 'dart:typed_data';

/// Vommet issue 813: no HEIC decoder on the web build (no dart:io/dart:ffi).
Uint8List? decodeHeifToBmp(Uint8List bytes) => null;
