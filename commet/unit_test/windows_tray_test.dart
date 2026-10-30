import 'package:commet/utils/tray/linux_tray.dart';
import 'package:commet/utils/tray/windows_tray.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 632: the Dart side of the Windows tray icon.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel("test/vommet_tray");
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == "start" ? true : null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> fromRunner(String method, [Object? arguments]) =>
      messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall(method, arguments)),
          (_) {});

  test("starts with the icon, tooltip and menu labels", () async {
    final tray = await WindowsTray.start(
      title: "Vommet",
      iconPixmaps: [
        const LinuxTrayPixmap(1, 1, [255, 1, 2, 3])
      ],
      onActivate: () {},
      menu: [
        const LinuxTrayMenuItem("Hide"),
        const LinuxTrayMenuItem.separator(),
        const LinuxTrayMenuItem("Quit"),
      ],
      channel: channel,
    );
    expect(tray, isNotNull);
    expect(tray!.available, isTrue);
    final args = calls.single.arguments as Map;
    expect(args["tooltip"], "Vommet");
    expect(args["menu"], ["Hide", null, "Quit"]);
    final icon = (args["icons"] as List).single as Map;
    expect(icon["width"], 1);
    expect(icon["argb"], Uint8List.fromList([255, 1, 2, 3]));
    await tray.dispose();
  });

  test("runs the clicked menu entry and the left-click action", () async {
    var activated = 0;
    var quit = 0;
    final tray = await WindowsTray.start(
      title: "Vommet",
      iconPixmaps: const [],
      onActivate: () => activated++,
      menu: [
        const LinuxTrayMenuItem("Hide"),
        const LinuxTrayMenuItem.separator(),
        LinuxTrayMenuItem("Quit", onClicked: () => quit++),
      ],
      channel: channel,
    );
    await fromRunner("activate");
    await fromRunner("menuClicked", 2);
    await fromRunner("menuClicked", 7);
    expect(activated, 1);
    expect(quit, 1);
    await tray!.dispose();
  });

  test("follows the runner's availability", () async {
    final tray = await WindowsTray.start(
      title: "Vommet",
      iconPixmaps: const [],
      onActivate: () {},
      menu: const [],
      channel: channel,
    );
    final changes = <bool>[];
    tray!.onAvailableChanged.listen(changes.add);
    await fromRunner("available", false);
    await fromRunner("available", true);
    await Future<void>.delayed(Duration.zero);
    expect(changes, [false, true]);
    await tray.dispose();
    expect(tray.available, isFalse);
  });

  test("puts the unread description on the tooltip's second line", () async {
    final tray = await WindowsTray.start(
      title: "Vommet",
      iconPixmaps: const [],
      onActivate: () {},
      menu: const [],
      channel: channel,
    );
    await tray!
        .setIcon(iconName: "", iconPixmaps: const [], description: "3 unread");
    expect((calls.last.arguments as Map)["tooltip"], "Vommet\n3 unread");
    await tray.dispose();
  });
}
