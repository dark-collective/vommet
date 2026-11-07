import 'package:commet/utils/relistenable_stream_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 485: unblocking a DM partner (or an unban) swaps the footer
// back to the composer, whose new state listens to the chat's streams again.
void main() {
  test("can be listened to again after the listener cancels", () async {
    final controller = RelistenableStreamController<String>();
    final first = <String>[];
    final sub = controller.stream.listen(first.add);
    controller.add("a");
    await pumpEventQueue();
    await sub.cancel();

    final second = <String>[];
    controller.stream.listen(second.add);
    controller.add("b");
    await pumpEventQueue();

    expect(first, ["a"]);
    expect(second, ["b"]);
  });

  test("holds events added while nobody listens for the next listener",
      () async {
    final controller = RelistenableStreamController<String>();
    controller.add("before");
    final sub = controller.stream.listen((_) {});
    await sub.cancel();
    controller.add("between");

    final received = <String>[];
    controller.stream.listen(received.add);
    await pumpEventQueue();

    expect(received, ["between"]);
  });

  test("delivers events held before the first listener", () async {
    final controller = RelistenableStreamController<int>();
    controller.add(1);
    controller.add(2);

    final received = <int>[];
    controller.stream.listen(received.add);
    controller.add(3);
    await pumpEventQueue();

    expect(received, [1, 2, 3]);
  });

  test("calls onListen and onCancel for each listener", () async {
    var listens = 0;
    var cancels = 0;
    final controller = RelistenableStreamController<void>(
        onListen: () => listens++, onCancel: () => cancels++);

    for (var i = 0; i < 2; i++) {
      final sub = controller.stream.listen((_) {});
      await sub.cancel();
    }

    expect(listens, 2);
    expect(cancels, 2);
  });
}
