// Vommet issue 584: a picture that failed with a definite server answer
// (deleted, or a remote server the homeserver can't fetch from) was asked
// for again on every retry and every time it was shown again, so most
// thumbnail requests were repeats of the same few failures.
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/client/matrix/matrix_media_failures.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

MatrixException _error(String errcode) =>
    MatrixException.fromJson({"errcode": errcode, "error": "x"});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group("MatrixMediaFailures", () {
    late DateTime now;
    late MatrixMediaFailures failures;
    late int loads;

    setUp(() {
      now = DateTime(2026, 10, 22, 12);
      failures =
          MatrixMediaFailures(ttl: const Duration(minutes: 15), now: () => now);
      loads = 0;
    });

    Future<String> failWith(Object error) async {
      loads++;
      throw error;
    }

    test("a lasting failure is replayed without loading again", () async {
      final notFound = _error("M_NOT_FOUND");
      await expectLater(
          failures.guard("a", () => failWith(notFound)), throwsA(notFound));
      expect(failures.isReplay(notFound), isFalse);

      await expectLater(
          failures.guard("a", () => failWith(notFound)), throwsA(notFound));
      expect(loads, 1);
      expect(failures.isReplay(notFound), isTrue);

      // Other media are unaffected.
      expect(await failures.guard("b", () async => "ok"), "ok");
    });

    test("server errors (remote fetch failures) are remembered too", () async {
      final unknown = _error("M_UNKNOWN");
      for (var i = 0; i < 4; i++) {
        await expectLater(
            failures.guard("a", () => failWith(unknown)), throwsA(unknown));
      }
      expect(loads, 1);
    });

    test("loads again after the ttl", () async {
      final notFound = _error("M_NOT_FOUND");
      await expectLater(
          failures.guard("a", () => failWith(notFound)), throwsA(notFound));
      now = now.add(const Duration(minutes: 16));
      expect(await failures.guard("a", () async => "back"), "back");
    });

    test("transient answers and network errors are never remembered", () async {
      for (final error in [
        _error("M_LIMIT_EXCEEDED"),
        _error("M_UNKNOWN_TOKEN"),
        _error("M_MISSING_TOKEN"),
        _error("M_NOT_YET_UPLOADED"),
        http.ClientException("XMLHttpRequest error."),
        Exception("http error response"),
      ]) {
        loads = 0;
        await expectLater(
            failures.guard("t", () => failWith(error)), throwsA(same(error)));
        await expectLater(
            failures.guard("t", () => failWith(error)), throwsA(same(error)));
        expect(loads, 2, reason: "$error");
      }
    });

    test("successes are not remembered", () async {
      expect(await failures.guard("a", () async => "one"), "one");
      expect(await failures.guard("a", () async => "two"), "two");
    });
  });

  group("MatrixMxcImage", () {
    late Client client;
    late List<Uri> thumbnailRequests;
    late http.Response Function() thumbnailAnswer;

    setUp(() async {
      MatrixMediaFailures.instance = MatrixMediaFailures();
      thumbnailRequests = [];
      final http = MockClient((request) async {
        if (request.url.path.contains("/thumbnail/")) {
          thumbnailRequests.add(request.url);
          return thumbnailAnswer();
        }
        if (request.url.path.endsWith("/sync")) {
          await Future.delayed(const Duration(seconds: 5));
          return _json({"next_batch": "s1"});
        }
        if (request.url.path.endsWith("/filter")) {
          return _json({"filter_id": "f"});
        }
        if (request.url.path.endsWith("/versions")) {
          return _json({
            "versions": ["v1.11"]
          });
        }
        return _json({});
      });
      final database = await MatrixSdkDriftDatabase.init(
          NativeDatabase.memory(), "media failure test");
      client =
          Client("media-failure-test", database: database, httpClient: http);
      await client.init(
        newToken: "token",
        newHomeserver: Uri.parse("https://example.com"),
        newUserID: "@me:example.com",
        newDeviceID: "DEVICE",
        newDeviceName: "test",
        waitForFirstSync: false,
      );
    });

    tearDown(() => client.dispose(closeDatabase: true));

    final missing = Uri.parse("mxc://gone.example/missing");

    Future<Uint8List?> load() => MatrixMxcImage.retryUntilOnline(client,
        () => MatrixMxcImage.loadMatrixThumbnail(client, missing, null));

    test("missing remote media is requested once, not on every retry",
        () async {
      thumbnailAnswer =
          () => _json({"errcode": "M_NOT_FOUND", "error": "Not found"}, 404);

      // The first load plus the image loader's three retries while shown,
      // then the avatar shown again elsewhere.
      for (var i = 0; i < 5; i++) {
        await expectLater(load(), throwsA(isA<MatrixException>()));
      }
      expect(thumbnailRequests, hasLength(1));
      expect(thumbnailRequests.single.path,
          startsWith("/_matrix/client/v1/media/thumbnail/gone.example/"));
    });

    test("a media repository error is requested once too", () async {
      thumbnailAnswer = () => _json({
            "errcode": "M_UNKNOWN",
            "error": "Unexpected Error",
            "mr_errcode": "M_UNKNOWN"
          }, 500);

      for (var i = 0; i < 3; i++) {
        await expectLater(load(), throwsA(isA<MatrixException>()));
      }
      expect(thumbnailRequests, hasLength(1));
    });

    test("a proxy's error page keeps its retries", () async {
      thumbnailAnswer = () => http.Response("<html>502</html>", 502);

      await expectLater(load(), throwsA(anything));
      // One attempt plus retryUntilOnline's two retries.
      expect(thumbnailRequests, hasLength(3));
      await expectLater(load(), throwsA(anything));
      expect(thumbnailRequests, hasLength(6));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {"content-type": "application/json"});
