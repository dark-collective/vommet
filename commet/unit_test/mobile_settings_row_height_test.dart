import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rows are 56 logical px at the default app scale', () {
    expect(mobileSettingsRowHeight(1.0), 56);
  });

  test('rows stay at least 56 dp on the device at a reduced app scale', () {
    for (final scale in [0.5, 0.8, 0.9]) {
      expect(mobileSettingsRowHeight(scale) * scale, closeTo(56, 0.001));
    }
  });

  test('a larger app scale keeps the default row height', () {
    expect(mobileSettingsRowHeight(1.5), 56);
  });

  test('an invalid app scale falls back to the default row height', () {
    expect(mobileSettingsRowHeight(0), 56);
  });
}
