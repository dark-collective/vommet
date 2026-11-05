import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/search/settings_search_entries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
      'Notification diagnostics are discoverable from existing settings search',
      () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    final entries = settingsSearchEntries()
        .where((e) => e.key == 'notification.troubleshooter');
    expect(entries, hasLength(1));
    expect(entries.single.title, 'Notification troubleshooter');
  });
}
