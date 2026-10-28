import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/atoms/shimmer_loading.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_url_previews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

// Vommet issue 377: when a link preview couldn't be fetched, the timeline kept
// its loading placeholder up until the room was reopened. Loading must end
// with no card when the lookup gives nothing back or fails.

class _FakeTimeline extends Timeline {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEvent implements TimelineEvent<Client> {
  _FakeEvent(this.status);

  @override
  final TimelineEventStatus status;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeComponent implements UrlPreviewComponent<Client> {
  _FakeComponent(this.lookup);

  final Future<UrlPreviewData?> Function() lookup;
  int calls = 0;

  @override
  Future<UrlPreviewData?> getPreview(Timeline timeline, TimelineEvent event) {
    calls += 1;
    return lookup();
  }

  @override
  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event) =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpPreview(WidgetTester tester, _FakeComponent component,
    {TimelineEventStatus status = TimelineEventStatus.synced}) async {
  final timeline = _FakeTimeline()..events = [_FakeEvent(status)];
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [ThemeSettings()]),
    home: Scaffold(
      body: TimelineEventViewUrlPreviews(
          initialIndex: 0, timeline: timeline, component: component),
    ),
  ));
}

void main() {
  testWidgets("placeholder shows while the preview loads", (tester) async {
    final pending = Completer<UrlPreviewData?>();
    final component = _FakeComponent(() => pending.future);
    await _pumpPreview(tester, component);

    expect(find.byType(Shimmer), findsOneWidget);

    pending.complete(
        UrlPreviewData(Uri.parse("https://example.com"), title: "Example"));
    await tester.pump();
    await tester.pump();

    expect(find.byType(Shimmer), findsNothing);
    expect(find.text("Example"), findsOneWidget);
  });

  testWidgets("no preview from the server removes the placeholder",
      (tester) async {
    final component = _FakeComponent(() async => null);
    await _pumpPreview(tester, component);
    await tester.pump();
    await tester.pump();

    expect(component.calls, 1);
    expect(find.byType(Shimmer), findsNothing);
  });

  testWidgets("the invalid marker removes the placeholder", (tester) async {
    final component =
        _FakeComponent(() async => UrlPreviewComponent.invalidPreviewData);
    await _pumpPreview(tester, component);
    await tester.pump();
    await tester.pump();

    expect(find.byType(Shimmer), findsNothing);
    expect(
        find.text(UrlPreviewComponent.invalidPreviewData.title!), findsNothing);
  });

  testWidgets("a failed lookup removes the placeholder", (tester) async {
    final component =
        _FakeComponent(() => Future.error(StateError("preview_url failed")));
    await _pumpPreview(tester, component);
    await tester.pump();
    await tester.pump();

    expect(find.byType(Shimmer), findsNothing);
  });

  testWidgets("an unsent message keeps the placeholder and doesn't fetch",
      (tester) async {
    final component = _FakeComponent(() async => null);
    await _pumpPreview(tester, component, status: TimelineEventStatus.sending);
    await tester.pump();

    expect(component.calls, 0);
    expect(find.byType(Shimmer), findsOneWidget);
  });
}
