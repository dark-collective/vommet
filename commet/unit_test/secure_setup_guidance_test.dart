import 'dart:async';
import 'dart:convert';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/login_password_memory.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_flow.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_storage_help.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Entirely offline fixtures: no crypto initialization or account requests.
const fixtureKey = 'FICTIONAL RECOVERY KEY FOR UI TESTS ONLY';
const fixturePassword = 'fictional blue balloons drift over imaginary hills';

class GuidanceSdk implements matrix.Client {
  @override
  String get userID => '@fictional:example.invalid';
  @override
  String? get prevBatch => null;
  @override
  Encryption? get encryption => null;
  @override
  String get deviceID => 'FICTIONAL';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GuidanceClient implements MatrixClient {
  final sdk = GuidanceSdk();
  @override
  matrix.Client getMatrixClient() => sdk;
  @override
  bool get firstSyncComplete => false;
  @override
  Stream<void> get onSync => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GuidanceController extends SecureSetupController {
  GuidanceController(super.client);
  final calls = <({String? passphrase, bool replace, bool keepBackup})>[];
  Object? failure;
  int replacements = 0;
  @override
  Future<bool> checkKey(String input, {bool currentKeyOnly = false}) async =>
      input == fixtureKey;
  @override
  Future<String> replaceKey(String currentInput, {String? passphrase}) async {
    if (currentInput != fixtureKey) throw WrongRecoveryKeyException();
    replacements++;
    return fixtureKey;
  }

  @override
  Future<String> setUpNew(
      {String? passphrase,
      required bool replaceExisting,
      bool keepBackup = false}) async {
    calls.add((
      passphrase: passphrase,
      replace: replaceExisting,
      keepBackup: keepBackup
    ));
    if (failure != null) throw failure!;
    return fixtureKey;
  }
}

Future<void> tapGuidance(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// Clipboard messages and wordlist assets can finish outside the fake frame clock.
Future<void> waitGuidance(WidgetTester tester, String text) async {
  for (var i = 0; i < 100 && find.text(text).evaluate().isEmpty; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
  }
  expect(find.text(text), findsOneWidget);
}

Future<GuidanceController> openGuidance(WidgetTester tester,
    {Size size = const Size(390, 844),
    double textScale = 1,
    SecureMessagingState status = SecureMessagingState.notSetUp,
    SecureSetupStart start = SecureSetupStart.signIn,
    void Function(bool)? onFinished}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  final client = GuidanceClient();
  final controller = GuidanceController(client);
  await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: SecureSetupFlow(
          client: client,
          controller: controller,
          status: SecureMessagingStatus(status),
          start: start,
          onFinished: onFinished ?? (_) {})));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  String? clipboard;
  setUp(() async {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String;
          return null;
        case 'Clipboard.getData':
          return clipboard == null ? null : {'text': clipboard};
        default:
          return null;
      }
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
  });

  testWidgets('help returns to the selected method without creating keys',
      (tester) async {
    final controller = await openGuidance(tester);
    await tapGuidance(tester, secureSetupIntroStart);
    expect(tester.widget<SetupOption>(find.byType(SetupOption).first).selected,
        isTrue);
    await tapGuidance(tester, secureSetupOptionPassword);
    await tapGuidance(tester, secureSetupNoManagerTitle);
    expect(find.byType(SecureSetupStorageHelp), findsOneWidget);
    expect(find.text(secureSetupStorageBitwarden), findsOneWidget);
    expect(controller.calls, isEmpty);
    await tapGuidance(tester, secureSetupStorageBack);
    expect(tester.widget<SetupOption>(find.byType(SetupOption).last).selected,
        isTrue);
    await tapGuidance(tester, secureSetupContinue);
    expect(find.text(secureSetupPasswordTitle), findsOneWidget);
    expect(controller.calls, isEmpty);
  });

