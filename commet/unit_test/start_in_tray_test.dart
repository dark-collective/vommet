import 'package:commet/utils/start_in_tray.dart';
import 'package:test/test.dart';

// Vommet issue 714: --start-in-tray starts hidden in the tray, or minimized
// when there's no tray.

void main() {
  late List<String> calls;
  late bool visible;

  Future<void> start({required bool tray}) => StartInTray.run(
        isVisible: () async => visible,
        waitForTray: (timeout) async {
          calls.add("wait ${timeout.inSeconds}s");
          return tray;
        },
        hideToTray: () async => calls.add("tray"),
        showMinimized: () async => calls.add("minimized"),
      );

  setUp(() {
    calls = [];
    visible = false;
  });

  test("only the flag requests it; --minimize doesn't", () {
    expect(StartInTray.requested(["--start-in-tray"]), isTrue);
    expect(StartInTray.requested(["--minimize"]), isFalse);
    expect(StartInTray.requested([]), isFalse);
  });

  test("hides to the tray once a tray shows the icon", () async {
    await start(tray: true);
    expect(calls, ["wait 10s", "tray"]);
  });

  test("starts minimized when there's no tray", () async {
    await start(tray: false);
    expect(calls, ["wait 10s", "minimized"]);
  });

  test("leaves a window the user opened while it waited", () async {
    visible = true;
    await start(tray: true);
    expect(calls, ["wait 10s"]);
  });
}
