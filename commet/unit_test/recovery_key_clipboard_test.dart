import 'package:commet/utils/recovery_key_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A recovery key copied for a password manager comes off the clipboard
  // when setup is done or left, but nothing else the user copied does.
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case "Clipboard.setData":
          clipboard = (call.arguments as Map)["text"] as String?;
          return null;
        case "Clipboard.getData":
          return clipboard == null ? null : {"text": clipboard};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  const key = "EsTj 3yST y93F SLpB jJsz eAXc 2XzA ygD3 w69H fGaN TKBj jXEd";

  test("clears the key it copied", () async {
    await Clipboard.setData(const ClipboardData(text: key));
    await RecoveryKeyClipboard.clearIfHolds(key);
    expect(clipboard, "");
  });

  test("ignores surrounding whitespace", () async {
    await Clipboard.setData(const ClipboardData(text: " $key\n"));
    await RecoveryKeyClipboard.clearIfHolds(key);
    expect(clipboard, "");
  });

  test("leaves something the user copied since", () async {
    await Clipboard.setData(const ClipboardData(text: "lunch at noon?"));
    await RecoveryKeyClipboard.clearIfHolds(key);
    expect(clipboard, "lunch at noon?");
  });

  test("nothing copied: nothing to do", () async {
    await Clipboard.setData(const ClipboardData(text: key));
    await RecoveryKeyClipboard.clearIfHolds(null);
    await RecoveryKeyClipboard.clearIfHolds("");
    expect(clipboard, key);
  });

  test("a clipboard that fails doesn't throw", () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (call) async => throw PlatformException(code: "busy"));
    await RecoveryKeyClipboard.clearIfHolds(key);
  });
}
