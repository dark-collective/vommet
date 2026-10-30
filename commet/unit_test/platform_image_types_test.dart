import 'package:commet/utils/attachment_mime.dart';
import 'package:commet/utils/platform_image_types.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 778: HEIC/AVIF pictures shown in full where the platform
// decoder can read them.
void main() {
  tearDown(() => PlatformImageTypes.setForTesting(const {}));

  test("Android API levels map to the platform's decodable types", () {
    expect(PlatformImageTypes.forAndroidSdk(27), isEmpty);
    expect(PlatformImageTypes.forAndroidSdk(28), {"image/heic", "image/heif"});
    expect(PlatformImageTypes.forAndroidSdk(30), {"image/heic", "image/heif"});
    expect(PlatformImageTypes.forAndroidSdk(31),
        {"image/heic", "image/heif", "image/avif"});
  });

  test("without a platform decoder HEIC stays thumbnail-only", () {
    expect(AttachmentMime.isFullPicture("image/heic"), isFalse);
    expect(AttachmentMime.isFullPicture("image/jpeg"), isTrue);
    expect(
        AttachmentMime.showsThumbnailOnly(
            mimetype: "image/heic",
            hasThumbnail: true,
            thumbnailMimetype: "image/jpeg"),
        isTrue);
  });

  test("with a platform decoder HEIC is a full picture, thumbnail or not", () {
    PlatformImageTypes.setForTesting(PlatformImageTypes.forAndroidSdk(28));
    expect(AttachmentMime.isFullPicture("image/heic"), isTrue);
    expect(AttachmentMime.isFullPicture("image/heif"), isTrue);
    expect(AttachmentMime.isFullPicture("image/avif"), isFalse);
    expect(
        AttachmentMime.showsThumbnailOnly(
            mimetype: "image/heic",
            hasThumbnail: true,
            thumbnailMimetype: "image/jpeg"),
        isFalse);
    // A HEIC sent as m.file with a generic mimetype is found by its name.
    expect(
        AttachmentMime.isFullPicture(AttachmentMime.effective(
            mimetype: "application/octet-stream", name: "IMG_0001.HEIC")),
        isTrue);
  });
}
