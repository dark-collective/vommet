import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/telemetry_tag_field.dart';
import 'package:commet/ui/pages/setup/menus/telemetry_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test('"No" clears a typed and a saved tag', () async {
    await preferences.telemetryTag.set("MOSSFERN");
    final tag = TextEditingController(text: "MOSSFERN");
    await TelemetryConsentChoice.choose(false, tag);
    expect(preferences.telemetryConsent.value, false);
    expect(tag.text, "");
    expect(preferences.telemetryTag.value, isNull);
  });

  test('"Yes" keeps the typed tag; Next saves it normalized', () async {
    final tag = TextEditingController(text: " mossfern ");
    await TelemetryConsentChoice.choose(true, tag);
    expect(tag.text, " mossfern ");
    expect(preferences.telemetryTag.value, isNull);
    await TelemetryConsentChoice.saveTag(tag.text);
    expect(preferences.telemetryTag.value, "MOSSFERN");
  });

  test('a tag is never saved without consent', () async {
    await TelemetryConsentChoice.saveTag("MOSSFERN");
    expect(preferences.telemetryTag.value, isNull);
  });

  test('invalid tags are not saved; an empty box removes the tag', () async {
    await preferences.telemetryConsent.set(true);
    await preferences.telemetryTag.set("OLD");
    await TelemetryConsentChoice.saveTag("a.b@c");
    expect(preferences.telemetryTag.value, "OLD");
    await TelemetryConsentChoice.saveTag("");
    expect(preferences.telemetryTag.value, isNull);
  });

  testWidgets('the tag box is disabled until "Yes"', (tester) async {
    Future<void> pump(bool enabled) => tester.pumpWidget(MaterialApp(
        home: Material(
            child: TelemetryTagField(
                controller: TextEditingController(),
                enabled: enabled,
                autoSave: false,
                showWarning: false))));

    await pump(false);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(find.text(telemetryTagOff), findsOneWidget);

    await pump(true);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
    expect(find.text(telemetryTagEmpty), findsOneWidget);
  });
}