  testWidgets('a new step starts at the heading after scrolling the intro',
      (tester) async {
    await openGuidance(tester, size: const Size(1100, 900), textScale: 1.5);
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        greaterThan(0));
    await tapGuidance(tester, secureSetupIntroStart);
    expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        0);
    expect(find.text(secureSetupChooseTitle).hitTestable(), findsOneWidget);
  });

  testWidgets(
      'default key path requires the complete saved key and clears clipboard',
      (tester) async {
    final controller = await openGuidance(tester);
    await tapGuidance(tester, secureSetupIntroStart);
    await tapGuidance(tester, secureSetupContinue);
    expect(controller.calls.single,
        (passphrase: null, replace: false, keepBackup: false));
    expect(find.text(secureSetupSaveKeyManualBody), findsOneWidget);
    await tapGuidance(tester, secureSetupStorageHelpLink);
    await tapGuidance(tester, secureSetupStorageBack);
    expect(controller.calls, hasLength(1));
    await tapGuidance(tester, secureSetupCopyForManager);
    await waitGuidance(tester, secureSetupCheckKeyTitle);
    expect(clipboard, fixtureKey);
    await tester.enterText(
        find.byType(TextField).last, 'fictional wrong input');
    await tapGuidance(tester, secureSetupCheck);
    expect(find.text(secureSetupCheckKeyMismatch), findsOneWidget);
    expect(
        SecureSetupRecords(controller.client.getMatrixClient().userID!).method,
        isNull);
    await tester.enterText(
        find.byType(TextField).last, fixtureKey.replaceAll(' ', '\n'));
    await tapGuidance(tester, secureSetupCheck);
    await waitGuidance(tester, secureSetupDoneTitle);
    expect(
        SecureSetupRecords(controller.client.getMatrixClient().userID!).method,
        RecoveryMethod.key);
    expect(clipboard, isEmpty);
    expect(controller.calls, hasLength(1));
  });

  testWidgets('system-save platforms retain Save and a manual-copy fallback',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = await openGuidance(tester);
    await tapGuidance(tester, secureSetupIntroStart);
    await tapGuidance(tester, secureSetupContinue);
    expect(find.text(secureSetupSaveKeyBody), findsOneWidget);
    expect(find.text(secureSetupSave), findsOneWidget);
    expect(find.text(secureSetupCopyMyself), findsOneWidget);
    await tapGuidance(tester, secureSetupCopyMyself);
    await waitGuidance(tester, secureSetupCheckKeyTitle);
    expect(controller.calls, hasLength(1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'password option retains strength, re-entry and recovery-method record',
      (tester) async {
    final controller = await openGuidance(tester);
    await tapGuidance(tester, secureSetupIntroStart);
    await tapGuidance(tester, secureSetupOptionPassword);
    await tapGuidance(tester, secureSetupContinue);
    final button = find.byType(SetupPrimaryButton).last;
    expect(tester.widget<SetupPrimaryButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, fixturePassword);
    await tapGuidance(tester, secureSetupContinue);
    expect(controller.calls.single.passphrase, fixturePassword);
    expect(find.text(secureSetupCheckPasswordTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'fictional mismatch');
    await tapGuidance(tester, secureSetupCheck);
    expect(find.text(secureSetupCheckPasswordMismatch), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, fixturePassword);
    await tapGuidance(tester, secureSetupCheck);
    await waitGuidance(tester, secureSetupDoneTitle);
    expect(
        SecureSetupRecords(controller.client.getMatrixClient().userID!).method,
        RecoveryMethod.password);
  });

  testWidgets('phrase option retains two-word verification before completion',
      (tester) async {
    // Six deliberately long fictional words exercise the real phrase layout.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      if (!path.endsWith('eff_large_wordlist.txt')) return null;
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(
          [for (var i = 0; i < 6; i++) 'fictionalrecoveryword$i'].join('\n'))));
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    final controller =
        await openGuidance(tester, size: const Size(320, 740), textScale: 2);
    await tapGuidance(tester, secureSetupIntroStart);
    await tapGuidance(tester, secureSetupOptionPhrase);
    await tapGuidance(tester, secureSetupContinue);
    await waitGuidance(tester, secureSetupPhraseTitle);
    expect(controller.calls, isEmpty);
    await tapGuidance(tester, secureSetupPhraseGotThem);
    final words = controller.calls.single.passphrase!.split(' ');
    expect(words, hasLength(6));
    expect(words.every((word) => word.startsWith('fictionalrecoveryword')),
        isTrue);
    final fields = find.byType(TextField);
    for (var i = 0; i < 2; i++) {
      await tester.enterText(fields.at(i), 'fictional-wrong-word');
    }
    await tapGuidance(tester, secureSetupCheck);
    expect(find.text(secureSetupCheckPhraseWrong), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      final label =
          tester.widget<TextField>(fields.at(i)).decoration!.labelText!;
      final index = int.parse(RegExp(r'\d+').firstMatch(label)![0]!) - 1;
      await tester.enterText(fields.at(i), words[index]);
    }
    await tapGuidance(tester, secureSetupCheck);
    await waitGuidance(tester, secureSetupDoneTitle);
    expect(
        SecureSetupRecords(controller.client.getMatrixClient().userID!).method,
        RecoveryMethod.phrase);
  });

  testWidgets('known sign-in password is still refused for recovery',
      (tester) async {
    final controller = await openGuidance(tester);
    LoginPasswordMemory.remember(
        controller.client.getMatrixClient().userID!, fixturePassword);
    await tapGuidance(tester, secureSetupIntroStart);
    await tapGuidance(tester, secureSetupOptionPassword);
    await tapGuidance(tester, secureSetupContinue);
    await tester.enterText(find.byType(TextField).last, fixturePassword);
    await tester.pumpAndSettle();
    expect(find.text(secureSetupPasswordIsLoginTitle), findsOneWidget);
    expect(
        tester
            .widget<SetupPrimaryButton>(find.byType(SetupPrimaryButton).last)
            .onPressed,
        isNull);
    expect(controller.calls, isEmpty);
  });

  testWidgets('new-key mode keeps the backup after explicit hold',
      (tester) async {
    final controller =
        await openGuidance(tester, start: SecureSetupStart.newKey);
    expect(controller.calls, isEmpty);
    final hold = tester.widget<HoldButton>(find.byType(HoldButton)).duration;
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
    await tester.pump();
    await tester.pump(hold + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    await tapGuidance(tester, secureSetupContinue);
    expect(controller.calls.single,
        (passphrase: null, replace: true, keepBackup: true));
  });

  testWidgets(
      'replacement still checks the old key and retains replacement mode',
      (tester) async {
    final controller =
        await openGuidance(tester, start: SecureSetupStart.replaceKey);
    await tapGuidance(tester, secureSetupContinue);
    await tester.enterText(find.byType(TextField).last, 'fictional mismatch');
    await tapGuidance(tester, secureSetupReplaceUnlockContinue);
    expect(find.text(secureSetupReplaceWrongKey), findsOneWidget);
    expect(controller.replacements, 0);
    await tester.enterText(find.byType(TextField).last, fixtureKey);
    await tapGuidance(tester, secureSetupReplaceUnlockContinue);
    await tapGuidance(tester, secureSetupNoManagerTitle);
    await tapGuidance(tester, secureSetupStorageBack);
    await tapGuidance(tester, secureSetupContinue);
    expect(controller.calls, isEmpty);
    expect(controller.replacements, 1);
    expect(find.text(secureSetupSaveKeyTitle), findsOneWidget);
  });

  testWidgets('existing account guard still redirects instead of making keys',
      (tester) async {
    final controller = await openGuidance(tester);
    controller.failure = ExistingSetupException();
    await tapGuidance(tester, secureSetupIntroStart);
    await tapGuidance(tester, secureSetupContinue);
    expect(find.text(secureSetupExistingTitle), findsOneWidget);
    expect(find.text(secureSetupErrorAlreadySetUp), findsOneWidget);
    expect(find.byType(RecoveryKeyText), findsNothing);
    expect(controller.calls.single.replace, isFalse);
  });

  testWidgets('existing account direct key entry never offers creation',
      (tester) async {
    final controller = await openGuidance(tester,
        status: SecureMessagingState.thisDeviceUnverified,
        start: SecureSetupStart.enterKey);
    expect(find.text(secureSetupEnterKeyTitle), findsOneWidget);
    expect(find.text(secureSetupIntroStart), findsNothing);
    expect(controller.calls, isEmpty);
  });

  for (final size in const [Size(320, 740), Size(1100, 900)]) {
    testWidgets('all choices and help remain reachable at 200% text: $size',
        (tester) async {
      final controller = await openGuidance(tester, size: size, textScale: 2);
      await tapGuidance(tester, secureSetupIntroStart);
      for (final title in [
        secureSetupOptionPassword,
        secureSetupOptionPhrase,
        secureSetupOptionManager
      ]) {
        await tapGuidance(tester, title);
        expect(tester.takeException(), isNull);
      }
      await tapGuidance(tester, secureSetupNoManagerTitle);
      await tester.ensureVisible(find.text(secureSetupStoragePaperBody));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapGuidance(tester, secureSetupStorageBack);
      expect(controller.calls, isEmpty);
      expect(find.byType(SetupOption), findsNWidgets(3));
    });
  }
}
