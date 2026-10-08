import 'package:commet/utils/links/matrix_link.dart';
import 'package:flutter_test/flutter_test.dart';

MatrixLinkTarget? parse(String link) => MatrixLinkTarget.parse(Uri.parse(link));

void main() {
  group("matrix: URIs", () {
    test("room alias", () {
      final t = parse("matrix:r/somewhere:example.org")!;
      expect(t.kind, MatrixLinkKind.roomAlias);
      expect(t.identifier, "#somewhere:example.org");
      expect(t.via, isEmpty);
      expect(t.roomAddress, "#somewhere:example.org");
    });

    test("room id with via and action", () {
      final t = parse(
          "matrix:roomid/somewhere:example.org?via=elsewhere.ca&via=a.b&action=join")!;
      expect(t.kind, MatrixLinkKind.room);
      expect(t.identifier, "!somewhere:example.org");
      expect(t.via, ["elsewhere.ca", "a.b"]);
      expect(t.roomAddress, "!somewhere:example.org?via=elsewhere.ca,a.b");
    });

    test("event in a room", () {
      final t = parse("matrix:roomid/somewhere:example.org/e/event?via=x.y")!;
      expect(t.identifier, "!somewhere:example.org");
      expect(t.eventId, "\$event");
    });

    test("user", () {
      final t = parse("matrix:u/alice:example.org?action=chat")!;
      expect(t.kind, MatrixLinkKind.user);
      expect(t.identifier, "@alice:example.org");
    });

    test("percent-encoded identifier", () {
      expect(parse("matrix:r/caf%C3%A9:example.org")!.identifier,
          "#café:example.org");
    });

    test("with an authority", () {
      expect(parse("matrix://example.org/u/alice:example.org")!.identifier,
          "@alice:example.org");
    });

    test("unknown or incomplete", () {
      expect(parse("matrix:x/foo:example.org"), isNull);
      expect(parse("matrix:r"), isNull);
      expect(parse("matrix:r/"), isNull);
    });
  });

  group("matrix.to links", () {
    test("room alias, raw and encoded", () {
      expect(parse("https://matrix.to/#/#somewhere:example.org")!.identifier,
          "#somewhere:example.org");
      final t = parse("https://matrix.to/#/%23somewhere%3Aexample.org")!;
      expect(t.kind, MatrixLinkKind.roomAlias);
      expect(t.identifier, "#somewhere:example.org");
    });

    test("room id with via", () {
      final t = parse(
          "https://matrix.to/#/!somewhere:example.org?via=elsewhere.ca&via=a.b")!;
      expect(t.kind, MatrixLinkKind.room);
      expect(t.via, ["elsewhere.ca", "a.b"]);
    });

    test("event permalink", () {
      final t =
          parse("https://matrix.to/#/!somewhere:example.org/\$event?via=x.y")!;
      expect(t.identifier, "!somewhere:example.org");
      expect(t.eventId, "\$event");
      expect(t.via, ["x.y"]);
    });

    test("user", () {
      final t = parse("https://matrix.to/#/@alice:example.org")!;
      expect(t.kind, MatrixLinkKind.user);
      expect(t.identifier, "@alice:example.org");
    });

    test("not a Matrix link", () {
      expect(parse("https://matrix.to/"), isNull);
      expect(parse("https://matrix.to/#/"), isNull);
      expect(parse("https://example.org/#/@alice:example.org"), isNull);
      expect(parse("commetchat://add_widget?url=x"), isNull);
    });
  });
}
