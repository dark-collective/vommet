import 'package:commet/utils/app_exit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Exited implements Exception {
  _Exited(this.code);
  final int code;
}

Never _fakeExit(int code) => throw _Exited(code);

// Vommet issue 883: on Windows the runner closes the window instead of
// dart:io's exit(), which crashed with an access violation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = BasicMessageChannel<String?>(
    "test/vommet_session",
    StringCodec(),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final sent = <String?>[];

  void runnerReplies(String? reply) {
    messenger.setMockDecodedMessageHandler<String?>(channel, (message) async {
      sent.add(message);
      return reply;
    });
  }

  setUp(sent.clear);
  tearDown(
      () => messenger.setMockDecodedMessageHandler<String?>(channel, null));

  Future<int?> run({required bool isWindows}) async {
    try {
      await exitApp(
        isWindows: isWindows,
        channel: channel,
        fallbackAfter: const Duration(milliseconds: 10),
        exitProcess: _fakeExit,
      );
    } on _Exited catch (e) {
      return e.code;
    }
  }

  test("asks the Windows runner to quit before exiting", () async {
    runnerReplies("ok");
    expect(await run(isWindows: true), 0);
    expect(sent, ["quit"]);
  });

  test("exits when the runner doesn't take the request", () async {
    runnerReplies(null);
    expect(await run(isWindows: true), 0);
    expect(sent, ["quit"]);
  });

  test("other platforms exit without asking the runner", () async {
    runnerReplies("ok");
    expect(await run(isWindows: false), 0);
    expect(sent, isEmpty);
  });
}
