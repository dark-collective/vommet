import 'package:commet/main.dart';
import 'package:commet/utils/text_scale_changer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A platform curve with different ratios for body and heading text.
class _PlatformCurve extends TextScaler {
  const _PlatformCurve();

  @override
  double scale(double fontSize) => fontSize * (fontSize <= 20 ? 2 : 1.5);

  @override
  double get textScaleFactor => 2;
}

Widget _sample(TextScaler platform,
        {double app = 1.1, ValueNotifier<double>? expectedApp}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(textScaler: platform),
        child: Column(children: [
          TextScaleChanger(
            child: Column(children: [
              for (final size in [14.0, 28.0])
                Text('Readable',
                    key: ValueKey('actual-$size'),
                    style: TextStyle(fontSize: size)),
            ]),
          ),
          ValueListenableBuilder<double>(
            valueListenable: expectedApp ?? AlwaysStoppedAnimation(app),
            builder: (context, multiplier, _) => Column(children: [
              for (final size in [14.0, 28.0])
                Text('Readable',
                    key: ValueKey('expected-$size'),
                    textScaler: TextScaler.noScaling,
                    style:
                        TextStyle(fontSize: platform.scale(size) * multiplier)),
            ]),
          ),
        ]),
      ),
    );

void _expectMatchingText(WidgetTester tester) {
  for (final size in [14.0, 28.0]) {
    final actual = tester.getSize(find.byKey(ValueKey('actual-$size')));
    final expected = tester.getSize(find.byKey(ValueKey('expected-$size')));
    expect(actual.width, closeTo(expected.width, 0.01));
    expect(actual.height, closeTo(expected.height, 0.01));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() async {
    // unit_test is the repository's test directory.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  for (final viewport in [const Size(390, 844), const Size(1440, 900)]) {
    for (final platform in [TextScaler.linear(2), const _PlatformCurve()]) {
      testWidgets('OS and app scale compose at $viewport with $platform',
          (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await preferences.textScale.set(1.1);
        await tester.pumpWidget(_sample(platform));
        _expectMatchingText(tester);
      });
    }
  }

  testWidgets('live app changes and default restore preserve the OS curve',
      (tester) async {
    const platform = _PlatformCurve();
    final expectedApp = ValueNotifier(1.0);
    addTearDown(expectedApp.dispose);
    await tester.pumpWidget(_sample(platform, expectedApp: expectedApp));
    _expectMatchingText(tester);
    for (final multiplier in [1.1, 0.8, 1.0]) {
      await preferences.textScale.set(multiplier);
      expectedApp.value = multiplier;
      await tester.pump();
      _expectMatchingText(tester);
    }
  });

  testWidgets('platform changes are observed while app scaling is active',
      (tester) async {
    await preferences.textScale.set(1.1);
    await tester.pumpWidget(_sample(TextScaler.linear(1)));
    _expectMatchingText(tester);
    await tester.pumpWidget(_sample(const _PlatformCurve()));
    _expectMatchingText(tester);
  });

  testWidgets('unmount cancels the preference listener', (tester) async {
    await tester.pumpWidget(_sample(const _PlatformCurve(), app: 1));
    await tester.pumpWidget(const SizedBox());
    await preferences.textScale.set(1.1);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
