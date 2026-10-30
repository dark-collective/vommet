// Vommet: the home notices of local data encryption (phase 6): the offer
// to existing users (Encrypt recommended since 10-30), the key-kept-in-a-file notice, and a conversion
// that needs free space. In the Discord layout they show in the Home
// Alerts panel, in the Telegram and Custom mix layouts above the chat list.
import 'dart:async';

import 'package:commet/client/alert.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/security/local_data_keys.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:commet/security/local_data_strings.dart';
import 'package:commet/ui/pages/settings/categories/app/local_data_panel.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class LocalDataNotices {
  /// Adds the notices due this start (UI engine, after the accounts load).
  static void add(ClientManager manager) {
    if (!LocalDataKeys.supported) return;
    final alerts = manager.alertManager;
    _rememberLabels(manager);

    final summary = LocalDataKeys.lastMigration;
    final bytes = summary?.bytesToFree;
    if (summary != null && bytes != null) {
      alerts.addAlert(Alert(AlertType.warning,
          titleGetter: () => summary.decrypting
              ? localDataNoSpaceDecryptTitle
              : localDataNoSpaceTitle,
          messageGetter: () {
            final size = TextUtils.readableFileSize(bytes);
            final name = localDataAccountName(summary.noSpaceAccount);
            return summary.decrypting
                ? localDataNoSpaceDecrypt(size, name)
                : localDataNoSpaceEncrypt(size, name);
          },
          action: openLocalDataSettings));
    }

    // Decisions 12 and 13, on by default since 10-30: people who never
    // answered are asked here (no splash; a new install answers on the
    // first-run page), Encrypt recommended. A "Not now" given to the
    // opt-in question on the first-run page or this notice is asked once
    // more; one from the settings switch never is (offerDue).
    if (LocalDataKeys.offerDue && LocalDataKeys.registeredAccounts.isNotEmpty) {
      late final Alert offer;
      void notNow() {
        // Answered for good (this generation): "Not now".
        unawaited(
            LocalDataKeys.choose(false, source: LocalDataSetting.sourceNotice));
        alerts.clearAlert(offer);
      }

      offer = Alert(AlertType.info,
          icon: Icons.lock_outline,
          titleGetter: () => localDataOfferEncryptTitle,
          messageGetter: () => localDataOfferEncryptBody,
          actionLabel: () => localDataOfferEncryptAction,
          actionIsPrimary: true,
          action: (context) =>
              _encrypt(context, () => alerts.clearAlert(offer)),
          secondaryActionLabel: () => localDataOfferNotNow,
          secondaryAction: (_) => notNow(),
          onDismiss: notNow);
      alerts.addAlert(offer);
    }

    if (LocalDataKeys.keyFileNoticeDue) {
      late final Alert notice;
      void done() {
        unawaited(LocalDataKeys.acknowledgeKeyFileNotice());
        alerts.clearAlert(notice);
      }

      notice = Alert(AlertType.info,
          icon: Icons.key_outlined,
          titleGetter: () => localDataKeyFileNoticeTitle,
          messageGetter: () => localDataKeyFileNoticeBody,
          actionLabel: () => localDataLearnMore,
          action: (context) => _learnMore(context, done),
          onDismiss: done);
      alerts.addAlert(notice);
    }
  }

  /// Encrypt on the offer: on from the next start. When the setting
  /// can't be saved, the settings say why (the offer stays).
  static Future<void> _encrypt(
      BuildContext context, void Function() answered) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final saved =
        await LocalDataKeys.choose(true, source: LocalDataSetting.sourceNotice);
    if (!saved) {
      if (context.mounted) openLocalDataSettings(context);
      return;
    }
    answered();
    messenger?.showSnackBar(SnackBar(content: Text(localDataOfferEncryptDone)));
  }

  static Future<void> _learnMore(
      BuildContext context, void Function() done) async {
    final open = await localDataDialog<bool>(context,
        title: localDataKeyFileDialogTitle,
        paragraphs: [
          localDataKeyFileDialogKeyring,
          localDataKeyFileDialogFile,
          localDataKeyFileDialogBetter,
        ],
        buttons: [
          (localDataOpenSettings, true, tiamat.ButtonType.secondary),
          (localDataGotIt, false, tiamat.ButtonType.primary),
        ]);
    if (open == null) return;
    done();
    if (open && context.mounted) openLocalDataSettings(context);
  }

  /// The damaged-data screen names the account it is about (only kept
  /// while encryption is on).
  static void _rememberLabels(ClientManager manager) {
    final labels = <String, ({String? name, String? userId})>{};
    for (final client in manager.clients) {
      try {
        final self = client.self;
        labels[client.identifier] = (
          name: self?.displayName,
          userId: self?.identifier,
        );
      } catch (_) {}
    }
    unawaited(LocalDataKeys.rememberAccountLabels(labels));
  }
}
