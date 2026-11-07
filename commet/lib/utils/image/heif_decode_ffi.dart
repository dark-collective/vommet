import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/utils/image/heif_decode.dart';
import 'package:ffi/ffi.dart';

/// Vommet issue 813: see [decodeHeifToBmp] in heif_decode.dart. Linux uses
/// the system's libheif (opened at runtime, not linked or bundled), Windows
/// the Windows Imaging Component, which reads HEIC once Microsoft's "HEIF
/// Image Extensions" and "HEVC Video Extensions" are installed.
Uint8List? decodeHeifToBmp(Uint8List bytes) {
  try {
    if (Platform.isLinux) return _LibHeif.open()?.decode(bytes);
    if (Platform.isWindows) return _decodeWithWic(bytes);
  } catch (_) {
    // No library, a missing symbol or a failed decode: not decodable here.
  }
  return null;
}

// ---------------------------------------------------------------- libheif

final class _HeifError extends Struct {
  @Int32()
  external int code;
  @Int32()
  external int subcode;
  external Pointer<Utf8> message;
}

typedef _HeifInitC = _HeifError Function(Pointer<Void>);
typedef _HeifInit = _HeifError Function(Pointer<Void>);
typedef _AllocC = Pointer<Void> Function();
typedef _ReleaseC = Void Function(Pointer<Void>);
typedef _Release = void Function(Pointer<Void>);
typedef _ReadC = _HeifError Function(
    Pointer<Void>, Pointer<Uint8>, Size, Pointer<Void>);
typedef _Read = _HeifError Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>);
typedef _PrimaryC = _HeifError Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _DecodeC = _HeifError Function(
    Pointer<Void>, Pointer<Pointer<Void>>, Int32, Int32, Pointer<Void>);
typedef _Decode = _HeifError Function(
    Pointer<Void>, Pointer<Pointer<Void>>, int, int, Pointer<Void>);
typedef _PlaneC = Pointer<Uint8> Function(Pointer<Void>, Int32, Pointer<Int32>);
typedef _Plane = Pointer<Uint8> Function(Pointer<Void>, int, Pointer<Int32>);
typedef _SizeC = Int32 Function(Pointer<Void>, Int32);
typedef _Size = int Function(Pointer<Void>, int);

class _LibHeif {
  _LibHeif(DynamicLibrary lib)
      : _alloc = lib.lookupFunction<_AllocC, _AllocC>("heif_context_alloc"),
        _free = lib.lookupFunction<_ReleaseC, _Release>("heif_context_free"),
        _read = lib.lookupFunction<_ReadC, _Read>(
            "heif_context_read_from_memory_without_copy"),
        _primary = lib.lookupFunction<_PrimaryC, _PrimaryC>(
            "heif_context_get_primary_image_handle"),
        _releaseHandle = lib
            .lookupFunction<_ReleaseC, _Release>("heif_image_handle_release"),
        _decode = lib.lookupFunction<_DecodeC, _Decode>("heif_decode_image"),
        _releaseImage =
            lib.lookupFunction<_ReleaseC, _Release>("heif_image_release"),
        _plane = lib
            .lookupFunction<_PlaneC, _Plane>("heif_image_get_plane_readonly"),
        _width = lib.lookupFunction<_SizeC, _Size>("heif_image_get_width"),
        _height = lib.lookupFunction<_SizeC, _Size>("heif_image_get_height") {
    // libheif 1.13+ loads its decoder plugins in heif_init; older versions
    // have the decoders built in and no heif_init.
    if (lib.providesSymbol("heif_init")) {
      lib.lookupFunction<_HeifInitC, _HeifInit>("heif_init")(nullptr);
    }
  }

  static _LibHeif? _instance;

  static _LibHeif? open() {
    if (_instance != null) return _instance;
    for (final name in const ["libheif.so.1", "libheif.so"]) {
      try {
        return _instance = _LibHeif(DynamicLibrary.open(name));
      } catch (_) {}
    }
    return null;
  }

  static const _colorspaceRgb = 1;
  static const _chromaInterleavedRgba = 11;
  static const _channelInterleaved = 10;

  final _AllocC _alloc;
  final _Release _free;
  final _Read _read;
  final _PrimaryC _primary;
  final _Release _releaseHandle;
  final _Decode _decode;
  final _Release _releaseImage;
  final _Plane _plane;
  final _Size _width;
  final _Size _height;

