import 'package:commet/client/matrix/support/homeserver_support.dart';
import 'package:test/test.dart';

void main() {
  // Vommet issue 88: show the homeserver's support page / contacts.
  test('reads support page and contacts', () {
    final s = HomeserverSupport.fromJson({
      "support_page": "https://example.org/support",
      "contacts": [
        {"role": "m.role.admin", "matrix_id": "@admin:example.org"},
        {"role": "m.role.security", "email_address": "security@example.org"},
      ],
    })!;
    expect(s.supportPage, Uri.parse("https://example.org/support"));
    expect(s.contacts, hasLength(2));
    expect(s.contacts[0].matrixId, "@admin:example.org");
    expect(s.contacts[1].emailAddress, "security@example.org");
  });

  test('skips unsafe pages and incomplete contacts', () {
    final s = HomeserverSupport.fromJson({
      "support_page": "javascript:alert(1)",
      "contacts": [
        {"role": "m.role.admin"},
        {"matrix_id": "@norole:example.org"},
        "junk",
        {"role": "m.role.admin", "email_address": " admin@example.org "},
      ],
    })!;
    expect(s.supportPage, isNull);
    expect(s.contacts.single.emailAddress, "admin@example.org");
  });

  test('nothing usable gives null', () {
    expect(HomeserverSupport.fromJson({}), isNull);
    expect(HomeserverSupport.fromJson("nope"), isNull);
    expect(HomeserverSupport.fromJson({"support_page": "ftp://x"}), isNull);
  });

  test('well-known host drops the port', () {
    expect(HomeserverSupport.hostOf("example.org"), "example.org");
    expect(HomeserverSupport.hostOf("example.org:8448"), "example.org");
    expect(HomeserverSupport.hostOf("[::1]:8448"), "::1");
  });

  test('server name comes from the user ID, port kept', () {
    expect(HomeserverSupport.serverNameOf("@a:example.org"), "example.org");
    expect(HomeserverSupport.serverNameOf("@a:example.org:8448"),
        "example.org:8448");
    expect(HomeserverSupport.serverNameOf("@a:[::1]:8448"), "[::1]:8448");
    expect(HomeserverSupport.serverNameOf("@nodomain"), isNull);
    expect(HomeserverSupport.serverNameOf("@trailing:"), isNull);
    expect(HomeserverSupport.serverNameOf(null), isNull);
  });
}
