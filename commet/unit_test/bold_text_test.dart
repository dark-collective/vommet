import 'package:commet/utils/bold_text.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TextStyle?> _resolve(
    WidgetTester tester, bool boldText, TextStyle? style) async {
  TextStyle? result;
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(boldText: boldText),
    child: Builder(builder: (context) {
      result = withBoldText(context, style);
      return const SizedBox();
    }),
  ));
  return result;
}

void main() {
  const style = TextStyle(fontWeight: FontWeight.w400, fontSize: 12);

  testWidgets("leaves the style alone when Bold text is off", (tester) async {
    expect(await _resolve(tester, false, style), style);
    expect(await _resolve(tester, false, null), isNull);
  });

  testWidgets("overrides an explicit weight when Bold text is on",
      (tester) async {
    final bold = (await _resolve(tester, true, style))!;
    expect(bold.fontWeight, FontWeight.bold);
    expect(bold.fontSize, 12);
    expect((await _resolve(tester, true, null))!.fontWeight, FontWeight.bold);
  });
}
