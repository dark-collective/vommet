import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cards stack when one would be narrower than the minimum', () {
    expect(ChoiceCards.columnsFor(300, 2), 1);
    expect(ChoiceCards.columnsFor(460, 2), 2);
  });

  test('six cards use fewer columns on a phone-sized row', () {
    expect(ChoiceCards.columnsFor(400, 6), 1);
    expect(ChoiceCards.columnsFor(700, 6), 3);
    expect(ChoiceCards.columnsFor(2000, 6), 6);
  });
}
