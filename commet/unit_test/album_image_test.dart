import 'dart:typed_data';

import 'package:commet/client/matrix/components/photo_album_room/matrix_upload_photos_task.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

img.Image _solid(int r, int g, int b, int a) {
  final image = img.Image(width: 4, height: 4, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(r, g, b, a));
  return image;
}

void main() {
  // Vommet issue 22: album uploads turned animated GIF/WebP into one JPEG frame and
  // lost transparency.
  test('animated GIF is sent unchanged', () {
    final anim = _solid(255, 0, 0, 255);
    anim.addFrame(_solid(0, 0, 255, 255));
    final bytes = img.encodeGif(anim);
    final (out, name) = prepareAlbumImage((bytes, "dance.gif"));
    expect(out, same(bytes));
    expect(name, "dance.gif");
  });

  test('transparent picture becomes PNG and keeps its alpha', () {
    final bytes = img.encodePng(_solid(0, 255, 0, 0));
    final (out, name) = prepareAlbumImage((bytes, "sticker.png"));
    expect(name, "sticker.png");
    final decoded = img.decodePng(out)!;
    expect(decoded.getPixel(0, 0).a, 0);
  });

  test('opaque picture is re-encoded as JPEG', () {
    final bytes = img.encodePng(_solid(10, 20, 30, 255));
    final (out, name) = prepareAlbumImage((bytes, "photo.png"));
    expect(name, "photo.jpeg");
    expect(img.findDecoderForData(out), isA<img.JpegDecoder>());
  });

  test('animated PNG is sent unchanged', () {
    final anim = _solid(255, 0, 0, 255);
    anim.addFrame(_solid(0, 0, 255, 255));
    final bytes = img.encodePng(anim);
    final (out, name) = prepareAlbumImage((bytes, "blink.png"));
    expect(out, same(bytes));
    expect(name, "blink.png");
  });

  test('single-frame GIF with a transparent colour becomes PNG', () {
    // The image package's GIF encoder writes no transparency, so this is a
    // hand-made 1x1 GIF whose only pixel uses the transparent colour index.
    final bytes = Uint8List.fromList([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, //
      0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0x21, 0xf9, 0x04, 0x01, 0x00,
      0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
      0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b,
    ]);
    final (out, name) = prepareAlbumImage((bytes, "dot.gif"));
    expect(name, "dot.png");
    expect(img.decodePng(out)!.getPixel(0, 0).a, 0);
  });

  test('undecodable data is not sent with its metadata', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(() => prepareAlbumImage((bytes, "x.heic")), throwsUnsupportedError);
  });
}
