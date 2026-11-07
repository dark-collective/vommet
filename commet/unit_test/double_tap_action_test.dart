import 'package:commet/ui/molecules/timeline_events/double_tap_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DoubleTapAction defaults', () {
    test('React on phones, Nothing on computers', () {
      expect(DoubleTapAction.parse("", phone: true), DoubleTapAction.react);
      expect(DoubleTapAction.parse("", phone: false), DoubleTapAction.nothing);
    });

    test('a stored choice wins over the default', () {
      expect(
          DoubleTapAction.parse("reply", phone: true), DoubleTapAction.reply);
      expect(DoubleTapAction.parse("edit", phone: false), DoubleTapAction.edit);
      expect(DoubleTapAction.parse("nothing", phone: true),
          DoubleTapAction.nothing);
    });

    test('an unknown value falls back to the default', () {
      expect(DoubleTapAction.parse("wave", phone: true), DoubleTapAction.react);
    });
  });

  group('DoubleTapAction.forMessage', () {
    DoubleTapAction on(DoubleTapAction chosen,
            {bool react = true, bool reply = true, bool edit = true}) =>
        DoubleTapAction.forMessage(chosen,
            canReact: react, canReply: reply, canEdit: edit);

    test('Edit on someone else\'s message replies', () {
      expect(on(DoubleTapAction.edit, edit: false), DoubleTapAction.reply);
      expect(on(DoubleTapAction.edit), DoubleTapAction.edit);
    });

    test('an action the message does not take does nothing', () {
      expect(on(DoubleTapAction.react, react: false), DoubleTapAction.nothing);
      expect(on(DoubleTapAction.reply, reply: false), DoubleTapAction.nothing);
      expect(on(DoubleTapAction.edit, edit: false, reply: false),
          DoubleTapAction.nothing);
      expect(on(DoubleTapAction.nothing), DoubleTapAction.nothing);
    });
  });

  test('a heart matches with or without the variation selector', () {
    expect(DoubleTapAction.sameEmoji("❤️", "❤"), isTrue);
    expect(DoubleTapAction.sameEmoji("❤️", "👍"), isFalse);
  });
}
