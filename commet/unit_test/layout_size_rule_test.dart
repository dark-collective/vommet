import 'package:commet/config/layout_size_rule.dart';
import 'package:test/test.dart';

void main() {
  test("phone in portrait is mobile", () {
    expect(useMobileLayoutForSize(412, 915, 1), true);
  });

  test("phone in landscape is mobile", () {
    expect(useMobileLayoutForSize(915, 412, 1), true);
  });

  test("tablet is desktop in both orientations", () {
    expect(useMobileLayoutForSize(800, 1280, 1), false);
    expect(useMobileLayoutForSize(1280, 800, 1), false);
  });

  test("app scale still applies", () {
    expect(useMobileLayoutForSize(800, 1280, 0.5), true);
    expect(useMobileLayoutForSize(500, 900, 1.5), false);
  });
}
