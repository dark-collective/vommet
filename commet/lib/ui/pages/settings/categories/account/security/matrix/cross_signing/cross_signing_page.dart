import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_view.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/encryption.dart';

enum MatrixCrossSigningMode {
  standard,
  enableBackup,
  restoreBackup,
  resetCrossSigning,
  crossSigningOnly
}

class MatrixCrossSigningPage extends StatefulWidget {
  const MatrixCrossSigningPage(
      {required this.client,
      this.mode = MatrixCrossSigningMode.standard,
      super.key,
      this.onComplete});
  final MatrixClient client;
  final MatrixCrossSigningMode mode;
  final Function()? onComplete;

  @override
  State<MatrixCrossSigningPage> createState() => MatrixCrossSigningPageState();
}

class MatrixCrossSigningPageState extends State<MatrixCrossSigningPage> {
  BootstrapState state = BootstrapState.loading;
  Bootstrap? bootstrapper;
  @override
  void initState() {
    var mx = widget.client.getMatrixClient();
    bootstrapper = mx.encryption?.bootstrap(onUpdate: onBootstrapperUdate);
    onBootstrapperUdate(bootstrapper!);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MatrixCrossSigningView(
      state,
      recoveryKey: bootstrapper?.newSsssKey?.recoveryKey,
      onSetNewSsss: (passphrase) {
        bootstrapper?.newSsss(passphrase);
      },
      onAskSetupCrossSigning: () async {
        await bootstrapper?.askSetupCrossSigning(
          setupMasterKey: true,
          setupSelfSigningKey: true,
          setupUserSigningKey: true,
        );
      },
      onAskSetupOnlineBackup: (enable) {
        bootstrapper?.askSetupOnlineKeyBackup(enable);
      },
      useExistingKeys: (use) {
        bootstrapper?.useExistingSsss(use);
      },
      wipeSsss: (wipe) {
        bootstrapper?.wipeSsss(wipe);
        if (!wipe) {
          bootstrapper?.useExistingSsss(true);
          bootstrapper?.openExistingSsss();
        }
      },
      wipeExistingBackup: (wipe) {
        bootstrapper?.wipeOnlineKeyBackup(wipe);
      },
      openExistingSsss: (key) async {
        await bootstrapper?.newSsssKey!.unlock(keyOrPassphrase: key);
        await bootstrapper?.openExistingSsss();

        // Vommet: "Restore backup" used to stop here: it unlocked the
        // recovery key and cached the backup key, but never downloaded the
        // backup, so old messages stayed undecryptable (#32). Each key
        // loaded also re-decrypts open timelines (onSessionKeyReceived).
        if (widget.mode == MatrixCrossSigningMode.restoreBackup) {
          unawaited(downloadKeyBackup());
        }

        if (bootstrapper!.encryption.crossSigning.enabled) {
          await bootstrapper?.client.encryption!.crossSigning
              .selfSign(keyOrPassphrase: key);
        }
      },
      wipeCrossSigning: (wipe) {
        bootstrapper?.wipeCrossSigning(wipe);
      },
    );
  }

  Future<void> downloadKeyBackup() async {
    final keyManager = widget.client.getMatrixClient().encryption?.keyManager;
    if (keyManager == null) return;
    final clock = Stopwatch()..start();
    try {
      await keyManager.loadAllKeys();
      Log.i("Key backup downloaded in ${clock.elapsedMilliseconds} ms");
    } catch (e, s) {
      Log.onError(e, s, content: "Downloading the key backup failed");
    }
  }

  void onBootstrapperUdate(Bootstrap bootstrapper) async {
    if (bootstrapper.state == BootstrapState.done) {
      widget.onComplete?.call();
    }

    if (widget.mode == MatrixCrossSigningMode.enableBackup ||
        widget.mode == MatrixCrossSigningMode.restoreBackup) {
      switch (bootstrapper.state) {
        case BootstrapState.askUseExistingSsss:
          bootstrapper.useExistingSsss(true);
          break;
        case BootstrapState.askWipeSsss:
          bootstrapper.wipeSsss(false);
          break;
        case BootstrapState.askWipeCrossSigning:
          bootstrapper.wipeCrossSigning(false);
          break;
        case BootstrapState.askWipeOnlineKeyBackup:
          bootstrapper.wipeOnlineKeyBackup(false);
          break;
        default:
          break;
      }
    }

    setState(() {
      state = bootstrapper.state;
    });
  }
}
