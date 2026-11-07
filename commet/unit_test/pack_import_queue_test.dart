import 'dart:async';

import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/background_tasks/pack_import_queue_task.dart';
import 'package:test/test.dart';

void main() {
  PackImportQueueTask queue(List<PackImportJob> jobs) =>
      PackImportQueueTask(jobs, removeAfter: Duration.zero);

  test("packs import one at a time, in order", () async {
    final log = <String>[];
    var running = 0;
    Future<void> Function(PackImportProgress) work(String name) =>
        (progress) async {
          running++;
          expect(running, 1, reason: "only one pack at a time");
          log.add("start $name");
          progress(0.5, 1);
          await Future.delayed(const Duration(milliseconds: 5));
          log.add("end $name");
          running--;
        };

    final task = queue([
      PackImportJob(name: "Grumpy Toads", imageCount: 2, run: work("a")),
      PackImportJob(name: "Pixel Foxes", imageCount: 2, run: work("b")),
    ]);
    await task.start();

    expect(log, ["start a", "end a", "start b", "end b"]);
    expect(task.doneCount, 2);
    expect(task.status, BackgroundTaskStatus.completed);
    expect(task.progress, 1);
  });

  test("one failing pack doesn't stop the rest", () async {
    final task = queue([
      PackImportJob(
          name: "Office Cats",
          imageCount: 1,
          run: (_) async => throw Exception("pack not found")),
      PackImportJob(name: "Space Otters", imageCount: 1, run: (_) async {}),
    ]);
    await task.start();

    expect(task.jobs[0].state, PackImportJobState.failed);
    expect(task.jobs[0].error, contains("pack not found"));
    expect(task.jobs[1].state, PackImportJobState.done);
    expect(task.status, BackgroundTaskStatus.completed);
  });

  test("cancel stops the packs that haven't started", () async {
    final release = Completer<void>();
    late PackImportQueueTask task;
    var laterRan = false;
    task = queue([
      PackImportJob(
          name: "Mochi Bunnies",
          imageCount: 1,
          run: (_) async {
            task.cancel();
            await release.future;
          }),
      PackImportJob(
          name: "Sleepy Toads",
          imageCount: 1,
          run: (_) async => laterRan = true),
      PackImportJob(
          name: "Disco Toads",
          imageCount: 1,
          run: (_) async => laterRan = true),
    ]);
    final done = task.start();
    await Future.delayed(Duration.zero);
    release.complete();
    await done;

    expect(task.jobs[0].state, PackImportJobState.done,
        reason: "the running pack finishes");
    expect(task.jobs[1].state, PackImportJobState.cancelled);
    expect(task.jobs[2].state, PackImportJobState.cancelled);
    expect(laterRan, isFalse);
  });

  test("a link that failed to load is never run", () async {
    var ran = false;
    final task = queue([
      PackImportJob(
          name: "NoSuchPack",
          imageCount: 0,
          error: "pack not found",
          run: (_) async => ran = true),
    ]);
    await task.start();
    expect(ran, isFalse);
    expect(task.jobs.single.state, PackImportJobState.failed);
    expect(task.status, BackgroundTaskStatus.failed);
  });

  test("progress is reported per pack and overall", () async {
    late PackImportQueueTask task;
    double? midway;
    task = queue([
      PackImportJob(
          name: "Grumpy Toads",
          imageCount: 4,
          run: (progress) async {
            progress(0.5, 2);
            midway = task.progress;
            expect(task.current!.imagesDone, 2);
          }),
      PackImportJob(name: "Pixel Foxes", imageCount: 4, run: (_) async {}),
    ]);
    await task.start();
    expect(midway, 0.25);
    expect(task.progress, 1);
  });
}