  Uint8List? decode(Uint8List bytes) {
    final arena = Arena();
    final ctx = _alloc();
    var handle = nullptr.cast<Void>();
    var image = nullptr.cast<Void>();
    try {
      if (ctx == nullptr) return null;
      final data = arena<Uint8>(bytes.length);
      data.asTypedList(bytes.length).setAll(0, bytes);
      if (_read(ctx, data, bytes.length, nullptr).code != 0) return null;

      final handleOut = arena<Pointer<Void>>();
      if (_primary(ctx, handleOut).code != 0) return null;
      handle = handleOut.value;

      // Default options: libheif applies the picture's rotation/mirroring.
      final imageOut = arena<Pointer<Void>>();
      if (_decode(handle, imageOut, _colorspaceRgb, _chromaInterleavedRgba,
                  nullptr)
              .code !=
          0) {
        return null;
      }
      image = imageOut.value;

      final stride = arena<Int32>();
      final plane = _plane(image, _channelInterleaved, stride);
      final width = _width(image, _channelInterleaved);
      final height = _height(image, _channelInterleaved);
      if (plane == nullptr || width <= 0 || height <= 0) return null;
      return bmpFromRgba(plane.asTypedList(stride.value * height), width,
          height, stride.value);
    } finally {
      if (image != nullptr) _releaseImage(image);
      if (handle != nullptr) _releaseHandle(handle);
      if (ctx != nullptr) _free(ctx);
      arena.releaseAll();
    }
  }
}

// -------------------------------------------------------------------- WIC

final class _Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

Pointer<_Guid> _guid(Arena arena, String text) {
  final hex = text.replaceAll("-", "");
  final guid = arena<_Guid>();
  guid.ref.data1 = int.parse(hex.substring(0, 8), radix: 16);
  guid.ref.data2 = int.parse(hex.substring(8, 12), radix: 16);
  guid.ref.data3 = int.parse(hex.substring(12, 16), radix: 16);
  for (var i = 0; i < 8; i++) {
    guid.ref.data4[i] =
        int.parse(hex.substring(16 + i * 2, 18 + i * 2), radix: 16);
  }
  return guid;
}

/// Entry [index] of a COM object's vtable.
Pointer<NativeFunction<T>> _method<T extends Function>(
        Pointer<Void> object, int index) =>
    object.cast<Pointer<Pointer<Void>>>().value[index].cast();

typedef _ComOutC = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ComOut = int Function(Pointer<Void>, Pointer<Pointer<Void>>);

const _clsidWicImagingFactory = "cacaf262-9370-4615-a13b-9f5539da4c0a";
const _iidWicImagingFactory = "ec5ec8a9-c395-4314-9c77-54d7a935ff70";
const _wicPixelFormat32bppRgba = "f5c7ad2d-6a8d-43dd-a7a8-a29935261ae9";

