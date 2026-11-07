// Vommet issue 1139: drive real Matrix message renderers, not a hand-made
// link span or consent stub. This file also runs unchanged against the base.
import 'dart:async';

import 'package:commet/config/app_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rich_text/spans/link.dart';
import 'package:commet/ui/pages/settings/categories/app/privacy_settings_page.dart';
import 'package:commet/utils/links/link_detector.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'helpers/magnet_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MagnetTestLauncher launcher;
  late MagnetTestManager manager;
  late UrlLauncherPlatform previousLauncher;
  final previousManager = clientManager;
  String? copied;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    previousLauncher = UrlLauncherPlatform.instance;
    launcher = MagnetTestLauncher();
    UrlLauncherPlatform.instance = launcher;
    manager = MagnetTestManager();
    clientManager = manager;
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = (call.arguments as Map)['text'] as String;
      return null;
    });
  });
  tearDown(() {
    UrlLauncherPlatform.instance = previousLauncher;
    clientManager = previousManager;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester t,
      {bool formatted = false, bool emote = false}) async {
    await t.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(body: message(formatted: formatted, emote: emote))));
    await t.pumpAndSettle();
  }

  Future<void> tapLink(WidgetTester t,
      {bool formatted = false, bool emote = false}) async {
    final needle = formatted ? 'Linux ISO' : 'magnet:';
    final found = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(needle));
    final paragraph = t.renderObject<RenderParagraph>(found.first);
    final offset = paragraph.text.toPlainText().indexOf(needle);
    final box = paragraph
        .getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1))
        .first;
    await t.tapAt(paragraph.localToGlobal(box.toRect().center));
    await t.pumpAndSettle();
  }

  Future<List<String>> trusted() async =>
      (await SharedPreferences.getInstance())
          .getStringList('vommet_trusted_magnet_senders') ??
      [];

  Future<void> pumpPrivacy(WidgetTester t) async {
    final previousPath = AppConfig.debugDatabasePath;
    AppConfig.debugDatabasePath = '/tmp/vommet-1139-empty-settings';
    addTearDown(() => AppConfig.debugDatabasePath = previousPath);
    await t.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: const Scaffold(
            body: SingleChildScrollView(child: PrivacySettingsPage()))));
    await t.pumpAndSettle();
  }

  test('whole magnet detection keeps repeated trackers and excludes code', () {
    for (final bare in [true, false]) {
      final links = LinkDetector.find('😀 ($magnet) then https://example.org',
          bareDomains: bare);
      expect(links.length, 2);
      expect(links.first.uri.toString(), magnet);
      expect(links.first.start, 4);
      expect(links.first.uri.queryParametersAll['tr']!.length, 2);
      expect(LinkDetector.find('`$magnet`'), isEmpty);
    }
  });

  for (final formatted in [false, true]) {
    for (final emote in [false, true]) {
      testWidgets(
          'message formatted=$formatted emote=$emote asks then opens once',
          (t) async {
        await pump(t, formatted: formatted, emote: emote);
        await tapLink(t, formatted: formatted, emote: emote);
        expect(find.text('Open magnet link?'), findsOneWidget);
        expect(find.text('From $sender'), findsOneWidget);
        expect(find.text('Using $me'), findsOneWidget);
        expect(launcher.launched, isEmpty);
        await t.tap(find.text('Open once'));
        await t.pumpAndSettle();
        expect(launcher.launched, kIsWeb ? isEmpty : [magnet]);
        expect(await trusted(), isEmpty);
      }, skip: kIsWeb);
    }
  }

  testWidgets('cancel, remember and subsequent same-sender tap', (t) async {
    await pump(t);
    await tapLink(t);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(launcher.launched, isEmpty);
    expect(await trusted(), isEmpty);
    await tapLink(t);
    await t.tap(find.byType(Checkbox));
    await t.pumpAndSettle();
    await t.tap(find.text('Open & remember'));
    await t.pumpAndSettle();
    expect(await trusted(), hasLength(1));
    await tapLink(t);
    expect(find.text('Open magnet link?'), findsNothing);
    expect(launcher.launched, [magnet, magnet]);
    await LinkUtils.open(Uri.parse(magnet), bypassConfirmation: true);
    expect(launcher.launched, [magnet, magnet]);
  }, skip: kIsWeb);

  for (final throws in [false, true]) {
    testWidgets('failed handoff throws=$throws offers copy without new trust',
        (t) async {
      launcher.accepted = false;
      launcher.throws = throws;
      await pump(t);
      await tapLink(t);
      await t.tap(find.byType(Checkbox));
      await t.pumpAndSettle();
      await t.tap(find.text('Open & remember'));
      await t.pumpAndSettle();
      expect(find.text('Couldn’t open magnet link'), findsOneWidget);
      expect(await trusted(), isEmpty);
      await t.tap(find.text('Copy link'));
      await t.pumpAndSettle();
      expect(copied, magnet);
    }, skip: kIsWeb);
  }

  testWidgets('absent sender still confirms even with generic bypass',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => LinkUtils.open(Uri.parse(magnet),
                    context: context, bypassConfirmation: true),
                child: const Text('Tap')))));
    await t.tap(find.text('Tap'));
    await t.pumpAndSettle();
    expect(find.text('Sender unavailable'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(launcher.launched, isEmpty);
    await t.tap(find.text(kIsWeb ? 'Copy link' : 'Open once'));
    await t.pumpAndSettle();
    expect(await trusted(), isEmpty);
  });

  testWidgets('web message offers Copy link and never persists permission',
      (t) async {
    await pump(t);
    await tapLink(t);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    await t.tap(find.text('Copy link'));
    await t.pumpAndSettle();
    expect(copied, magnet);
    expect(launcher.launched, isEmpty);
    expect(await trusted(), isEmpty);
  }, skip: !kIsWeb);

  testWidgets('invalid magnet offers copy and close without launching',
      (t) async {
    await pump(t);
    final context = t.element(find.byType(Scaffold));
    final uri = Uri.parse('magnet:?xt=urn:btih:bad');
    for (final action in ['Copy link', 'Close']) {
      await LinkUtils.open(uri, context: context, bypassConfirmation: true);
      await t.pumpAndSettle();
      expect(find.text('Invalid magnet link'), findsOneWidget);
      await t.tap(find.text(action));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(copied, uri.toString());
    expect(launcher.launched, isEmpty);
    expect(await trusted(), isEmpty);
  });

  testWidgets(
      'duplicate pending opens show one dialog and dismissal releases it',
      (t) async {
    await pump(t);
    final context = t.element(find.byType(Scaffold));
    for (var i = 0; i < 2; i++) {
      await LinkUtils.open(Uri.parse(magnet), context: context);
    }
    await t.pumpAndSettle();
    expect(find.text('Open magnet link?'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    Navigator.of(context).pop();
    await t.pumpAndSettle();
    await LinkUtils.open(Uri.parse(magnet), context: context);
    await t.pumpAndSettle();
    expect(find.text('Open magnet link?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(launcher.launched, isEmpty);
  });

  testWidgets('disposed consent context never launches or saves trust',
      (t) async {
    await pump(t);
    final context = t.element(find.byType(Scaffold));
    await tapLink(t);
    expect(find.text('Open magnet link?'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await LinkUtils.open(Uri.parse(magnet), context: context);
    await t.pumpAndSettle();
    expect(launcher.launched, isEmpty);
    expect(await trusted(), isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('account removed during consent cannot acquire remembered trust',
      (t) async {
    await pump(t);
    await tapLink(t);
    expect(find.text('Using $me'), findsOneWidget);
    await t.tap(find.byType(Checkbox));
    manager.present = false;
    await t.pumpAndSettle();
    await t.tap(find.text('Open & remember'));
    await t.pumpAndSettle();
    expect(launcher.launched, [magnet]);
    expect(await trusted(), isEmpty);
    await tapLink(t);
    expect(find.text('Sender unavailable'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    await t.tap(find.text('Cancel'));
  }, skip: kIsWeb);

  testWidgets('account removed during OS handoff cannot save late permission',
      (t) async {
    final response = Completer<bool>();
    launcher.response = response.future;
    await pump(t);
    await tapLink(t);
    expect(find.text('Using $me'), findsOneWidget);
    await t.tap(find.byType(Checkbox));
    await t.pumpAndSettle();
    await t.tap(find.text('Open & remember'));
    await t.pumpAndSettle();
    expect(launcher.launched, [magnet]);
    manager.present = false;
    response.complete(true);
    await t.pumpAndSettle();
    expect(await trusted(), isEmpty);
  }, skip: kIsWeb);

  testWidgets(
      'real Privacy removal restores confirmation on the next message tap',
      (t) async {
    await pump(t);
    await tapLink(t);
    await t.tap(find.byType(Checkbox));
    await t.pumpAndSettle();
    await t.tap(find.text('Open & remember'));
    await t.pumpAndSettle();
    expect(await trusted(), hasLength(1));
    await pumpPrivacy(t);
    await t.ensureVisible(find.byTooltip('Remove magnet trust'));
    await t.tap(find.byTooltip('Remove magnet trust'));
    await t.pumpAndSettle();
    expect(find.text('No trusted magnet senders'), findsOneWidget);
    expect(await trusted(), isEmpty);
    await pump(t);
    await tapLink(t);
    expect(find.text('Open magnet link?'), findsOneWidget);
    expect(launcher.launched, [magnet]);
    await t.tap(find.text('Cancel'));
  }, skip: kIsWeb);

  testWidgets('corrupt stored trust cannot blank the real Privacy screen',
      (t) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setStringList('vommet_trusted_magnet_senders', [
      '%zz|self|sender',
      'account|%40lee%3Aexample.org|%40alex%3Aexample.net',
    ]);
    await pumpPrivacy(t);
    await t.ensureVisible(find.text('Trusted magnet senders'));
    expect(find.text(sender), findsOneWidget);
    expect(find.byTooltip('Remove magnet trust'), findsOneWidget);
    expect(t.takeException(), isNull);
  }, skip: kIsWeb);

  testWidgets('malformed formatted magnet remains text with no link recognizer',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: message(formatted: true, target: '$magnet&dn=%zz'))));
    await t.pumpAndSettle();
    var links = 0;
    for (final text in t.widgetList<RichText>(find.byType(RichText))) {
      text.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer is LinkGestureRecognizer)
          links++;
        return true;
      });
    }
    expect(
        find.textContaining('Linux ISO', findRichText: true), findsOneWidget);
    expect(links, 0);
    expect(launcher.launched, isEmpty);
  });
}
