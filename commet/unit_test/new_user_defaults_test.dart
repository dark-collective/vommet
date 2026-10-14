import 'package:commet/config/new_user_defaults.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet: "Back to new-user defaults" saves, resets to each preference's own
// default (not "everything off") and restores exactly what was stored.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      // The opposite of what a new user gets. Its default differs between
      // main (off) and the fork's settings (on), and new-user defaults mean
      // that default, not "off".
      "experiment_enabled_e2ee_element_call":
          !preferences.experimentEnableE2eeElementCall.defaultValue,
      "app_theme": "light",
      "notifications_volume": 50.0,
      "allowed_remote_video_hosts": ["example.org"],
    });
    await preferences.init();
  });

  test("experiments go back to their own defaults and restore", () async {
    final e2ee = preferences.experimentEnableE2eeElementCall;
    expect(NewUserDefaults.changedExperiments.map((e) => e.preference.key),
        [e2ee.key]);

    final changed =
        await NewUserDefaults.reset(experiments: true, appSettings: false);
    expect(changed.map((e) => e.preference.key), [e2ee.key]);
    expect(e2ee.value, e2ee.defaultForNewUser);
    expect(e2ee.hasStoredValue, isFalse);
    expect(preferences.theme.value, "light", reason: "app settings untouched");
    expect(NewUserDefaults.hasSavedSetup, isTrue);
    expect(NewUserDefaults.savedExperimentCount, 1);
    expect(NewUserDefaults.changedExperiments, isEmpty);

    await NewUserDefaults.restore();
    expect(e2ee.value, !e2ee.defaultForNewUser);
    expect(NewUserDefaults.hasSavedSetup, isFalse);
  });

  test("app settings reset and restore, unstored ones stay unstored", () async {
    final effects = preferences.messageEffectsEnabled;
    expect(effects.hasStoredValue, isFalse);

    await NewUserDefaults.reset(experiments: false, appSettings: true);
    expect(preferences.theme.value, preferences.theme.defaultForNewUser);
    expect(preferences.notificationsVolume.hasStoredValue, isFalse);
    expect(preferences.allowedRemoteVideoHosts.value, isEmpty);
    expect(preferences.experimentEnableE2eeElementCall.hasStoredValue, isTrue,
        reason: "experiments untouched");

    await NewUserDefaults.restore();
    expect(preferences.theme.value, "light");
    expect(preferences.notificationsVolume.value, 50.0);
    expect(preferences.allowedRemoteVideoHosts.value, ["example.org"]);
    expect(effects.hasStoredValue, isFalse);
  });
}
