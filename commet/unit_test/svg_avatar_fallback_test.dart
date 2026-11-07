// Vommet issue 584: the SVG fallback for refused thumbnails (Vommet issue
// 309) checked the HTTP status of the thumbnail error, but the SDK's media
// calls throw the error without the response, so the status was always null
// and SVG avatars, room and space icons stayed empty.
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/client/matrix/matrix_media_failures.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/utils/image/svg_image.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" width="40" '
    'height="40"><circle cx="20" cy="20" r="18" fill="#f00"/></svg>';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {"content-type": "application/json"});

MatrixException _error(String errcode) =>
    MatrixException.fromJson({"errcode": errcode, "error": "x"});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group("mayTrySvgOriginal", () {
    test("errors as the SDK's media calls throw them (no response)", () {
      // Synapse's answer for media it can't thumbnail, a missing thumbnail,
      // a media repository error.
      for (final errcode in ["M_UNKNOWN", "M_NOT_FOUND", "M_TOO_LARGE"]) {
        final error = _error(errcode);
        expect(error.response, isNull);
        expect(MatrixMxcImage.mayTrySvgOriginal(error), isTrue,
            reason: errcode);
      }
    });

    test("not for sign-in, permission, rate limit or upload-pending errors",
        () {
      for (final errcode in [
        "M_FORBIDDEN",
        "M_UNKNOWN_TOKEN",
        "M_MISSING_TOKEN",
        "M_LIMIT_EXCEEDED",
        "M_NOT_YET_UPLOADED",
      ]) {
        expect(MatrixMxcImage.mayTrySvgOriginal(_error(errcode)), isFalse,
            reason: errcode);
      }
    });

    test("a known status still counts", () {
      final forbidden = MatrixException(http.Response(
          jsonEncode({"errcode": "M_UNKNOWN", "error": "x"}), 403));
      expect(MatrixMxcImage.mayTrySvgOriginal(forbidden), isFalse);
      final refused = MatrixException(http.Response(
          jsonEncode({"errcode": "M_UNKNOWN", "error": "x"}), 400));
      expect(MatrixMxcImage.mayTrySvgOriginal(refused), isTrue);
    });
  });

  group("thumbnail of an SVG", () {
    late Client client;
    late http.Response Function() thumbnailAnswer;
    late http.Response Function() downloadAnswer;
    late List<Uri> downloads;

    setUp(() async {
      MatrixMediaFailures.instance = MatrixMediaFailures();
      downloads = [];
      downloadAnswer = () =>
          http.Response(_svg, 200, headers: {"content-type": "image/svg+xml"});
      final mock = MockClient((request) async {
        if (request.url.path.contains("/thumbnail/")) {
          return thumbnailAnswer();
        }
        if (request.url.path.contains("/download/")) {
          downloads.add(request.url);
          return downloadAnswer();
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
          NativeDatabase.memory(), "svg fallback test");
      client =
          Client("svg-fallback-test", database: database, httpClient: mock);
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

    final avatar = Uri.parse("mxc://example.com/svgavatar");

    // Room, space, DM and member avatars load the 90 px thumbnail; profile
    // avatars the scaled one. None has an event.
    for (final scaled in [false, true]) {
      final kind =
          scaled ? "scaled (profile)" : "small (room, space, DM, member)";

      test("refused by the server ($kind): the original SVG is used", () async {
        thumbnailAnswer = () => _json({
              "errcode": "M_UNKNOWN",
              "error": "Cannot find any thumbnails for the requested media"
            }, 400);

        final Uint8List? bytes = await MatrixMxcImage.loadMatrixThumbnail(
            client, avatar, null,
            cache: true, scaled: scaled);

        expect(SvgImage.looksLikeSvg(bytes), isTrue);
        expect(utf8.decode(bytes!), _svg);
        expect(downloads.single.path,
            "/_matrix/client/v1/media/download/example.com/svgavatar");
      });
    }

    test("a thumbnail that's not found also checks the original", () async {
      thumbnailAnswer =
          () => _json({"errcode": "M_NOT_FOUND", "error": "Not found"}, 404);
      final bytes =
          await MatrixMxcImage.loadMatrixThumbnail(client, avatar, null);
      expect(SvgImage.looksLikeSvg(bytes), isTrue);
    });

    test("an original that isn't an SVG keeps the thumbnail's error", () async {
      thumbnailAnswer = () => _json({
            "errcode": "M_UNKNOWN",
            "error": "Cannot find any thumbnails for the requested media"
          }, 400);
      downloadAnswer = () => http.Response.bytes(
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], 200,
          headers: {"content-type": "image/png"});

      await expectLater(
          MatrixMxcImage.loadMatrixThumbnail(client, avatar, null),
          throwsA(isA<MatrixException>()
              .having((e) => e.errcode, "errcode", "M_UNKNOWN")));
      expect(downloads, hasLength(1));
    });

    test("rate limiting and forbidden media don't fetch the original",
        () async {
      for (final errcode in ["M_LIMIT_EXCEEDED", "M_FORBIDDEN"]) {
        thumbnailAnswer = () => _json({"errcode": errcode, "error": "x"},
            errcode == "M_FORBIDDEN" ? 403 : 429);
        await expectLater(
            MatrixMxcImage.loadMatrixThumbnail(client, avatar, null),
            throwsA(isA<MatrixException>()));
      }
      expect(downloads, isEmpty);
    });
  });
}
