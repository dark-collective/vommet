import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 862: cards never get narrower than minCardWidth.
void main() {
  test("two cards sit side by side from 460 px", () {
    expect(ChoiceCards.columnsFor(459, 2), 1);
    expect(ChoiceCards.columnsFor(460, 2), 2);
  });

  test("six cards on a phone stack, on a wide window wrap into rows", () {
    expect(ChoiceCards.columnsFor(380, 6), 1);
    expect(ChoiceCards.columnsFor(800, 6), 3);
    expect(ChoiceCards.columnsFor(3000, 6), 6);
  });
}
