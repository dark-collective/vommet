// Vommet issue 503: "Always open links to <domain>" on the Open Link prompt
// trusts the link's exact host; Settings › Privacy lists and removes them.
import 'package:commet/main.dart';
import 'package:commet/utils/links/trusted_link_domains.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test('the domain is the lower-cased host of a web link', () {
    expect(TrustedLinkDomains.domainOf(Uri.parse("https://Docs.Example.com/a")),
        "docs.example.com");
    expect(TrustedLinkDomains.domainOf(Uri.parse("http://example.com:8080/")),
        "example.com");
    expect(
        TrustedLinkDomains.domainOf(Uri.parse("mailto:a@example.com")), isNull);
    expect(
        TrustedLinkDomains.domainOf(Uri.parse("ftp://example.com/")), isNull);
  });

  test('only the exact host is trusted', () async {
    await TrustedLinkDomains.trust(Uri.parse("https://www.example.com/x?y=1"));

    expect(TrustedLinkDomains.isTrusted(Uri.parse("https://www.example.com/")),
        isTrue);
    expect(TrustedLinkDomains.isTrusted(Uri.parse("http://WWW.example.com/z")),
        isTrue);
    expect(TrustedLinkDomains.isTrusted(Uri.parse("https://example.com/")),
        isFalse);
    expect(TrustedLinkDomains.isTrusted(Uri.parse("https://docs.example.com/")),
        isFalse);
  });

  test('trusting twice keeps one entry; remove stops trusting', () async {
    await TrustedLinkDomains.trust(Uri.parse("https://a.example.com/1"));
    await TrustedLinkDomains.trust(Uri.parse("https://a.example.com/2"));
    await TrustedLinkDomains.trust(Uri.parse("https://b.example.net/"));
    expect(TrustedLinkDomains.domains, ["a.example.com", "b.example.net"]);

    await TrustedLinkDomains.remove("a.example.com");
    expect(TrustedLinkDomains.domains, ["b.example.net"]);
    expect(TrustedLinkDomains.isTrusted(Uri.parse("https://a.example.com/")),
        isFalse);
  });

  testWidgets('the settings panel is hidden until a domain is trusted',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: const Scaffold(body: TrustedLinkDomainsPanel())));
    expect(find.text(trustedLinkDomainsHeader), findsNothing);

    await tester.runAsync(
        () => TrustedLinkDomains.trust(Uri.parse("https://docs.example.com/")));
    await tester.pumpAndSettle();
    expect(find.text(trustedLinkDomainsHeader), findsOneWidget);
    expect(find.text("docs.example.com"), findsOneWidget);

    await tester.tap(find.byTooltip(trustedLinkDomainsRemove));
    await tester.pumpAndSettle();
    expect(find.text(trustedLinkDomainsHeader), findsNothing);
  });

  testWidgets('the prompt switch starts off and reports changes',
      (tester) async {
    bool? reported;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
            body: TrustLinkDomainSwitch(
                domain: "docs.example.com",
                onChanged: (value) => reported = value))));
    expect(find.text(linkAlwaysOpenDomain("docs.example.com")), findsOneWidget);
    expect(reported, isNull);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(reported, isTrue);
  });
}
