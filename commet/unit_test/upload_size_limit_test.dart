import 'package:commet/utils/upload_size_limit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("UploadSizeLimit.exceeds", () {
    test("over the limit", () {
      expect(UploadSizeLimit.exceeds(101, 100), isTrue);
    });

    test("at or under the limit", () {
      expect(UploadSizeLimit.exceeds(100, 100), isFalse);
      expect(UploadSizeLimit.exceeds(1, 100), isFalse);
    });

    test("unknown size or limit lets the file through", () {
      expect(UploadSizeLimit.exceeds(null, 100), isFalse);
      expect(UploadSizeLimit.exceeds(101, null), isFalse);
      expect(UploadSizeLimit.exceeds(101, 0), isFalse);
    });
  });

  group("UploadSizeLimit.serverOf", () {
    test("takes the part after the first colon", () {
      expect(UploadSizeLimit.serverOf("@sam:example.org"), "example.org");
      expect(UploadSizeLimit.serverOf("@sam:example.org:8448"),
          "example.org:8448");
    });

    test("null without a server part", () {
      expect(UploadSizeLimit.serverOf(null), isNull);
      expect(UploadSizeLimit.serverOf("sam"), isNull);
      expect(UploadSizeLimit.serverOf("@sam:"), isNull);
    });
  });
}
