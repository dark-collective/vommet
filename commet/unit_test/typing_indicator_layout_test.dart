import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/typing_indicators_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  T? getComponent<T extends Component>() => null;
}

class _Member extends Fake implements Member {
  @override
  String get identifier => '@alice:example.org';

  @override
  String get displayName => 'Alice';
}

class _Typing extends Fake implements TypingIndicatorComponent {
  final updates = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get onTypingUsersUpdated => updates.stream;

  @override
  List<Member> typingUsers = [];

  void setTyping(bool typing) {
    typingUsers = typing ? [_Member()] : [];
    updates.add(null);
  }
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  tearDown(() => preferences.layoutOverride.set(null));

  for (final style in LayoutStyle.values) {
    for (final mobile in [true, false]) {
      testWidgets(
        '${style.name} ${mobile ? 'phone' : 'desktop'} typing layout',
        (tester) async {
          // Exercise scaled text and reduced motion on the narrower viewport.
          final reducedMotion = mobile;
          final scale = mobile ? 3.0 : 1.0;
          await preferences.layoutOverride.set(mobile ? 'mobile' : 'desktop');
          if (style == LayoutStyle.custom) {
            await pickLayoutStyle(LayoutStyle.telegram);
          }
          await pickLayoutStyle(style);
          addTearDown(() => pickLayoutStyle(LayoutStyle.discord));

          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(mobile ? 412 : 1096, 700);
          addTearDown(tester.view.reset);
          final typing = _Typing();
          final scroll = ScrollController();
          final client = _Client();
          const timelineKey = ValueKey('timeline');
          const historyKey = ValueKey('history');

          Future<void> pumpChat({required bool showIndicator}) async {
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: reducedMotion,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        child: CustomScrollView(
                          key: timelineKey,
                          controller: scroll,
                          reverse: true,
                          center: historyKey,
                          slivers: [
                            SliverFixedExtentList.builder(
                              key: historyKey,
                              itemExtent: 52,
                              itemCount: 50,
                              itemBuilder: (_, index) =>
                                  Text('Message ${50 - index}'),
                            ),
                          ],
                        ),
                      ),
                      MessageInput(
                        client: client,
                        availibleEmoticons: const [],
                        onSendMessage: (message, {overrideClient}) =>
                            MessageInputSendResult.success,
                        typingIndicatorWidget: showIndicator
                            ? TypingIndicatorsWidget(component: typing)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pump();
          }

          final timeline = find.byKey(timelineKey);
          final input = find.byType(TextField);
          await pumpChat(showIndicator: false);
          final baseline = tester.getRect(timeline);
          final inputBounds = tester.getRect(input);

          await pumpChat(showIndicator: true);
          expect(
            tester.getRect(timeline),
            baseline,
            reason: 'An idle indicator should reserve no timeline space.',
          );
          expect(tester.getRect(input), inputBounds);

          for (final offset in [0.0, 250.0]) {
            scroll.jumpTo(offset);
            await tester.pump();
            typing.setTyping(true);
            await tester.pump();
            if (!reducedMotion) {
              await tester.pump(Durations.medium3 ~/ 2);
              expect(
                tester.getRect(timeline).bottom,
                inExclusiveRange(baseline.bottom - 23, baseline.bottom),
              );
              await tester.pump(Durations.medium3);
            }
            final label = find.text('Alice is typing...');
            final labelBounds = tester.getRect(label);
            final typingBottom = tester.getRect(timeline).bottom;
            expect(typingBottom, lessThan(baseline.bottom));
            expect(labelBounds.top, greaterThanOrEqualTo(typingBottom));
            expect(labelBounds.bottom, lessThanOrEqualTo(baseline.bottom));
            if (scale == 1) expect(baseline.bottom - typingBottom, 23);
            if (scale > 1)
              expect(baseline.bottom - typingBottom, greaterThan(23));
            expect(tester.getRect(input), inputBounds);
            expect(scroll.offset, offset);

            typing.setTyping(false);
            await tester.pump();
            if (!reducedMotion) await tester.pump(Durations.medium3);
            expect(tester.getRect(timeline), baseline);
            expect(tester.getRect(input), inputBounds);
            expect(scroll.offset, offset);
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await typing.updates.close();
          scroll.dispose();
        },
      );
    }
  }
}
