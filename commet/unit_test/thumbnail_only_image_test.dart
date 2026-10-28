import 'package:commet/utils/attachment_mime.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool thumbOnly(String mimetype,
          {bool hasThumbnail = true, String thumbnailMimetype = "image/png"}) =>
      AttachmentMime.showsThumbnailOnly(
          mimetype: mimetype,
          hasThumbnail: hasThumbnail,
          thumbnailMimetype: thumbnailMimetype);

  test("AVIF and HEIC with a JPEG/PNG thumbnail show through it", () {
    expect(thumbOnly("image/avif"), isTrue);
    expect(thumbOnly("image/avif", thumbnailMimetype: "image/jpeg"), isTrue);
    expect(thumbOnly("image/heic", thumbnailMimetype: "image/jpg"), isTrue);
    expect(thumbOnly("image/heif"), isTrue);
  });

  test("an unknown thumbnail mimetype is tried (sniffed on load)", () {
    expect(thumbOnly("image/avif", thumbnailMimetype: ""), isTrue);
  });

  test("without a decodable thumbnail they stay files", () {
    expect(thumbOnly("image/avif", hasThumbnail: false), isFalse);
    expect(thumbOnly("image/avif", thumbnailMimetype: "image/avif"), isFalse);
    expect(thumbOnly("image/heic", thumbnailMimetype: "image/heic"), isFalse);
  });

  test("decodable pictures and other files are not thumbnail-only", () {
    expect(thumbOnly("image/png"), isFalse);
    expect(thumbOnly("image/jpeg"), isFalse);
    expect(thumbOnly("application/pdf"), isFalse);
    expect(thumbOnly("video/mp4"), isFalse);
    expect(Mime.imageTypes.contains("image/avif"), isFalse);
  });

  test("AVIF/HEIC sent as a generic file are recognised by extension", () {
    expect(AttachmentMime.effective(mimetype: "", name: "photo.avif"),
        "image/avif");
    expect(
        AttachmentMime.effective(
            mimetype: "application/octet-stream", name: "IMG_0001.HEIC"),
        "image/heic");
  });

  test("an AVIF file tile gets the picture icon", () {
    expect(Mime.toIcon("image/avif"), Icons.image);
    expect(Mime.toIcon("image/heic"), Icons.image);
  });
}
