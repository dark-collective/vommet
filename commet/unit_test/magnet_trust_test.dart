// Vommet issue 1139: permission isolation, revocation, validation and sizing.
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/utils/links/magnet_links.dart';
import 'package:commet/utils/links/magnet_uri.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'helpers/magnet_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const origin = MessageLinkOrigin('account', me, sender);
  final previousManager = clientManager;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    clientManager = MagnetTestManager();
  });
  tearDown(() => clientManager = previousManager);

  test('trust uses exact receiving account, self ID and sender', () async {
    await MagnetSenderTrust.remember(origin);
    expect(MagnetSenderTrust.contains(origin), isTrue);
    for (final other in [
      const MessageLinkOrigin('other', me, sender),
      const MessageLinkOrigin('account', '@other:example.org', sender),
      const MessageLinkOrigin('account', me, '@other:example.net'),
      const MessageLinkOrigin('account', null, sender),
    ]) {
      expect(MagnetSenderTrust.contains(other), isFalse);
    }
    (clientManager as MagnetTestManager).present = false;
    expect(MagnetSenderTrust.contains(origin), isFalse);
    await MagnetSenderTrust.remember(
        const MessageLinkOrigin('account', me, '@new:example.net'));
    expect(MagnetSenderTrust.entries, hasLength(1));
  });

  test('remove and account removal restore default with no empty stored key',
      () async {
    await MagnetSenderTrust.remember(origin);
    await MagnetSenderTrust.remove(origin);
    expect(MagnetSenderTrust.contains(origin), isFalse);
    expect(preferences.trustedMagnetSenders.hasStoredValue, isFalse);
    await MagnetSenderTrust.remember(origin);
    await preferences.removeMagnetTrustForAccount('other');
    expect(MagnetSenderTrust.contains(origin), isTrue);
    await preferences.removeMagnetTrustForAccount('account');
    expect(preferences.trustedMagnetSenders.hasStoredValue, isFalse);
  });

  test('reject invalid and unsupported schemes; keep supported v1/v2 magnets',
      () {
    expect(MagnetUri.isValid(Uri.parse(magnet)), isTrue);
    expect(MagnetUri.isValid(Uri.parse('magnet:?xt=urn:btmh:1220${'a' * 64}')),
        isTrue);
    for (final raw in [
      'https://example.org',
      'javascript:alert(1)',
      'magnet://example.org?xt=urn:btih:${'a' * 40}',
      'magnet:?dn=Linux.iso',
      'magnet:?xt=urn:btih:bad',
      '$magnet&dn=%0A',
      '$magnet&dn=%zz'
    ]) {
      expect(MagnetUri.parse(raw), isNull, reason: raw);
    }
  });

  test('malformed stored keys are ignored and cannot grant sender trust',
      () async {
    await preferences.trustedMagnetSenders.set([
      'bad',
      'account||sender',
      '%zz|self|sender',
      const MessageLinkOrigin('account-extra', me, sender).key,
    ]);
    expect(MagnetSenderTrust.entries, hasLength(1));
    expect(MagnetSenderTrust.contains(origin), isFalse);
    await MagnetSenderTrust.remember(origin);
    await MagnetSenderTrust.remember(origin);
    expect(preferences.trustedMagnetSenders.value.where((k) => k == origin.key),
        hasLength(1));
    await preferences.removeMagnetTrustForAccount('account');
    expect(preferences.trustedMagnetSenders.value,
        contains(const MessageLinkOrigin('account-extra', me, sender).key));
  });

  testWidgets('revoke one account keeps the same sender in the other account',
      (t) async {
    const other = MessageLinkOrigin('other', '@other:example.org', sender);
    await preferences.trustedMagnetSenders.set([origin.key, other.key]);
    await t.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: const Scaffold(body: TrustedMagnetSendersPanel())));
    expect(find.text(sender), findsNWidgets(2));
    await t.tap(find.byTooltip(MagnetText.remove).first);
    await t.pumpAndSettle();
    expect(preferences.trustedMagnetSenders.value, [other.key]);
    expect(find.text('@other:example.org'), findsOneWidget);
    expect(find.text(MagnetText.empty), findsNothing);
    await t.tap(find.byTooltip(MagnetText.remove));
    await t.pumpAndSettle();
    expect(find.text(MagnetText.empty), findsOneWidget);
    expect(preferences.trustedMagnetSenders.hasStoredValue, isFalse);
  });

  testWidgets('settings removal restores confirmation and empty state',
      (t) async {
    await MagnetSenderTrust.remember(origin);
    await t.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: const Scaffold(body: TrustedMagnetSendersPanel())));
    expect(find.text(me), findsOneWidget);
    expect(find.text(sender), findsOneWidget);
    await t.tap(find.byTooltip(MagnetText.remove));
    await t.pumpAndSettle();
    expect(find.text(MagnetText.empty), findsOneWidget);
    expect(MagnetSenderTrust.contains(origin), isFalse);
  });

  for (final style in LayoutStyle.values) {
    for (final size in [
      const Size(1100, 700),
      const Size(360, 800),
      const Size(320, 640)
    ]) {
      testWidgets('confirmation fits $style at $size with large text',
          (t) async {
        await pickLayoutStyle(style);
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(MaterialApp(
            theme: ThemeDark.theme,
            builder: (_, child) => MediaQuery(
                data: MediaQueryData(
                    size: size, textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => MagnetLinkConfirmation(
                                uri: Uri.parse(magnet), origin: origin)),
                        child: const Text('Tap'))))));
        await t.tap(find.text('Tap'));
        await t.pumpAndSettle();
        expect(find.text(MagnetText.title), findsOneWidget);
        expect(find.text(MagnetText.openOnce), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(find.text(MagnetText.cancel));
        await t.pumpAndSettle();
        await LinkUtils.open(Uri.parse('magnet:?xt=bad'),
            context: t.element(find.byType(Scaffold)));
        await t.pumpAndSettle();
        expect(find.text(MagnetText.invalid), findsOneWidget);
        expect(find.text(MagnetText.copy), findsOneWidget);
        expect(find.text(MagnetText.close), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(find.text(MagnetText.close));
        await t.pumpAndSettle();
      });
    }
  }
}
