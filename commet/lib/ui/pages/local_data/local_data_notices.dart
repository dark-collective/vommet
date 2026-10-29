// Vommet: the home notices of local data encryption (phase 6): the one-time
// offer to existing users, the key-kept-in-a-file notice, and a conversion
// that needs free space. In the Discord layout they show in the Home
// Alerts panel, in the Telegram and Custom mix layouts above the chat list.
import 'dart:async';

import 'package:commet/client/alert.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/security/local_data_keys.dart';
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

    // Decisions 12 and 13: people who never answered are asked once, here
    // (no splash); a new install answers on the first-run page.
    if (!LocalDataKeys.chosen &&
        !LocalDataKeys.encrypt &&
        LocalDataKeys.registeredAccounts.isNotEmpty) {
      late final Alert offer;
      offer = Alert(AlertType.info,
          icon: Icons.info_outline,
          titleGetter: () => localDataOfferTitle,
          messageGetter: () => localDataOfferBody,
          actionLabel: () => localDataOfferAction,
          action: openLocalDataSettings,
          onDismiss: () {
            // Dismissed for good: the answer is "Not now".
            unawaited(LocalDataKeys.choose(false, source: "notice"));
            alerts.clearAlert(offer);
          });
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
