// Vommet's integration suite (.vommet/it/run.sh runs this by default).
//
// Starts with the upstream tests that pass against the CI homeserver; the
// rest of upstream's runner.dart (create space, key verification, multi
// account, change space name) targets UI that has since changed and is being
// rewritten. Add fork scenarios here as they land.

import 'package:commet/generated/l10n.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'matrix/launch_test.dart' as launch_test;
import 'matrix/login_test.dart' as login_test;
import 'matrix/room_directory_test.dart' as room_directory_test;
import 'matrix/media_mosaic_test.dart' as media_mosaic_test;
import 'matrix/threads_block_test.dart' as threads_block_test;
import 'matrix/room_banner_test.dart' as room_banner_test;
import 'matrix/unread_dot_test.dart' as unread_dot_test;
import 'matrix/utd_vanish_test.dart' as utd_vanish_test;
import 'matrix/dm_order_test.dart' as dm_order_test;
import 'matrix/encryption_trust_test.dart' as encryption_trust_test;
import 'matrix/cross_signing_test.dart' as cross_signing_test;
import 'matrix/notify_after_sign_in_test.dart' as notify_after_sign_in_test;
import 'matrix/sync_gap_test.dart' as sync_gap_test;
import 'stream_popout_test.dart' as stream_popout_test;
import 'matrix/local_data_keys_test.dart' as local_data_keys_test;
import 'matrix/local_data_migration_test.dart' as local_data_migration_test;

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await T.load(const Locale("en"));
  await preferences.init();

  launch_test.main();
  login_test.main();
  room_directory_test.main();
  media_mosaic_test.main();
  // Thread list, read state per thread, blocking.
  threads_block_test.main();
  room_banner_test.main();
  // An accepted DM invite is drawn first in Direct Messages.
  dm_order_test.main();
  // Encryption markers, DM trust warnings, recovery-key paste guard.
  encryption_trust_test.main();
  // Encrypted messages decrypt and stay after Retry Decrypt (#16, #102);
  // only the deterministic variant here, the rest run nightly.
  utd_vanish_test.registerVariants(["report:"]);
  // Unread dot on the room list, Tuwunel (Synapse + sliding sync: nightly).
  unread_dot_test
      .registerVariants(["desktop: plain room", "phone: plain room"]);
  // Confirming a freshly signed-in device: the fast tier (approve both
  // ways, recovery key, missing own device list). The rest runs nightly.
  cross_signing_test.registerFast();
  // Desktop notifications right after a fresh sign-in, no restart.
  notify_after_sign_in_test.main();
  // Messages sliding sync skipped while the app was away are paged back.
  sync_gap_test.main();
  // A watched stream in its own window (second Flutter view), Linux.
  stream_popout_test.main();
  // An install from before local data encryption: its plaintext message
  // store is encrypted at start-up and the account comes back intact.
  local_data_migration_test.main();
  // The build has the cipher; the vault keeps its key in the CI keyring,
  // reached over the encrypted Secret Service session.
  local_data_keys_test.main();
}
