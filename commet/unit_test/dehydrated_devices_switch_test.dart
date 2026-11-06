import 'package:commet/client/matrix/dehydrated_devices.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Vommet issue 965: the per-account switch for the stand-in session.
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      "vommet_dehydrated_devices_off": ["@off:example.org"],
    });
    Preference.preferences = await SharedPreferences.getInstance();
  });

  test('on by default, off per account', () {
    expect(DehydratedDevices.shouldEnable("@on:example.org"), isTrue);
    expect(DehydratedDevices.shouldEnable("@off:example.org"), isFalse);
  });

  test('nothing is created before the account is known', () {
    expect(DehydratedDevices.shouldEnable(null), isFalse);
  });
}
