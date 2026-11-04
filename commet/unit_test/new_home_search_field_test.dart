import 'package:commet/client/space.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 1073: the Home search field is single-line, 40px tall like
// the Deep Search bar, and Enter opens the highlighted result.
void main() {
  Widget host(
          {SearchScope<Space>? scope,
          bool searching = false,
          VoidCallback? onSubmitted}) =>
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: NewHomeSearchField(
                controller: TextEditingController(),
                focusNode: FocusNode(),
                scope: scope,
                searching: searching,
                onChanged: (_) {},
                onSubmitted: onSubmitted ?? () {},
                onClearScope: () {},
                onClear: () {},
              ),
            ),
          ),
        ),
      );

  final field = find.byKey(const ValueKey("NewHomeSearch"));

  testWidgets("single-line and 40px tall", (tester) async {
    await tester.pumpWidget(host());
    expect(tester.widget<TextField>(field).maxLines, 1);
    expect(tester.getSize(field).height, 40);
  });

  testWidgets("stays 40px with the clear button and a scope token",
      (tester) async {
    await tester
        .pumpWidget(host(scope: const SearchScope.kind(true), searching: true));
    expect(tester.getSize(field).height, 40);
    expect(find.byKey(const ValueKey("NewHomeSearchToken")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("icon inset 14, text 10 after the icon", (tester) async {
    await tester.pumpWidget(host());
    final left = tester.getTopLeft(field).dx;
    final icon = tester.getRect(find.byIcon(Icons.search_rounded));
    expect(icon.left - left, 14);
    expect(icon.width, 20);
    final text = tester.getTopLeft(find.byType(EditableText)).dx;
    expect(text - icon.right, 10);
  });

  testWidgets("Enter calls onSubmitted", (tester) async {
    var submitted = 0;
    await tester.pumpWidget(host(onSubmitted: () => submitted++));
    await tester.tap(field);
    await tester.enterText(field, "abc");
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(submitted, 1);
  });
}
