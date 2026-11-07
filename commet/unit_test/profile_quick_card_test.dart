import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/profile_quick_card.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:commet/utils/redaction/redaction_preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _trigger = ValueKey('profile trigger');
const _identifier = '@user:example.org';

class _ClientManager extends Fake implements ClientManager {
  @override
  final clients = NotifyingList<Client>.from([_Client(), _Client()]);
}

class _Client extends Fake implements Client {
  @override
  Profile? get self => _Profile();

  @override
  T? getComponent<T extends Component>() => null;
}

class _Profile extends Fake implements Profile {
  @override
  String get identifier => _identifier;

  @override
  String get displayName => 'User NE';

  @override
  ImageProvider? get avatar => null;

  @override
  ImageProvider? get banner => null;

  @override
  Color get defaultColor => Colors.pink;
}

Future<void> _openCard(
  WidgetTester tester,
  Size size, {
  double? mediaHeight,
  double textScale = 1,
  EdgeInsets safePadding = EdgeInsets.zero,
  EdgeInsets? viewInsets,
  EdgeInsets overlayPadding = EdgeInsets.zero,
  double triggerLeft = 18,
  double? triggerTop,
}) async {
  final client = _Client();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    Padding(
      padding: overlayPadding,
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          platform: TargetPlatform.macOS,
          fontFamily: 'RobotoCustom',
        ),
        builder: (context, child) => RedactionScope(
          policy: RedactionPolicy(app.preferences.effectiveRedaction,
              salt: const [1, 1, 4, 1]),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: mediaHeight == null
                  ? MediaQuery.sizeOf(context)
                  : Size(size.width, mediaHeight),
              viewPadding: safePadding,
              viewInsets: viewInsets,
              padding: safePadding,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
        ),
        home: Material(
          child: Stack(
            children: [
              Positioned(
                left: triggerLeft,
                top: triggerTop,
                bottom: triggerTop == null ? 22 : null,
                child: Builder(
                  builder: (context) => TextButton(
                    key: _trigger,
                    onPressed: () =>
                        ProfileQuickCard.show(context, client: client),
                    child: const Text('User NE'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_trigger));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Flutter's default test font is much wider than the app font.
    final font = FontLoader('RobotoCustom')
      ..addFont(rootBundle.load('assets/font/roboto/Roboto-Regular.ttf'));
    await font.load();
  });

  setUp(() async {
    final original = app.clientManager;
    final originalPreferences = Preference.preferences;
    app.clientManager = _ClientManager();
    // The repository keeps Flutter widget tests under unit_test/.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      app.preferences.experimentQuickProfileControls.key: true,
      app.preferences.experimentRedactedMode.key: true,
      app.preferences.redactionEnabled.key: true,
    });
    Preference.preferences = await SharedPreferences.getInstance();
    addTearDown(() {
      app.clientManager = original;
      Preference.preferences = originalPreferences;
    });
  });

  testWidgets('keeps Copy user ID visible when route and media heights differ',
      (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const size = Size(464, 480);
    // Simulate inconsistent metrics. The macOS report gives no viewport size.
    await _openCard(tester, size,
        mediaHeight: 380, safePadding: const EdgeInsets.only(bottom: 16));

    final copy = find.text('Copy user ID');
    expect(tester.getBottomRight(copy).dy, lessThan(size.height - 16));
    expect(copy.hitTestable(), findsOneWidget);

    await tester.tapAt(const Offset(450, 100));
    await tester.pumpAndSettle();
    await _openCard(tester, const Size(700, 550));
    expect(
      tester.getRect(find.byType(ProfileQuickCard)).bottom,
      closeTo(tester.getRect(find.byKey(_trigger)).top - 8, 0.01),
    );
    expect(find.byType(Scrollable), findsOneWidget);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, 0);
  });

  testWidgets('scrolls the card on a short viewport and copies the ID',
      (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final channel = tester.binding.defaultBinaryMessenger;
    String? copied;
    channel.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
        () => channel.setMockMethodCallHandler(SystemChannels.platform, null));

    await _openCard(tester, const Size(280, 220),
        textScale: 1.65,
        safePadding: const EdgeInsets.only(top: 20, bottom: 16));

    final card = find.byType(ProfileQuickCard);
    expect(tester.getRect(card).top, greaterThanOrEqualTo(20));
    expect(tester.getRect(card).bottom, lessThanOrEqualTo(220 - 16));
    expect(tester.getRect(card).right, lessThanOrEqualTo(280));

    final copy = find.text('Copy user ID');
    expect(copy.hitTestable(), findsNothing);
    await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(card),
      scrollDelta: const Offset(0, 1000),
    ));
    await tester.pumpAndSettle();
    expect(copy.hitTestable(), findsOneWidget);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, _identifier);
    expect(card, findsNothing);
  });
  testWidgets('keeps the card inside left and top safe areas', (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const padding = EdgeInsets.only(left: 36, top: 32);
    await _openCard(tester, const Size(700, 550),
        safePadding: padding, triggerLeft: 4, triggerTop: 70);

    final card = tester.getRect(find.byType(ProfileQuickCard));
    expect(card.left, greaterThanOrEqualTo(padding.left));
    expect(card.top, greaterThanOrEqualTo(padding.top));
    expect(find.text('Copy user ID').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps the card inside the right safe area', (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const size = Size(700, 550);
    const padding = EdgeInsets.only(right: 60);
    await _openCard(tester, size, safePadding: padding, triggerLeft: 440);

    final card = tester.getRect(find.byType(ProfileQuickCard));
    expect(card.right, lessThanOrEqualTo(size.width - padding.right));
    expect(find.text('Copy user ID').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps the card above keyboard insets larger than safe padding',
      (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const size = Size(700, 600);
    const keyboardHeight = 160.0;
    await _openCard(tester, size,
        safePadding: const EdgeInsets.only(bottom: 16),
        viewInsets: const EdgeInsets.only(bottom: keyboardHeight));

    final card = tester.getRect(find.byType(ProfileQuickCard));
    expect(card.bottom, lessThanOrEqualTo(size.height - keyboardHeight));
    expect(tester.getBottomRight(find.text('Copy user ID')).dy,
        lessThan(size.height - keyboardHeight));
    expect(find.text('Copy user ID').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps safe padding when it exceeds keyboard insets',
      (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const size = Size(700, 600);
    const safeBottom = 80.0;
    await _openCard(tester, size,
        safePadding: const EdgeInsets.only(bottom: safeBottom),
        viewInsets: const EdgeInsets.only(bottom: 40));

    final card = tester.getRect(find.byType(ProfileQuickCard));
    expect(card.bottom, lessThanOrEqualTo(size.height - safeBottom));
    expect(find.text('Copy user ID').hitTestable(), findsOneWidget);
  });

  testWidgets('anchors in the root overlay when the navigator is offset',
      (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _openCard(tester, const Size(700, 600),
        overlayPadding: const EdgeInsets.only(left: 64, top: 40));

    final card = tester.getRect(find.byType(ProfileQuickCard));
    final trigger = tester.getRect(find.byKey(_trigger));
    expect(card.left, closeTo(trigger.left, 0.01));
    expect(card.bottom, closeTo(trigger.top - 8, 0.01));
    expect(find.text('Copy user ID').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps an already open card visible after window resize',
      (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _openCard(tester, const Size(700, 550));

    const resized = Size(360, 280);
    tester.view.physicalSize = resized;
    await tester.pumpAndSettle();

    final card = find.byType(ProfileQuickCard);
    expect(card, findsOneWidget);
    expect(tester.getRect(card).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(card).bottom, lessThanOrEqualTo(resized.height));
    await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(card),
      scrollDelta: const Offset(0, 1000),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Copy user ID').hitTestable(), findsOneWidget);
  });
}
