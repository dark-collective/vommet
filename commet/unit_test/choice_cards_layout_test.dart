import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet issue 862: many cards must not squeeze into one narrow row.
void main() {
  test("cards stack below the side-by-side width", () {
    expect(ChoiceCards.columnsFor(400, 3), 1);
    expect(ChoiceCards.columnsFor(400, 6), 1);
  });

  test("a row only holds as many cards as fit", () {
    expect(ChoiceCards.columnsFor(460, 2), 2);
    expect(ChoiceCards.columnsFor(460, 3), 2);
    expect(ChoiceCards.columnsFor(520, 3), 3);
    // Six app icons: balanced rows, never six 65 px cards.
    expect(ChoiceCards.columnsFor(460, 6), 2);
    expect(ChoiceCards.columnsFor(520, 6), 3);
    expect(ChoiceCards.columnsFor(720, 6), 3);
    expect(ChoiceCards.columnsFor(1100, 6), 6);
  });

  for (final width in [360.0, 470.0, 900.0]) {
    testWidgets("six cards with a badge fit ${width.toInt()} px",
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: width,
                      child: SingleChildScrollView(
                        child: ChoiceCards<int>(
                          selected: 0,
                          onSelected: (_) {},
                          options: [
                            for (var i = 0; i < 6; i++)
                              ChoiceCardOption(
                                value: i,
                                title: "Telegram style",
                                description: "A longer description text",
                                badge: i == 1 ? "Experimental" : null,
                                badgeExperimental: true,
                                onBadgeTap: () {},
                              ),
                          ],
                        ),
                      ))))));
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 6; i++) {
        final size = tester.getSize(find.byKey(ValueKey("choice-card-$i")));
        expect(
            size.width,
            greaterThanOrEqualTo(
                width < 460 ? width : ChoiceCards.minCardWidth));
      }
    });
  }
}
