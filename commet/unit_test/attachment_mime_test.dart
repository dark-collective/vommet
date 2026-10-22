import 'package:commet/utils/attachment_mime.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String eff(String mimetype, [String? name]) =>
      AttachmentMime.effective(mimetype: mimetype, name: name);

  test("declared image mimetypes show as pictures", () {
    expect(
        Mime.imageTypes.contains(eff("image/jpeg", "file_63458.jpg")), isTrue);
    expect(eff("image/PNG"), "image/png");
    expect(eff("image/jpeg; charset=binary"), "image/jpeg");
  });

  test("non-standard image mimetypes are normalised", () {
    expect(eff("image/jpg"), "image/jpeg");
    expect(eff("image/pjpeg"), "image/jpeg");
    expect(eff("image/x-ms-bmp"), "image/bmp");
  });

  test("missing or generic mimetypes fall back to the extension", () {
    expect(eff("", "file_63458.jpg"), "image/jpeg");
    expect(eff("application/octet-stream", "Photo.JPEG"), "image/jpeg");
    expect(eff("", "anim.gif"), "image/gif");
    expect(eff("binary/octet-stream", " shot.webp "), "image/webp");
  });

  test("other files are unchanged", () {
    expect(eff("application/pdf", "doc.jpg"), "application/pdf");
    expect(eff("application/zip", "photos.zip"), "application/zip");
    expect(eff("", "notes.txt"), "");
    expect(eff("application/octet-stream", "archive.tar"),
        "application/octet-stream");
    expect(eff("", "no extension"), "");
    expect(eff("", "trailing."), "");
    expect(eff("", "weird.jp g"), "");
    expect(eff(""), "");
    expect(eff("video/mp4", "clip.mp4"), "video/mp4");
    expect(eff("image/svg+xml", "logo.svg"), "image/svg+xml");
    expect(Mime.imageTypes.contains(eff("image/svg+xml")), isFalse);
  });
}
