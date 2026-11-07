import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/utils/image/heif_decode_stub.dart'
    if (dart.library.io) 'package:commet/utils/image/heif_decode_ffi.dart'
    as native;

/// Vommet issue 813: HEIC/HEIF pictures on desktop. The Flutter engine has
/// no HEIC decoder outside Android, so on Linux (the system's libheif) and
/// Windows (WIC with Microsoft's HEIF and HEVC extensions) the picture is
/// decoded here into a BMP the engine can read. Nothing is bundled: where the
/// system has no working decoder this returns null and the picture keeps the
/// thumbnail-only path or a file tile (see PlatformImageTypes).
///
/// Synchronous and slow for big photos; run it with `compute`.
Uint8List? decodeHeifToBmp(Uint8List bytes) => native.decodeHeifToBmp(bytes);

/// Whether [bytes] start like a HEIC/HEIF file (an ISO-BMFF `ftyp` box with
/// a HEIF brand).
bool looksLikeHeif(Uint8List bytes) {
  if (bytes.length < 12) return false;
  if (String.fromCharCodes(bytes, 4, 8) != "ftyp") return false;
  const brands = {"heic", "heix", "heim", "heis", "hevc", "hevx", "mif1"};
  return brands.contains(String.fromCharCodes(bytes, 8, 12));
}

/// A top-down 32-bit BMP (BITMAPV4HEADER with bit masks) of [width] x
/// [height] RGBA pixels read from [pixels], [stride] bytes per row.
Uint8List bmpFromRgba(Uint8List pixels, int width, int height, int stride) {
  const fileHeader = 14;
  const infoHeader = 108;
  const offset = fileHeader + infoHeader;
  final rowBytes = width * 4;
  final out = Uint8List(offset + rowBytes * height);
  final data = ByteData.sublistView(out);
  data.setUint8(0, 0x42); // "BM"
  data.setUint8(1, 0x4D);
  data.setUint32(2, out.length, Endian.little);
  data.setUint32(10, offset, Endian.little);
  data.setUint32(14, infoHeader, Endian.little);
  data.setInt32(18, width, Endian.little);
  data.setInt32(22, -height, Endian.little); // negative: rows top-down
  data.setUint16(26, 1, Endian.little); // planes
  data.setUint16(28, 32, Endian.little); // bits per pixel
  data.setUint32(30, 3, Endian.little); // BI_BITFIELDS
  data.setUint32(34, rowBytes * height, Endian.little);
  // Masks for R, G, B, A bytes in memory order.
  data.setUint32(54, 0x000000FF, Endian.little);
  data.setUint32(58, 0x0000FF00, Endian.little);
  data.setUint32(62, 0x00FF0000, Endian.little);
  data.setUint32(66, 0xFF000000, Endian.little);
  data.setUint32(70, 0x73524742, Endian.little); // LCS_sRGB
  for (var y = 0; y < height; y++) {
    out.setRange(
        offset + y * rowBytes, offset + (y + 1) * rowBytes, pixels, y * stride);
  }
  return out;
}

/// A 16x8 HEIC picture, decoded once at startup to see whether this system
/// really can (libheif may lack its HEVC plugin, Windows the HEVC extension).
final Uint8List heifProbeSample = base64Decode(
    "AAAAHGZ0eXBoZWljAAAAAG1pZjFoZWljbWlhZgAAAXxtZXRhAAAAAAAAACFoZGxy"
    "AAAAAAAAAABwaWN0AAAAAAAAAAAAAAAAAAAAAA5waXRtAAAAAAABAAAAImlsb2MA"
    "AAAAREAAAQABAAAAAAGgAAEAAAAAAAAAOwAAACNpaW5mAAAAAAABAAAAFWluZmUC"
    "AAAAAAEAAGh2YzEAAAAA/GlwcnAAAADcaXBjbwAAAHVodmNDAQNwAAAAAAAAAAAA"
    "HvAA/P34+AAADwNgAAEAGEABDAH//wNwAAADAJAAAAMAAAMAHroCQGEAAQApQgEB"
    "A3AAAAMAkAAAAwAAAwAeoCCBBZbqrprm4CGgwIAAAAyAAAADAIRiAAEABkQBwXPB"
    "iQAAABNjb2xybmNseAABAA0ABoAAAAAUaXNwZQAAAAAAAABAAAAAQAAAAChjbGFw"
    "AAAAEAAAAAEAAAAIAAAAAf///9AAAAAC////yAAAAAIAAAAQcGl4aQAAAAADCAgI"
    "AAAAGGlwbWEAAAAAAAAAAQABBYECAwWEAAAAQ21kYXQAAAA3KAGvGSFq4kDvXNWQ"
    "batafx23AG8O0s+TWgWuLf20wNCZEasv3EwLl0Zjm6NAs5HQ5bqyEjJRwA==");
