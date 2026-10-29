// Vommet: main.dart holds the splash screen with
// `clientManager.waitForStartupLoads().timeout(..., onTimeout: () {})`.
// Dart checks onTimeout against the future's runtime type when timeout() is
// called, so if waitForStartupLoads() hands back Future.wait's
// Future<List<void>> the app dies on every launch, although the analyzer is
// happy (testing.859).
import 'package:commet/client/client_manager.dart';
import 'package:test/test.dart';

void main() async {
  test("waitForStartupLoads is a real Future<void>", () {
    expect(ClientManager().waitForStartupLoads(), isA<Future<void>>());
    expect(ClientManager().waitForStartupLoads(),
        isNot(isA<Future<List<void>>>()));
  });

  test("waitForStartupLoads accepts main's void onTimeout", () async {
    await ClientManager()
        .waitForStartupLoads()
        .timeout(const Duration(seconds: 20), onTimeout: () {});
  });
}
