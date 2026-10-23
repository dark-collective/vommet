import 'package:commet/ui/atoms/release_notice_bar.dart';
import 'package:commet/utils/release_notice.dart';
import 'package:commet/utils/release_update.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The bar sits in MaterialApp.builder, above the navigator (and so above
  // its Overlay). Hovering its close button used to show a tooltip there,
  // which threw and turned the whole app white.
  testWidgets("hovering the bar's close button doesn't throw", (tester) async {
    ReleaseNotice.newer.value = "testing-2099-01-01";
    addTearDown(() => ReleaseNotice.newer.value = null);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: ReleaseNoticeBar(child: child),
      ),
      home: const Scaffold(body: Text("app")),
    ));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.close)));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text("app"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text("app"), findsOneWidget);
  });

  Future<void> pumpBar(WidgetTester tester) async {
    ReleaseNotice.newer.value = "testing-2099-01-01";
    addTearDown(() => ReleaseNotice.newer.value = null);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: ReleaseNoticeBar(child: child),
      ),
      home: const Scaffold(body: Text("app")),
    ));
  }

  // Vommet issue 593: a package manager owns Nix and Guix installs.
  testWidgets("a Guix install gets its update command", (tester) async {
    ReleaseUpdate.kindForTest = InstallKind.guix;
    addTearDown(() => ReleaseUpdate.kindForTest = null);
    await pumpBar(tester);
    expect(find.text("guix pull && guix upgrade vommet"), findsOneWidget);
    expect(find.text("Copy"), findsOneWidget);
  });

  testWidgets("a failed check says nothing was installed", (tester) async {
    ReleaseUpdate.state.value =
        const UpdateState(UpdatePhase.failed, error: UpdateError.verify);
    addTearDown(() => ReleaseUpdate.state.value = UpdateState.idle);
    await pumpBar(tester);
    expect(
        find.text(
            "The download didn't match its signature. Nothing was installed."),
        findsOneWidget);
    expect(find.text("Download page"), findsOneWidget);
  });

  testWidgets("downloading shows progress and Cancel", (tester) async {
    ReleaseUpdate.state.value = const UpdateState(UpdatePhase.downloading,
        received: 64 * 1024 * 1024, total: 198 * 1024 * 1024);
    addTearDown(() => ReleaseUpdate.state.value = UpdateState.idle);
    await pumpBar(tester);
    expect(find.text("Downloading testing-2099-01-01 · 64 of 198 MB"),
        findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text("Cancel"), findsOneWidget);
  });
}
