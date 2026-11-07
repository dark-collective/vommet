import 'package:commet/client/matrix/matrix_server_features.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/molecules/profile_quick_card.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/self_status_fixture.dart';

Widget _fixtureMedia(BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
    child: child!);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('RobotoCustom')
          ..addFont(rootBundle.load('assets/font/roboto/Roboto-Regular.ttf')))
        .load();
  });
  for (final style in LayoutStyle.values) {
    for (final phone in [false, true]) {
      final label = '${style.name}-${phone ? 'phone' : 'desktop'}';
      testWidgets('fresh self status and live clear: $label', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
        await app.preferences.init();
        await (style == LayoutStyle.discord
                ? LayoutOptions.discord
                : LayoutOptions.telegram)
            .save();
        if (style == LayoutStyle.custom) {
          await app.preferences.chatBubbleLayout.set(false);
          await layoutStyleCustomPicked.set(true);
        }
        await app.preferences.experimentQuickProfileControls.set(true);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            phone ? const Size(390, 844) : const Size(1280, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = SelfStatusFixture();
        final manager = app.clientManager;
        await tester.runAsync(() async {
          await f.init();
          await f.sdk.fetchCurrentPresence(selfStatusId);
          await f.profile(refresh: false);
          await MatrixServerFeatures.of(f.account);
        });
        expect(f.presenceGets, 1,
            reason: 'only capability probe before opening');
        app.clientManager = SelfStatusManager(f.account);
        Future<void> settle() async {
          // Yield native I/O/event queues without a wall-clock delay.
          for (var turn = 0; turn < 8; turn++) {
            await tester.runAsync(() async {
              await Future<void>(() {});
            });
            await tester.pumpAndSettle();
          }
        }

        Future<void> open() async {
          await tester.pumpWidget(MaterialApp(
            builder: _fixtureMedia,
            theme: ThemeData(
                brightness: Brightness.dark,
                platform: TargetPlatform.linux,
                fontFamily: 'RobotoCustom'),
            home: Scaffold(
                body: Center(
                    child: SizedBox(
              width: 300,
              child: Builder(
                  builder: (context) => ProfileQuickCard(
                      client: f.account, hostContext: context)),
            ))),
          ));
          await settle();
        }

        try {
          await open();
          expect(
              MediaQuery.textScalerOf(
                      tester.element(find.byType(ProfileQuickCard)))
                  .scale(16),
              16);
          expect(find.text('SERVER B'), findsOneWidget,
              reason: tester
                  .widgetList<Text>(find.byType(Text))
                  .map((text) => text.data)
                  .join(' | '));
          expect(find.text('CACHED A'), findsNothing);
          expect(f.presenceGets, 2,
              reason: 'the card initiates its own fresh status read');
          final requests = f.presenceGets;
          final profileRequests = f.profileGets;
          await tester.runAsync(() => f.sync(null));
          await settle();
          expect(find.text('Set a status'), findsOneWidget);
          expect(find.text('SERVER B'), findsNothing);
          await tester.pumpWidget(const SizedBox());
          await open();
          expect(find.text('Set a status'), findsOneWidget);
          expect(find.text(legacyStatus), findsNothing);
          expect(f.presenceGets, requests,
              reason: 'no per-update or repeated-open fetch');
          expect(f.profileGets, profileRequests,
              reason: 'status refresh must preserve fresh profile field cache');
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(f.close);
          app.clientManager = manager;
        }
      });
    }
  }
  for (final phone in [false, true]) {
    testWidgets('full self profile accepts live status and clear: phone=$phone',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await app.preferences.init();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize =
          phone ? const Size(390, 844) : const Size(1280, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = SelfStatusFixture();
      await tester.runAsync(() async {
        await f.init();
        await f.sdk.fetchCurrentPresence(selfStatusId);
        await f.profile(refresh: false);
        await MatrixServerFeatures.of(f.account);
      });
      Future<void> settle() async {
        for (var turn = 0; turn < 8; turn++) {
          await tester.runAsync(() async {
            await Future<void>(() {});
          });
          await tester.pumpAndSettle();
        }
      }

      try {
        await tester.pumpWidget(MaterialApp(
            builder: _fixtureMedia,
            theme: ThemeData(
                brightness: Brightness.dark,
                platform: TargetPlatform.linux,
                fontFamily: 'RobotoCustom'),
            home: Scaffold(
                body: SingleChildScrollView(
              child: UserProfile(
                  client: f.account,
                  userId: selfStatusId,
                  width: phone ? 390 : 700,
                  showMessageButton: false),
            ))));
        await settle();
        final fresh = find.text('SERVER B').evaluate().length;
        await tester.runAsync(() => f.sync('PROFILE LIVE'));
        await settle();
        final live = find.text('PROFILE LIVE').evaluate().length;
        await tester.runAsync(() => f.sync(null));
        await settle();
        expect(fresh, 1);
        expect(live, 1);
        expect(find.text('PROFILE LIVE'), findsNothing);
        expect(find.text(legacyStatus), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(f.close);
      }
    });
  }
  for (final status in [403, 404]) {
    testWidgets(
        'denied own card hides status without private fallback: $status',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await app.preferences.init();
      await app.preferences.experimentQuickProfileControls.set(true);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = SelfStatusFixture()..errorStatus = status;
      final manager = app.clientManager;
      await tester.runAsync(f.init);
      app.clientManager = SelfStatusManager(f.account);
      try {
        await tester.pumpWidget(MaterialApp(
            builder: _fixtureMedia,
            home: Scaffold(
                body: Builder(
                    builder: (context) => ProfileQuickCard(
                        client: f.account, hostContext: context)))));
        for (var turn = 0; turn < 8; turn++) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pumpAndSettle();
        }
        expect(find.text('Set a status'), findsNothing);
        expect(find.text(legacyStatus), findsNothing);
        expect(find.text('CACHED A'), findsNothing);
        expect(f.presenceGets, 1);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(f.close);
        app.clientManager = manager;
      }
    });
  }
}
