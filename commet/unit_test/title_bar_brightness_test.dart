import 'dart:async';

import 'package:commet/config/title_bar_brightness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late StreamController<ThemeData> themes;
  late StreamController<String> setting;

  final dark = ThemeData(brightness: Brightness.dark);
  final light = ThemeData(brightness: Brightness.light);

  void follow(Brightness initial, String value) => TitleBarBrightness.follow(
        initialTheme: initial,
        themes: themes.stream,
        setting: value,
        settingChanges: setting.stream,
      );

  // Lets the stream listeners and the channel call run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  List<Object?> sent() => calls.map((c) => c.arguments).toList();

  setUp(() async {
    await TitleBarBrightness.reset();
    calls = [];
    themes = StreamController.broadcast();
    setting = StreamController.broadcast();
    TitleBarBrightness.isSupported = () => true;
    messenger.setMockMethodCallHandler(TitleBarBrightness.channel,
        (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() async {
    await TitleBarBrightness.reset();
    messenger.setMockMethodCallHandler(TitleBarBrightness.channel, null);
  });

  test("a dark theme asks for the dark title bar at startup", () async {
    follow(Brightness.dark, TitleBarBrightness.followTheme);
    await settle();
    expect(calls.map((c) => [c.method, c.arguments]), [
      ["setDarkTheme", true]
    ]);
  });

  test("a light theme asks for the light title bar at startup", () async {
    follow(Brightness.light, TitleBarBrightness.followTheme);
    await settle();
    expect(sent(), [false]);
  });

  test("theme switches follow, same-brightness switches send nothing",
      () async {
    follow(Brightness.dark, TitleBarBrightness.followTheme);
    themes.add(light);
    await settle();
    themes.add(ThemeData(
        brightness: Brightness.light, primaryColor: Colors.deepOrange));
    await settle();
    themes.add(dark);
    await settle();
    expect(sent(), [true, false, true]);
  });

  test("a forced dark bar wins over a light theme at startup", () async {
    follow(Brightness.light, TitleBarBrightness.dark);
    await settle();
    expect(sent(), [true]);
  });

  test("while forced, theme switches send nothing", () async {
    follow(Brightness.dark, TitleBarBrightness.light);
    themes.add(dark);
    await settle();
    themes.add(light);
    await settle();
    themes.add(dark);
    await settle();
    expect(sent(), [false]);
  });

  test("changing the setting applies at once, and Match theme goes back",
      () async {
    follow(Brightness.dark, TitleBarBrightness.followTheme);
    setting.add(TitleBarBrightness.light);
    await settle();
    // The theme changed while forced: Match theme sends the current one.
    themes.add(light);
    await settle();
    themes.add(dark);
    await settle();
    setting.add(TitleBarBrightness.followTheme);
    await settle();
    expect(sent(), [true, false, true]);
  });

  test("setting values map to a forced brightness", () {
    expect(TitleBarBrightness.overrideFor("theme"), isNull);
    expect(TitleBarBrightness.overrideFor("light"), Brightness.light);
    expect(TitleBarBrightness.overrideFor("dark"), Brightness.dark);
    // An unknown value (say, from a newer build) follows the theme.
    expect(TitleBarBrightness.overrideFor("sepia"), isNull);
  });

  test("other platforms send nothing", () async {
    TitleBarBrightness.isSupported = () => false;
    follow(Brightness.dark, TitleBarBrightness.dark);
    themes.add(light);
    await settle();
    expect(calls, isEmpty);
  });

  test("a runner without the channel is not an error", () async {
    messenger.setMockMethodCallHandler(TitleBarBrightness.channel, null);
    follow(Brightness.dark, TitleBarBrightness.followTheme);
    await settle();
  });
}
