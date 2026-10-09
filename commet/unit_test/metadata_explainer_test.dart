import 'package:commet/ui/organisms/attachment_processor/metadata_explainer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("metadata explainer fits a phone and says what isn't removed",
      (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
        home:
            Scaffold(body: SingleChildScrollView(child: MetadataExplainer()))));
    expect(tester.takeException(), isNull);
    expect(find.textContaining("Google Docs"), findsWidgets);
    expect(find.textContaining("can't remove"), findsWidgets);
  });
}
