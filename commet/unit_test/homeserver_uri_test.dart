import 'package:commet/utils/homeserver_uri.dart';
import 'package:test/test.dart';

void main() {
  test("A bare address means https", () {
    expect(
        homeserverUriFromInput("matrix.org"), Uri.parse("https://matrix.org"));
    expect(homeserverUriFromInput("localhost:8448"),
        Uri.parse("https://localhost:8448"));
    expect(homeserverUriFromInput(" example.org "),
        Uri.parse("https://example.org"));
  });

  test("A typed http:// is kept", () {
    var uri = homeserverUriFromInput("http://127.0.0.1:8008");
    expect(uri?.scheme, "http");
    expect(uri?.host, "127.0.0.1");
    expect(uri?.port, 8008);

    expect(homeserverUriFromInput("HTTP://localhost:8008")?.scheme, "http");
    expect(homeserverUriFromInput("http://[::1]:8008")?.host, "::1");
    expect(homeserverUriFromInput("http://192.168.1.5")?.scheme, "http");
  });

  test("A typed https:// is kept", () {
    expect(homeserverUriFromInput("https://matrix.org"),
        Uri.parse("https://matrix.org"));
    expect(
        homeserverUriFromInput("https://example.org/matrix")?.path, "/matrix");
  });

  test("Anything without an http(s) host is rejected", () {
    expect(homeserverUriFromInput(""), isNull);
    expect(homeserverUriFromInput("   "), isNull);
    expect(homeserverUriFromInput("http://"), isNull);
    expect(homeserverUriFromInput("ftp://example.org"), isNull);
    expect(homeserverUriFromInput("https://example.org?x=1"), isNull);
    expect(homeserverUriFromInput("http://user:pw@example.org"), isNull);
  });

  test("The https:// prefix shows only without a typed scheme", () {
    expect(homeserverInputHasScheme("matrix.org"), isFalse);
    expect(homeserverInputHasScheme("http://127.0.0.1"), isTrue);
    expect(homeserverInputHasScheme("Https://matrix.org"), isTrue);
    expect(homeserverInputHasScheme("http"), isFalse);
  });

  test("Plain http is flagged unless it stays on this device", () {
    bool insecure(String input) =>
        homeserverUriIsInsecure(homeserverUriFromInput(input)!);

    expect(insecure("http://192.168.1.20:8008"), isTrue);
    expect(insecure("http://matrix.example.org"), isTrue);
    expect(insecure("http://127.example.org"), isTrue);
    expect(insecure("http://[fe80::1]:8008"), isTrue);

    expect(insecure("http://127.0.0.1:8008"), isFalse);
    expect(insecure("http://127.1.2.3"), isFalse);
    expect(insecure("http://localhost:8008"), isFalse);
    expect(insecure("HTTP://LOCALHOST"), isFalse);
    expect(insecure("http://matrix.localhost"), isFalse);
    expect(insecure("http://[::1]:8008"), isFalse);

    expect(insecure("matrix.example.org"), isFalse);
    expect(insecure("https://192.168.1.20"), isFalse);
  });
}
