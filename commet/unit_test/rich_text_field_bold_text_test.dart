import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rich_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 513: the composer builds its own spans, so it has to apply the
// system "Bold text" setting itself.
Future<TextSpan> _build(WidgetTester tester, bool boldText, String text) async {
  late TextSpan span;
  final controller = RichTextEditingController(client: null);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(boldText: boldText),
    child: Theme(
      data: ThemeData(),
      child: Builder(builder: (context) {
        span = controller.build(text, context);
        return const SizedBox();
      }),
    ),
  ));
  return span;
}

List<FontWeight?> _weights(TextSpan span) {
  final weights = <FontWeight?>[];
  span.visitChildren((child) {
    if (child is TextSpan && child.text != null) {
      weights.add(child.style?.fontWeight);
    }
    return true;
  });
  return weights;
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets("typed text is bold when Bold text is on", (tester) async {
    final weights = _weights(await _build(tester, true, "hello *there* you"));
    expect(weights, isNotEmpty);
    expect(weights, everyElement(FontWeight.bold));
  });

  testWidgets("typed text keeps the theme weight when Bold text is off",
      (tester) async {
    final weights = _weights(await _build(tester, false, "hello there"));
    expect(weights, isNotEmpty);
    expect(weights, everyElement(isNot(FontWeight.bold)));
  });
}
