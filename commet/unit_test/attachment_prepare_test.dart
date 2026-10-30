// Vommet issue 838: removing hidden info / sending smaller after Send.
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/utils/attachment_prepare.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _jpegWithGps(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p
      ..r = p.x * 255 ~/ w
      ..g = p.y * 255 ~/ h
      ..b = 90;
  }
  image.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii("N");
  image.exif.gpsIfd['GPSLongitudeRef'] = img.IfdValueAscii("W");
  image.exif.imageIfd.make = "Made-up Camera Co";
  return img.encodeJpg(image);
}

PendingFileAttachment _file(Uint8List data, String name, String mime) =>
    PendingFileAttachment(
        name: name, data: data, size: data.lengthInBytes, mimeType: mime);

void main() {
  test("nothing asked, nothing changed", () async {
    final file = _file(_jpegWithGps(64, 48), "a.jpg", "image/jpeg");
    expect(AttachmentPrepare.wanted(file), isFalse);
    expect(identical(await AttachmentPrepare.prepare(file), file), isTrue);
  });

  test("GIFs and non-pictures keep their hidden info", () {
    expect(AttachmentPrepare.canRemoveHiddenInfo("image/gif"), isFalse);
    expect(AttachmentPrepare.canRemoveHiddenInfo("video/mp4"), isFalse);
    expect(AttachmentPrepare.canRemoveHiddenInfo("image/jpeg"), isTrue);
    final gif = _file(Uint8List.fromList([1, 2, 3]), "a.gif", "image/gif")
      ..removeHiddenInfo = true;
    expect(AttachmentPrepare.wanted(gif), isFalse);
  });

  test("remove hidden info drops the location and camera, keeps spoiler",
      () async {
    final data = _jpegWithGps(64, 48);
    expect(img.decodeJpgExif(data)!.gpsIfd.isEmpty, isFalse);

    final file = _file(data, "holiday.jpg", "image/jpeg")
      ..removeHiddenInfo = true
      ..spoiler = true
      ..spoilerReason = "Made-up reason";
    final prepared = await AttachmentPrepare.prepare(file);

    expect(identical(prepared, file), isFalse);
    expect(prepared.name, "holiday.jpg");
    expect(prepared.mimeType, "image/jpeg");
    final exif = img.decodeJpgExif(prepared.data!);
    expect(exif == null || exif.gpsIfd.isEmpty, isTrue);
    expect(exif?.imageIfd.make, isNull);
    expect(prepared.spoiler, isTrue);
    expect(prepared.spoilerReason, "Made-up reason");
  });

  test("send smaller shrinks a big picture", () async {
    final file = _file(_jpegWithGps(1600, 1200), "big.jpg", "image/jpeg")
      ..shrinkLongestEdge = 800;
    final prepared = await AttachmentPrepare.prepare(file);
    final decoded = img.decodeImage(prepared.data!)!;
    expect(decoded.width, lessThanOrEqualTo(800));
    expect(prepared.dimensions?.width, decoded.width.toDouble());
  });

  test("an unreadable picture is sent as it is", () async {
    final file =
        _file(Uint8List.fromList([0, 1, 2, 3, 4]), "bad.jpg", "image/jpeg")
          ..removeHiddenInfo = true;
    expect(identical(await AttachmentPrepare.prepare(file), file), isTrue);
  });
}
