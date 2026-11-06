import 'package:commet/ui/pages/login/login_page_view.dart';
import 'package:test/test.dart';

void main() {
  // Vommet issue 39: a full Matrix ID in the username field fills in the
  // homeserver.
  test('full Matrix ID gives its server name', () {
    expect(LoginPageView.homeserverFromUserId('@alice:example.org'),
        'example.org');
    expect(LoginPageView.homeserverFromUserId('alice:matrix.example.org'),
        'matrix.example.org');
    expect(LoginPageView.homeserverFromUserId(' @bob:example.org:8448 '),
        'example.org:8448');
    expect(LoginPageView.homeserverFromUserId('@bob:localhost:8008'),
        'localhost:8008');
  });

  test('plain usernames and half-typed IDs give nothing', () {
    for (final input in [
      'alice',
      '@alice',
      '@alice:',
      '@alice:example',
      '@alice:example.',
      '@alice:example.org:',
      'alice@example.org',
      '@ali ce:example.org',
      '',
    ]) {
      expect(LoginPageView.homeserverFromUserId(input), isNull, reason: input);
    }
  });

  String? fill(String username, String current, {String? autoFilled}) =>
      LoginPageView.homeserverToFill(
          username: username,
          currentHomeserver: current,
          defaultHomeserver: 'matrix.org',
          autoFilled: autoFilled);

  test('replaces an empty field, the default, or an earlier fill', () {
    expect(fill('@alice:example.org', ''), 'example.org');
    expect(fill('@alice:example.org', 'matrix.org'), 'example.org');
    // Typing on: "@alice:example.co" was filled in, now "...com".
    expect(fill('@alice:example.com', 'example.co', autoFilled: 'example.co'),
        'example.com');
  });

  test('keeps a homeserver the user typed, and does nothing when it matches',
      () {
    expect(fill('@alice:example.org', 'matrix.example.org'), isNull);
    expect(
        fill('@alice:example.org', 'matrix.example.org',
            autoFilled: 'example.org'),
        isNull);
    expect(fill('@alice:example.org', 'example.org'), isNull);
    expect(fill('alice', 'matrix.org'), isNull);
  });
}
