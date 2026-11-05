import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 489: a dependent that throws when redacted mode changes must
// not replace the whole app (everything under the scope) with the grey
// error widget.
void main() {
  const on = RedactionSettings(names: NameRedaction.hide);
  const off = RedactionSettings();

  Widget app(RedactionSettings settings) => MaterialApp(
        home: RedactionScope.withSettings(
          settings: settings,
          child: const Column(children: [
            _Broken(),
            _NameShown(),
          ]),
        ),
      );

  testWidgets('a failing dependent is reported and the rest updates',
      (tester) async {
    await tester.pumpWidget(app(off));
    expect(find.text("Ada"), findsOneWidget);

    _BrokenElement.armed = true;
    addTearDown(() => _BrokenElement.armed = false);
    await tester.pumpWidget(app(on));

    expect(tester.takeException(), isA<StateError>());
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text("Ada"), findsNothing);
    expect(find.text(RedactionPolicy(on).name("Ada", "@ada:example.org")),
        findsOneWidget);
  });
}

class _NameShown extends StatelessWidget {
  const _NameShown();

  @override
  Widget build(BuildContext context) =>
      Text(RedactionScope.of(context).name("Ada", "@ada:example.org"));
}

/// Depends on the scope and throws when told it changed, like an element
/// whose LayoutBuilder ancestor was already unmounted.
class _Broken extends StatelessWidget {
  const _Broken();

  @override
  StatelessElement createElement() => _BrokenElement(this);

  @override
  Widget build(BuildContext context) {
    RedactionScope.of(context);
    return const SizedBox();
  }
}

class _BrokenElement extends StatelessElement {
  _BrokenElement(super.widget);

  static bool armed = false;

  @override
  void didChangeDependencies() {
    if (armed) throw StateError("render object already gone");
    super.didChangeDependencies();
  }
}
