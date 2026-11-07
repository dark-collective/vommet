import 'package:commet/client/matrix/matrix_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("matches the main alias", () {
    expect(
        MatrixClient.canonicalAliasMatches(
            {"alias": "#devel:example.org"}, "#devel:example.org"),
        isTrue);
  });

  test("matches an alt alias", () {
    expect(
        MatrixClient.canonicalAliasMatches({
          "alias": "#dev:example.org",
          "alt_aliases": ["#devel:example.org"]
        }, "#devel:example.org"),
        isTrue);
  });

  test("no match without the alias, or without the state", () {
    expect(
        MatrixClient.canonicalAliasMatches(
            {"alias": "#other:example.org"}, "#devel:example.org"),
        isFalse);
    expect(MatrixClient.canonicalAliasMatches(null, "#devel:example.org"),
        isFalse);
    expect(
        MatrixClient.canonicalAliasMatches(
            {"alt_aliases": "#devel:example.org"}, "#devel:example.org"),
        isFalse);
  });
}
