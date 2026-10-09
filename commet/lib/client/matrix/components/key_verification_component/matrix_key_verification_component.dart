import 'package:commet/client/components/component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/matrix/authentication/matrix_uia_request.dart';
import 'package:commet/ui/pages/matrix/verification/matrix_verification_page.dart';

import 'package:matrix/matrix.dart' as matrix;

class MatrixKeyVerificationComponent
    implements Component<MatrixClient>, NeedsPostLoginInit {
  /// Vommet: UIA requests that already have a dialog open.
  static final Set<matrix.UiaRequest> _openUia = {};

  @override
  MatrixClient client;

  MatrixKeyVerificationComponent(this.client);

  @override
  void postLoginInit() {
    Log.i("Registering key verification listeners");
    client.matrixClient.onKeyVerificationRequest.stream.listen((event) {
      AdaptiveDialog.show(
        navigator.currentContext!,
        builder: (_) => MatrixVerificationPage(request: event),
        title: "Verification Request",
      );
    });

    client.matrixClient.onUiaRequest.stream.listen((event) async {
      // Vommet: one dialog per request (the SDK reports it again on every
      // step, e.g. after a wrong password).
      if (event.state != matrix.UiaRequestState.waitForUser ||
          _openUia.contains(event)) {
        return;
      }
      _openUia.add(event);
      try {
        await AdaptiveDialog.show(
          navigator.currentContext!,
          builder: (_) => MatrixUIARequest(event, client),
          title: "Authentication Request",
        );
      } finally {
        _openUia.remove(event);
      }
      // Vommet: closing the dialog without finishing cancels the request,
      // so whatever asked for it (e.g. secure messaging setup) fails with an
      // error instead of waiting forever. Closed mid-request: cancel when it
      // next needs the user.
      if (event.state == matrix.UiaRequestState.waitForUser) {
        event.cancel();
      } else if (event.state == matrix.UiaRequestState.loading) {
        final previous = event.onUpdate;
        event.onUpdate = (state) {
          previous?.call(state);
          if (state == matrix.UiaRequestState.waitForUser) event.cancel();
        };
      }
    });
  }
}
