import 'package:commet/config/experiment_registry.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet: experiments are on unless the user switched them off; a few stay
// opt-in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Experiment experiment(BoolPreference p, {bool optIn = false}) => Experiment(
      preference: p,
      title: "t",
      description: "d",
      category: ExperimentCategory.messages,
      optIn: optIn);

  Future<void> load(Map<String, Object> stored) async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(stored);
    await preferences.init();
  }

  test("loading the preferences makes the registered experiments opt-out",
      () async {
    await load({});
    expect(BoolPreference.defaultOnKeys,
        contains(preferences.experimentEnableE2eeElementCall.key));
    expect(preferences.experimentEnableE2eeElementCall.value, isTrue);
  });

  test("an untouched experiment is on, one switched off stays off", () async {
    final p = BoolPreference("test_experiment", defaultValue: false);
    // Loading the preferences re-applies the registry's keys, so add the
    // test's own experiment after each load.
    void register() => BoolPreference.defaultOnKeys
        .addAll(ExperimentRegistry.defaultOnKeysOf([experiment(p)]));

    await load({});
    register();
    expect(p.value, isTrue);
    expect(Preference.preferences!.containsKey(p.key), isFalse);

    await load({"test_experiment": false});
    register();
    expect(p.value, isFalse);
  });

  test("opt-in experiments stay off", () {
    final listed = BoolPreference("vommet_experiment_space_nicknames",
        defaultValue: false);
    final flagged = BoolPreference("test_opt_in", defaultValue: false);
    expect(
        ExperimentRegistry.defaultOnKeysOf(
            [experiment(listed), experiment(flagged, optIn: true)]),
        isEmpty);
  });

  test("sliding sync is on by default, and stays off once switched off",
      () async {
    final p = BoolPreference("experiment_sliding_sync", defaultValue: false);
    // Loading the preferences re-applies the registry's keys, so add this
    // experiment after each load (as the registry entry would).
    void register() => BoolPreference.defaultOnKeys
        .addAll(ExperimentRegistry.defaultOnKeysOf([experiment(p)]));

    await load({});
    register();
    expect(p.value, isTrue);

    await load({"experiment_sliding_sync": false});
    register();
    expect(p.value, isFalse);
  });

  test("other settings keep their own defaults", () async {
    await load({});
    expect(preferences.minimizeOnClose.value,
        preferences.minimizeOnClose.defaultValue);
  });
}
