// Vommet issue 1144: fake-clock proof of the actual preview request budget.
import 'dart:async';

import 'package:commet/ui/organisms/new_home/followed_threads_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'deadline and cancellation keep occupied slots until requests settle',
      (tester) async {
    final pending = [Completer<List<int>>(), Completer<List<int>>()];
    var calls = 0;
    FollowedThreadPreviewResult<int>? expired;
    unawaited(FollowedThreadPreview.load<int, int>(
      rooms: [1, 2, 3],
      page: (_) => pending[calls++].future,
      extra: (_) => [],
    ).then((result) => expired = result));
    await tester.pump();
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 8));
    expect(expired!.failures, 1);
    expect(expired!.rows, isEmpty);
    final canceled = Completer<void>();
    FollowedThreadPreviewResult<int>? next;
    unawaited(FollowedThreadPreview.load<int, int>(
      rooms: [4],
      page: (_) async {
        calls++;
        return [4];
      },
      extra: (_) => [],
      canceled: canceled.future,
    ).then((result) => next = result));
    await tester.pump();
    expect(calls, 2);
    canceled.complete();
    await tester.pump();
    expect(next!.rows, isEmpty);
    final fresh = FollowedThreadPreview.load<int, int>(
      rooms: [5],
      page: (_) async {
        calls++;
        return [5];
      },
      extra: (_) => [],
    );
    await tester.pump();
    expect(calls, 2);
    pending.first.complete([1]);
    await tester.pump();
    expect((await fresh).rows, [5]);
    pending.last.complete([2]);
    await tester.pump();
    expect(calls, 3);
    expect(expired!.rows, isEmpty);
    expect(next!.rows, isEmpty);
  });

  testWidgets(
      'discovery caps rooms and extras, isolates errors, and never retries',
      (tester) async {
    var pages = 0;
    var extras = 0;
    FollowedThreadPreviewResult<int>? result;
    unawaited(FollowedThreadPreview.load<int, int>(
      rooms: List.generate(100, (i) => i),
      page: (_) async {
        pages++;
        throw StateError('offline');
      },
      extra: (_) => List.generate(
          100,
          (i) => () async {
                extras++;
                return i;
              }),
    ).then((value) => result = value));
    await tester.pump();
    expect(pages, 6);
    expect(extras, 6);
    expect(result!.failures, 6);
    expect(result!.completed, 6);
    expect(result!.rows, [0, 1, 2, 3, 4, 5]);
    await tester.pump(const Duration(minutes: 2));
    expect(pages, 6);
    expect(extras, 6);
  });
}
