import 'dart:convert';
import 'dart:io';

import 'package:commet/client/matrix/components/widgets/runners/remote_http/self_signed_https_server.dart';
import 'package:commet/main.dart' show preferences;
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/tls_trust.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet issue 990: TLS errors that name the server whose certificate failed.
final certError = HandshakeException(
    "Handshake error in client",
    OSError(
        "CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate"));

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  tearDown(() => TlsTrust.describeError(certError));

  test('other errors are left alone', () {
    TlsTrust.recordFailure(null, "a.example", 443);
    expect(TlsTrust.describeError(Exception("boom")), "Exception: boom");
  });

  test('a handshake error that is not a certificate failure names no host', () {
    TlsTrust.recordFailure(null, "a.example", 443);
    final other = HandshakeException(
        "Handshake error in client", OSError("WRONG_VERSION_NUMBER"));
    expect(TlsTrust.describeError(other), other.toString());
  });

  test('a recorded failure is used once', () {
    TlsTrust.recordFailure(null, "a.example", 443);
    expect(TlsTrust.describeError(certError),
        startsWith("Couldn't verify the TLS certificate of a.example."));
    expect(TlsTrust.describeError(certError), certError.toString());
  });

  test('failures older than a minute are not used', () {
    final then = DateTime(2026, 11, 2, 12);
    TlsTrust.recordFailure(null, "a.example", 443, now: then);
    expect(
        TlsTrust.describeError(certError,
            now: then.add(const Duration(minutes: 2))),
        certError.toString());
  });

  test('several failing servers are all named', () {
    TlsTrust.recordFailure(null, "a.example", 443);
    TlsTrust.recordFailure(null, "b.example", 8448);
    final text = TlsTrust.describeError(certError);
    expect(text, contains("one of these servers"));
    expect(text, contains("b.example:8448"));
    expect(text, contains("a.example"));
  });

  testWidgets('the error dialog of a failed call names the server',
      (tester) async {
    TlsTrust.recordFailure(null, "sfu.example", 443);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () =>
                AdaptiveDialog.showError(c, certError, StackTrace.current),
            child: const Text('Call'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining("Couldn't verify the TLS certificate of "
            "sfu.example"),
        findsOneWidget);
    expect(find.textContaining("CERTIFICATE_VERIFY_FAILED"), findsOneWidget);
  });

  group('local TLS server', () {
    late HttpServer server;
    late CertificateData cert;

    setUpAll(() async {
      await TlsTrust.install();
      cert = await generateSelfSignedCertificate("localhost");
      final context = SecurityContext()
        ..useCertificateChainBytes(cert.certBytes)
        ..usePrivateKeyBytes(cert.privateKeyBytes);
      server =
          await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
      server.listen((request) {
        request.response.write("ok");
        request.response.close();
      });
    });

    tearDownAll(() => server.close(force: true));

    test('an unknown root is rejected, and its host is named', () async {
      Object? error;
      final client =
          HttpClient(context: SecurityContext(withTrustedRoots: true));
      try {
        final request =
            await client.getUrl(Uri.https("localhost:${server.port}", "/"));
        await (await request.close()).transform(utf8.decoder).join();
      } catch (e) {
        error = e;
      } finally {
        client.close(force: true);
      }
      expect(error, isA<HandshakeException>());
      expect(TlsTrust.describeError(error!),
          contains("certificate of localhost:${server.port}"));
    });
  });
}
