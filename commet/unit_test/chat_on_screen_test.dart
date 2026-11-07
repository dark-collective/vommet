import 'package:commet/ui/molecules/room_timeline_widget/chat_on_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 408: only the phone layout's chat panel says whether the chat
// is on screen; anywhere else a chat counts as visible.
void main() {
  testWidgets('no ChatOnScreen above means no notifier', (tester) async {
    ValueNotifier<bool>? found;
    await tester.pumpWidget(Builder(builder: (context) {
      found = ChatOnScreen.of(context);
      return const SizedBox();
    }));
    expect(found, isNull);
  });

  testWidgets('a chat behind the room list sees its panel\'s notifier',
      (tester) async {
    final visible = ValueNotifier(false);
    addTearDown(visible.dispose);
    ValueNotifier<bool>? found;
    await tester.pumpWidget(ChatOnScreen(
        visible: visible,
        child: Builder(builder: (context) {
          found = ChatOnScreen.of(context);
          return const SizedBox();
        })));
    expect(found, same(visible));
    expect(found!.value, isFalse);
  });
}
