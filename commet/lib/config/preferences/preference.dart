import 'dart:async';

import 'package:commet/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Preference<T> {
  static SharedPreferences? preferences;

  final String key;
  final T defaultValue;
  late T? Function() _getter;
  late T Function()? _defaultGetter;
  late Future<void> Function(T value) _setter;

  Stream<T> get onChanged => _controller.stream;

  StreamController<T> _controller = StreamController.broadcast();

  Preference(
    this.key, {
    required this.defaultValue,
    required T? Function() getter,
    required Future<void> Function(T value) setter,
    T Function()? defaultGetter,
  }) {
    _getter = getter;
    _setter = setter;
    _defaultGetter = defaultGetter;
  }

  Future<void> set(T value) async {
    await _setter(value);
    Preferences.onSettingChangedController.add(null);
    _controller.add(value);
  }

  T get value => _getter() ?? _defaultGetter?.call() ?? defaultValue;

  /// Vommet: what a fresh install has (the default getter, if any, else
  /// [defaultValue]).
  T get defaultForNewUser => _defaultGetter?.call() ?? defaultValue;

  /// Vommet: whether a value is stored, as opposed to falling back to the
  /// default.
  bool get hasStoredValue => Preference.preferences?.containsKey(key) ?? false;

  /// Vommet: back to a fresh install's value by removing the stored one, so a
  /// platform-dependent default applies again too.
  Future<void> reset() async {
    await Preference.preferences?.remove(key);
    Preferences.onSettingChangedController.add(null);
    _controller.add(value);
  }

  @override
  bool operator ==(Object other) {
    throw Exception(
        "Do not check for equality on a preference, check the preferences value");
  }

  @override
  String toString() {
    throw Exception(
        "Do not convert a preference to string, use the preferences value");
  }
}
