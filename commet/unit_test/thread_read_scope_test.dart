import 'package:commet/client/matrix/components/threads/thread_read_scope.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issues 804 and 805: "Read state per thread" scopes.
void main() {
  test("parses the stored names and nothing else", () {
    expect(ThreadReadScopes.parse("off"), ThreadReadScope.off);
    expect(ThreadReadScopes.parse("mine"), ThreadReadScope.mine);
    expect(ThreadReadScopes.parse("all"), ThreadReadScope.all);
    expect(ThreadReadScopes.parse("everything"), isNull);
    expect(ThreadReadScopes.parse(null), isNull);
  });

  test("of several spaces, the one tracking the most threads wins", () {
    expect(ThreadReadScopes.widest([]), isNull);
    expect(ThreadReadScopes.widest([ThreadReadScope.off, ThreadReadScope.mine]),
        ThreadReadScope.mine);
    expect(
        ThreadReadScopes.widest([
          ThreadReadScope.all,
          ThreadReadScope.off,
          ThreadReadScope.mine,
        ]),
        ThreadReadScope.all);
  });

  test("without a saved default it's Threads I'm in", () {
    expect(ThreadReadScopes.defaultOf({}), ThreadReadScope.mine);
    expect(
        ThreadReadScopes.defaultOf({"default": "bogus"}), ThreadReadScope.mine);
    expect(ThreadReadScopes.defaultOf({"rooms": <String, Object?>{}}),
        ThreadReadScope.mine);
  });

  test("a saved account default wins", () {
    for (final scope in ThreadReadScope.values) {
      expect(ThreadReadScopes.defaultOf({"default": scope.name}), scope);
    }
  });
}
