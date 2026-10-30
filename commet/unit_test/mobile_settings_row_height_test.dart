import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 861: mobile Settings menu rows must be at least 48 dp on the
// device. The App Scale multiplies logical pixels into device dp.
void main() {
  double deviceDp(double scale) => settingsRowHeightForScale(scale) * scale;

  test('rows are 48 dp at App Scale 1.0', () {
    expect(settingsRowHeightForScale(1.0), 48);
    expect(deviceDp(1.0), greaterThanOrEqualTo(48));
  });

  test('rows stay at least 48 dp at App Scale 0.8', () {
    // The reporter's 40-px rows measured 32 dp, i.e. scale 0.8.
    expect(settingsRowHeightForScale(0.8), closeTo(60, 1e-9));
    expect(deviceDp(0.8), greaterThanOrEqualTo(48 - 1e-9));
  });

  test('every slider scale gives at least 48 dp', () {
    for (var scale = 0.2; scale <= 2.0; scale += 0.05) {
      expect(deviceDp(scale), greaterThanOrEqualTo(48 - 1e-9),
          reason: 'scale $scale');
    }
  });

  test('a bad scale falls back to 48', () {
    expect(settingsRowHeightForScale(0), 48);
  });
}
