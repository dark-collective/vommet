import 'package:commet/config/app_language.dart';
import 'package:commet/utils/app_language_switch.dart';
import 'package:commet/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

String get labelSettingsAppGeneral => Intl.message("General",
    name: "labelSettingsAppGeneral", desc: "Test copy of the settings label");

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => TextButton(
      onPressed: () => setState(() => taps++),
      child: Text("$labelSettingsAppGeneral $taps"));
}

void main() {
  tearDown(() async {
    await AppLanguageSwitch.apply(AppLanguages.byId(AppLanguages.english)!);
  });

  testWidgets("switching language rebuilds text and keeps state",
      (tester) async {
    await AppLanguageSwitch.apply(AppLanguages.byId(AppLanguages.english)!);
    await tester.pumpWidget(Builder(
        builder: (_) => MaterialApp(
            localizationsDelegates: AppLocalizations.delegates,
            locale: AppLocalizations.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: _Probe()))));
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text("General 1"), findsOneWidget);

    late bool ok;
    await tester.runAsync(() async {
      ok = await AppLanguageSwitch.apply(AppLanguages.byId("de")!);
    });
    expect(ok, isTrue);
    await tester.pumpAndSettle();

    expect(find.text("Allgemein 1"), findsOneWidget);
    expect(Localizations.localeOf(tester.element(find.byType(_Probe))),
        const Locale("de"));
  });

  testWidgets("a language intl has no data for still switches", (tester) async {
    late bool ok;
    await tester.runAsync(() async {
      ok = await AppLanguageSwitch.apply(AppLanguages.byId("eo")!);
    });
    expect(ok, isTrue);
    expect(Intl.defaultLocale, "eo");
    expect(DateFormat.yMd().format(DateTime(2026, 10, 14)), isNotEmpty);
  });
}
