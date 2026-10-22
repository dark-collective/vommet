import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet issue 28: a long (sub)space name ran underneath the expand/collapse
// chevron instead of being truncated.
Future<void> pumpExpander(WidgetTester tester, String name,
    {Function? onNameTapped}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          child: tiamat.TextButtonExpander(name,
              initiallyExpanded: true,
              onNameTapped: onNameTapped,
              children: const [SizedBox()]),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('long name is truncated and leaves room for the chevron',
      (tester) async {
    const name = 'A very long subspace name that will never fit in the sidebar';
    await pumpExpander(tester, name);

    expect(tester.takeException(), isNull);

    final chevron = tester.getRect(find.byIcon(Icons.expand_more));
    final text = tester.getRect(find.text(name));
    expect(text.right, lessThanOrEqualTo(chevron.left));
  });

  testWidgets('short name keeps a tap area the width of the name',
      (tester) async {
    const name = 'Lobby';
    await pumpExpander(tester, name, onNameTapped: () {});

    expect(tester.takeException(), isNull);

    // The name's own InkWell, not the ExpansionTile's whole-row one.
    final ink = tester.getRect(find
        .ancestor(of: find.text(name), matching: find.byType(InkWell))
        .first);
    final text = tester.getRect(find.text(name));
    expect(ink.width, closeTo(text.width, 0.5));
  });
}
