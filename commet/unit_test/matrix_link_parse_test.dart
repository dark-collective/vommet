import 'package:commet/client/matrix/matrix_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("matrix.to links without a target don't throw", () {
    for (final link in [
      "https://matrix.to",
      "https://matrix.to/",
      "https://matrix.to/#",
      "https://matrix.to/#/",
      "https://matrix.to/#/%zz",
    ]) {
      expect(MatrixClient.parseMatrixLink(Uri.parse(link)), isNull,
          reason: link);
    }
  });

  test("matrix.to links still parse", () {
    expect(
        MatrixClient.parseMatrixLink(
            Uri.parse("https://matrix.to/#/%23room:example.org")),
        (MatrixLinkType.roomAlias, "#room:example.org", "#room:example.org"));
    expect(
        MatrixClient.parseMatrixLink(
                Uri.parse("https://matrix.to/#/@user:example.org"))
            ?.$1,
        MatrixLinkType.user);
    expect(
        MatrixClient.parseMatrixLink(
                Uri.parse("https://matrix.to/#/!abc:example.org?via=x"))
            ?.$2,
        "!abc:example.org");
  });

  test("links to a message name the room, keeping every via", () {
    expect(
        MatrixClient.parseMatrixLink(Uri.parse(
            "https://matrix.to/#/!abc:example.org/\$event?via=a.org&via=b.org")),
        (
          MatrixLinkType.room,
          "!abc:example.org",
          "!abc:example.org?via=a.org,b.org"
        ));
    expect(
        MatrixClient.parseMatrixLink(
            Uri.parse("https://matrix.to/#/%23room:example.org/%24event")),
        (MatrixLinkType.roomAlias, "#room:example.org", "#room:example.org"));
  });
}
