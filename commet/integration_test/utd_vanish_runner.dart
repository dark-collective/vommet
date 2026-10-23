// Vommet: every "Retry Decrypt" / history-gap variant of
// matrix/utd_vanish_test.dart (.vommet/it/run.sh
// integration_test/utd_vanish_runner.dart; UTD_ONLY / UTD_REPEAT select).
// The per-push suite (vommet_runner.dart) runs only the "report" variant; the
// nightly integration-synapse workflow runs the federated ones against
// Synapse. Needs testing (#102, #16, #32), not the topic branch alone.

import 'package:commet/client/matrix/components/history_gaps/matrix_history_gap_component.dart';
import 'package:commet/generated/l10n.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'matrix/utd_vanish_test.dart' as utd_vanish_test;

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await T.load(const Locale("en"));
  await preferences.init();

  utd_vanish_test.gapRepairHooks = utd_vanish_test.GapRepairHooks(
    setAutoRepair: (on) => MatrixHistoryGapComponent.autoCheck = on,
    isReloading: (room) =>
        room.getComponent<MatrixHistoryGapComponent>()?.isReloading ?? false,
  );
  utd_vanish_test.main();
}