Uint8List? _decodeWithWic(Uint8List bytes) {
  final ole32 = DynamicLibrary.open("ole32.dll");
  final coInitializeEx = ole32.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)>("CoInitializeEx");
  final coUninitialize =
      ole32.lookupFunction<Void Function(), void Function()>("CoUninitialize");
  final coCreateInstance = ole32.lookupFunction<
      Int32 Function(Pointer<_Guid>, Pointer<Void>, Uint32, Pointer<_Guid>,
          Pointer<Pointer<Void>>),
      int Function(Pointer<_Guid>, Pointer<Void>, int, Pointer<_Guid>,
          Pointer<Pointer<Void>>)>("CoCreateInstance");

  // A worker isolate's thread: join the multithreaded apartment (S_OK or
  // S_FALSE both need a matching CoUninitialize).
  final initialized = coInitializeEx(nullptr, 0 /* MULTITHREADED */) >= 0;
  final arena = Arena();
  final objects = <Pointer<Void>>[];
  Pointer<Void>? create(int Function(Pointer<Pointer<Void>>) call) {
    final out = arena<Pointer<Void>>();
    if (call(out) < 0 || out.value == nullptr) return null;
    objects.add(out.value);
    return out.value;
  }

  try {
    final factory = create((out) => coCreateInstance(
        _guid(arena, _clsidWicImagingFactory),
        nullptr,
        1 /* CLSCTX_INPROC_SERVER */,
        _guid(arena, _iidWicImagingFactory),
        out));
    if (factory == null) return null;

    // IWICImagingFactory::CreateStream, IWICStream::InitializeFromMemory.
    final stream = create((out) =>
        _method<_ComOutC>(factory, 14).asFunction<_ComOut>()(factory, out));
    if (stream == null) return null;
    final data = arena<Uint8>(bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    if (_method<Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32)>(
                    stream, 16)
                .asFunction<int Function(Pointer<Void>, Pointer<Uint8>, int)>()(
            stream, data, bytes.length) <
        0) {
      return null;
    }

    // IWICImagingFactory::CreateDecoderFromStream, IWICBitmapDecoder::GetFrame.
    final decoder = create((out) =>
        _method<
                    Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<_Guid>,
                        Int32, Pointer<Pointer<Void>>)>(factory, 4)
                .asFunction<
                    int Function(Pointer<Void>, Pointer<Void>, Pointer<_Guid>,
                        int, Pointer<Pointer<Void>>)>()(factory, stream,
            nullptr, 0 /* WICDecodeMetadataCacheOnDemand */, out));
    if (decoder == null) return null;
    var source = create((out) =>
        _method<Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Void>>)>(
                    decoder, 13)
                .asFunction<
                    int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)>()(
            decoder, 0, out));
    if (source == null) return null;

    // Unlike libheif, WIC leaves the picture's orientation to the caller.
    final transform = _wicTransform(_wicOrientation(arena, source, create));
    if (transform != 0) {
      // IWICImagingFactory::CreateBitmapFlipRotator, ::Initialize.
      final rotator = create((out) =>
          _method<_ComOutC>(factory, 13).asFunction<_ComOut>()(factory, out));
      if (rotator != null &&
          _method<Int32 Function(Pointer<Void>, Pointer<Void>, Int32)>(
                          rotator, 8)
                      .asFunction<
                          int Function(Pointer<Void>, Pointer<Void>, int)>()(
                  rotator, source, transform) >=
              0) {
        source = rotator;
      }
    }

    // IWICImagingFactory::CreateFormatConverter, ::Initialize to RGBA.
    final converter = create((out) =>
        _method<_ComOutC>(factory, 10).asFunction<_ComOut>()(factory, out));
    if (converter == null) return null;
    if (_method<
                    Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<_Guid>,
                        Int32, Pointer<Void>, Double, Int32)>(converter, 8)
                .asFunction<
                    int Function(Pointer<Void>, Pointer<Void>, Pointer<_Guid>,
                        int, Pointer<Void>, double, int)>()(
            converter,
            source,
            _guid(arena, _wicPixelFormat32bppRgba),
            0 /* WICBitmapDitherTypeNone */,
            nullptr,
            0.0,
            0 /* WICBitmapPaletteTypeCustom */) <
        0) {
      return null;
    }

    // IWICBitmapSource::GetSize, ::CopyPixels.
    final width = arena<Uint32>();
    final height = arena<Uint32>();
    if (_method<
                Int32 Function(Pointer<Void>, Pointer<Uint32>,
                    Pointer<Uint32>)>(converter, 3)
            .asFunction<
                int Function(Pointer<Void>, Pointer<Uint32>,
                    Pointer<Uint32>)>()(converter, width, height) <
        0) {
      return null;
    }
    final w = width.value, h = height.value;
    if (w <= 0 || h <= 0) return null;
    final size = w * h * 4;
    final pixels = arena<Uint8>(size);
    if (_method<
                    Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Uint32,
                        Pointer<Uint8>)>(converter, 7)
                .asFunction<
                    int Function(Pointer<Void>, Pointer<Void>, int, int,
                        Pointer<Uint8>)>()(
            converter, nullptr, w * 4, size, pixels) <
        0) {
      return null;
    }
    return bmpFromRgba(pixels.asTypedList(size), w, h, w * 4);
  } finally {
    for (final object in objects.reversed) {
      _method<Uint32 Function(Pointer<Void>)>(object, 2)
          .asFunction<int Function(Pointer<Void>)>()(object);
    }
    arena.releaseAll();
    if (initialized) coUninitialize();
  }
}

/// The EXIF orientation (1-8) of a WIC frame, or 1 when it has none.
int _wicOrientation(Arena arena, Pointer<Void> frame,
    Pointer<Void>? Function(int Function(Pointer<Pointer<Void>>)) create) {
  // IWICBitmapFrameDecode::GetMetadataQueryReader.
  final reader = create(
      (out) => _method<_ComOutC>(frame, 8).asFunction<_ComOut>()(frame, out));
  if (reader == null) return 1;
  // IWICMetadataQueryReader::GetMetadataByName into a PROPVARIANT
  // (vt at offset 0, a VT_UI2 value at offset 8; 24 bytes on 64-bit).
  final value = arena<Uint8>(24);
  value.asTypedList(24).fillRange(0, 24, 0);
  final hr =
      _method<Int32 Function(Pointer<Void>, Pointer<Utf16>, Pointer<Uint8>)>(
                  reader, 5)
              .asFunction<
                  int Function(
                      Pointer<Void>, Pointer<Utf16>, Pointer<Uint8>)>()(reader,
          "System.Photo.Orientation".toNativeUtf16(allocator: arena), value);
  if (hr < 0) return 1;
  const vtUi2 = 18;
  if (value.cast<Uint16>().value != vtUi2) return 1;
  return (value + 8).cast<Uint16>().value;
}

/// The WICBitmapTransformOptions that show an EXIF [orientation] upright.
int _wicTransform(int orientation) {
  const rotate90 = 1, rotate180 = 2, rotate270 = 3, flipHorizontal = 8;
  const flipVertical = 16;
  return switch (orientation) {
    2 => flipHorizontal,
    3 => rotate180,
    4 => flipVertical,
    5 => rotate90 | flipHorizontal,
    6 => rotate90,
    7 => rotate270 | flipHorizontal,
    8 => rotate270,
    _ => 0,
  };
}
