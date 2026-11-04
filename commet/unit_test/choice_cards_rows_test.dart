import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 862: cards only sit side by side when each gets enough room.
void main() {
  test('six cards on a phone stack', () {
    expect(ChoiceCards.cardsPerRow(380, 6), 1);
  });

  test('six cards on a 460px row no longer share one row', () {
    expect(ChoiceCards.cardsPerRow(460, 6), 2);
  });

  test('a wide window fits as many as have room, up to the count', () {
    expect(ChoiceCards.cardsPerRow(900, 6), 4);
    expect(ChoiceCards.cardsPerRow(2000, 3), 3);
  });
}
