import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/ui/pages/secure_setup/change_password.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_flow.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

// Stand-ins: the dialogs only touch the client when a button is pressed.
class _MatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements matrix.Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The secure setup's dialogs lay out without errors on a phone and on a
/// desktop (AlertDialog measures its children's natural width, which
/// full-width buttons don't have: that threw on desktop).
void main() {
  final dialogs = <String, Widget Function()>{
    "skip warning 1": () => skipDialogsForTest()[0],
    "skip warning 2": () => skipDialogsForTest()[1],
    "check-in": () => checkInDialogForTest(_MatrixClient()),
    "change password": () => changePasswordDialogForTest(_Client()),
  };
  for (final size in const [Size(360, 740), Size(1280, 800)]) {
    for (final entry in dialogs.entries) {
      testWidgets("${entry.key} at ${size.width.toInt()} wide", (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
            MaterialApp(home: Scaffold(body: Center(child: entry.value()))));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsOneWidget);
      });
    }
  }
}
