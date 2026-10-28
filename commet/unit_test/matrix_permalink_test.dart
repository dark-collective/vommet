import 'package:commet/client/matrix/forwarding/forward_content.dart';
import 'package:commet/client/matrix/matrix_permalink.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/links/matrix_link.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 665: "Copy message link".
void main() {
  test("via: highest-powered member's server, then the most populated", () {
    final via = MatrixPermalink.viaServers([
      ("@a:big.org", 0),
      ("@b:big.org", 0),
      ("@c:big.org", 0),
      ("@d:mid.org", 0),
      ("@e:mid.org", 0),
      ("@f:small.org", 0),
      ("@g:tiny.org", 0),
      ("@admin:admin.org", 100),
    ]);
    expect(via, ["admin.org", "big.org", "mid.org"]);
  });

  test("via: no member at power level 50 or more means population only", () {
    expect(
        MatrixPermalink.viaServers([
          ("@a:one.org", 49),
          ("@b:two.org", 0),
          ("@c:two.org", 0),
        ]),
        ["two.org", "one.org"]);
  });

  test("via: skips IP literals and servers the ACL denies", () {
    final acl = {
      "allow": ["*"],
      "deny": ["*.evil.org"],
    };
    final via = MatrixPermalink.viaServers([
      ("@a:1.2.3.4", 100),
      ("@b:[::1]:8448", 0),
      ("@c:spam.evil.org", 0),
      ("@d:good.org:8448", 0),
    ], allowed: (s) => MatrixPermalink.aclAllows(acl, s));
    expect(via, ["good.org:8448"]);
  });

  test("ACL: none allows all, an empty allow list allows none", () {
    expect(MatrixPermalink.aclAllows(null, "x.org"), isTrue);
    expect(MatrixPermalink.aclAllows({"allow": []}, "x.org"), isFalse);
    expect(
        MatrixPermalink.aclAllows({
          "allow": ["x.or?"]
        }, "x.org:443"),
        isTrue);
  });

  test("the link opens back at the message", () {
    final link = ForwardContent.eventPermalink("!room:nether.im", "\$event_id",
        via: ["nether.im", "matrix.org"]);
    expect(link,
        "https://matrix.to/#/!room%3Anether.im/%24event_id?via=nether.im&via=matrix.org");
    final target = MatrixLinkTarget.parse(Uri.parse(link))!;
    expect(target.kind, MatrixLinkKind.room);
    expect(target.identifier, "!room:nether.im");
    expect(target.eventId, "\$event_id");
    expect(target.via, ["nether.im", "matrix.org"]);
  });

  test("a pending jump is taken once, by its own room", () {
    EventBus.setPendingJump("!a:x.org", "\$e");
    expect(EventBus.takePendingJump("!b:x.org"), isNull);
    expect(EventBus.takePendingJump("!a:x.org"), "\$e");
    expect(EventBus.takePendingJump("!a:x.org"), isNull);
  });
}
