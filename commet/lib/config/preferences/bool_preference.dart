import 'package:commet/config/preferences/preference.dart';

class BoolPreference extends Preference<bool> {
  /// Vommet: keys that default to on whatever their [defaultValue] says,
  /// filled at startup by ExperimentRegistry.applyDefaults (experiments are
  /// opt-out). A stored value, such as an experiment switched off, still
  /// wins.
  static final Set<String> defaultOnKeys = {};

  /// Vommet: keys that are always on, whatever is stored: experiments that
  /// graduated into ordinary features (ExperimentRegistry.graduatedKeys),
  /// filled at startup next to [defaultOnKeys]. A stored "off" from when they
  /// were experiments is ignored, but kept, so a graduation can be undone.
  static final Set<String> alwaysOnKeys = {};

  BoolPreference(super.key,
      {required super.defaultValue, bool Function()? defaultGetter})
      : super(
          defaultGetter: () =>
              defaultOnKeys.contains(key) ||
              (defaultGetter?.call() ?? defaultValue),
          getter: () => alwaysOnKeys.contains(key)
              ? true
              : Preference.preferences?.getBool(key),
          setter: (v) async {
            await Preference.preferences?.setBool(key, v);
          },
        );
}

class NullableBoolPreference extends Preference<bool?> {
  NullableBoolPreference(super.key, {required super.defaultValue})
      : super(
          getter: () => Preference.preferences?.getBool(key),
          setter: (v) async {
            if (v == null) {
              await Preference.preferences?.remove(key);
            } else {
              await Preference.preferences?.setBool(key, v);
            }
          },
        );
}
