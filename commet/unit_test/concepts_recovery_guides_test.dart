// Vommet issue 254: newcomers can follow the actual guide links between
// accounts and recovery without leaving the app, including on narrow phones.
import 'dart:io';

import 'package:commet/ui/pages/guides/guide_page.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    for (final route in [
      (Guides.accounts, 'Encryption and recovery', Guides.encryption),
      (Guides.encryption, 'Matrix accounts', Guides.accounts),
    ]) {
      testWidgets('Vommet issue 254: ${route.$1} links to ${route.$3} at $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? opened;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(
            body: ListView(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: GuideBody(
                      guide: Guides.byId(route.$1)!,
                      text: File('assets/guides/en/${route.$1}.md')
                          .readAsStringSync(),
                      onOpenGuide: (id) => opened = id,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final link = find.textContaining(route.$2, findRichText: true).last;
        await tester.scrollUntilVisible(link, 250,
            scrollable: find.byType(Scrollable).first);
        await Scrollable.ensureVisible(tester.element(link), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tapOnText(find.textRange.ofSubstring(route.$2));
        await tester.pumpAndSettle();
        expect(opened, route.$3);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
