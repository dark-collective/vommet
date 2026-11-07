import 'package:commet/utils/links/link_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // (message text, [(linked text, where it opens)]) with bare domains on.
  final cases = <(String, List<(String, String)>)>[
    (
      "discord.sektor64.net",
      [("discord.sektor64.net", "http://discord.sektor64.net")]
    ),
    (
      "join discord.sektor64.net tonight",
      [("discord.sektor64.net", "http://discord.sektor64.net")]
    ),
    (
      "example.com/path?x=1",
      [("example.com/path?x=1", "http://example.com/path?x=1")]
    ),
    (
      "example.com/a#frag",
      [("example.com/a#frag", "http://example.com/a#frag")]
    ),
    (
      "sub.example.com:8080/x",
      [("sub.example.com:8080/x", "http://sub.example.com:8080/x")]
    ),
    ("see example.com.", [("example.com", "http://example.com")]),
    ("see example.com, then", [("example.com", "http://example.com")]),
    ("is it example.com?", [("example.com", "http://example.com")]),
    ("wow example.com!", [("example.com", "http://example.com")]),
    ("(example.com)", [("example.com", "http://example.com")]),
    (
      "(see example.com/path)",
      [("example.com/path", "http://example.com/path")]
    ),
    (
      "en.wikipedia.org/wiki/Foo_(bar)",
      [
        (
          "en.wikipedia.org/wiki/Foo_(bar)",
          "http://en.wikipedia.org/wiki/Foo_(bar)"
        )
      ]
    ),
    ("\"example.com\"", [("example.com", "http://example.com")]),
    ("'example.com'", [("example.com", "http://example.com")]),
    ("EXAMPLE.COM", [("EXAMPLE.COM", "http://example.com")]),
    ("test.sh", [("test.sh", "http://test.sh")]),
    (
      "notes.md and api.io and claude.ai",
      [
        ("notes.md", "http://notes.md"),
        ("api.io", "http://api.io"),
        ("claude.ai", "http://claude.ai"),
      ]
    ),
    ("user@example.org", [("user@example.org", "mailto:user@example.org")]),
    (
      "mail first.last+tag@mail.example.org now",
      [
        (
          "first.last+tag@mail.example.org",
          "mailto:first.last+tag@mail.example.org"
        )
      ]
    ),
    (
      "first.last@example.org, user+tag@example.org",
      [
        ("first.last@example.org", "mailto:first.last@example.org"),
        ("user+tag@example.org", "mailto:user+tag@example.org"),
      ]
    ),
    (
      "script.py, main.rs, app.zip",
      [
        ("script.py", "http://script.py"),
        ("main.rs", "http://main.rs"),
        ("app.zip", "http://app.zip"),
      ]
    ),
    (
      "192.168.1.1:8080/x",
      [("192.168.1.1:8080/x", "http://192.168.1.1:8080/x")]
    ),
    ("ping 10.0.0.1", [("10.0.0.1", "http://10.0.0.1")]),
    // Links with a scheme or www. keep working as before (www. now opens).
    (
      "https://example.com/a.",
      [("https://example.com/a", "https://example.com/a")]
    ),
    ("www.example.com", [("www.example.com", "http://www.example.com")]),
    (
      "http://localhost:3000/x",
      [("http://localhost:3000/x", "http://localhost:3000/x")]
    ),
    (
      "two: a.com and b.org",
      [("a.com", "http://a.com"), ("b.org", "http://b.org")]
    ),
    // Not links.
    ("file.txt", []),
    ("v1.2.3", []),
    ("1.2.3", []),
    ("e.g. this", []),
    ("i.e.", []),
    ("node.js", []),
    ("main.go", []),
    ("end.Next sentence", []),
    ("999.1.1.1", []),
    ("foo.example.com", [("foo.example.com", "http://foo.example.com")]),
    ("/usr/lib.so", []),
    ("#tag.com", []),
    ("under_score.example_.com", []),
    ("in `example.com` code", []),
    ("```\nexample.com\n```", []),
    ("@alice:example.org said hi", []),
    ("#room:nether.im", []),
    ("!abc:example.org", []),
    ("", []),
    ("no dots here", []),
  ];

  for (final (text, expected) in cases) {
    test("links in '$text'", () {
      final found = LinkDetector.find(text);
      expect(found.map((l) => (l.text, l.uri.toString())).toList(), expected);
      for (final l in found) {
        expect(text.substring(l.start, l.end), l.text);
      }
    });
  }

  test("off: only http(s):// and www. links, like before", () {
    expect(
        LinkDetector.find("discord.sektor64.net", bareDomains: false), isEmpty);
    expect(LinkDetector.find("user@example.org", bareDomains: false), isEmpty);
    expect(
        LinkDetector.find("see https://example.com and example.org",
                bareDomains: false)
            .map((l) => l.text),
        ["https://example.com"]);
    expect(
        LinkDetector.find("www.example.com", bareDomains: false)
            .map((l) => l.uri.toString()),
        ["http://www.example.com"]);
  });

  test("offsets survive emoji before the link", () {
    const text = "😀😀 example.com";
    final found = LinkDetector.find(text);
    expect(found.single.text, "example.com");
    expect(text.substring(found.single.start, found.single.end), "example.com");
  });

  test("email check matches TDLib", () {
    expect(LinkDetector.isEmailAddress("a@b.co"), isTrue);
    expect(LinkDetector.isEmailAddress("a@b.c"), isFalse);
    expect(LinkDetector.isEmailAddress("a b@c.com"), isFalse);
    expect(LinkDetector.isEmailAddress("a@-b.com"), isFalse);
  });
}
