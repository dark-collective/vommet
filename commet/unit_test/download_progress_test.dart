import 'package:commet/cache/file_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("known size gives a fraction", () {
    final p = DownloadProgress(512, 1024);
    expect(p.hasTotal, isTrue);
    expect(p.fraction, 0.5);
  });

  test("unknown size (-1) gives no fraction", () {
    final p = DownloadProgress(287590, -1);
    expect(p.hasTotal, isFalse);
    expect(p.fraction, isNull);
  });

  test("fraction never passes 1", () {
    expect(DownloadProgress(2000, 1000).fraction, 1.0);
  });
}
