// Vommet: Settings › Privacy › Data on this device (local data encryption,
// phase 6): the opt-in switch, what is encrypted, and where the key is
// kept.
import 'dart:async';
import 'dart:io';

import 'package:commet/config/experiment_registry.dart';
import 'package:commet/main.dart';
import 'package:commet/security/local_data_keys.dart';
import 'package:commet/security/local_data_strings.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/local_data/local_data_startup_screens.dart'
    show localDataPlaceName;
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The panel's id for settings search and [SettingsHighlight].
const localDataSettingId = "local_data_encryption";

/// Opens App Settings › Privacy (not the account's Privacy tab) at Data on
/// this device.
void openLocalDataSettings(BuildContext context) =>
    SettingsNavigation.openAppPrivacy(context, highlight: localDataSettingId);

/// An account's name for the local data texts.
String localDataAccountName(String? account) {
  if (account == null) return localDataThisAccount;
  for (final client in clientManager?.clients ?? const []) {
    if (client.identifier != account) continue;
    try {
      final self = client.self;
      if (self != null) {
        final name = self.displayName;
        return name.isNotEmpty ? name : self.identifier;
      }
    } catch (_) {}
  }
  return localDataThisAccount;
}

/// A dialog with [paragraphs] and buttons; returns the picked button's
/// value (null: dismissed).
Future<T?> localDataDialog<T>(BuildContext context,
    {required String title,
    required List<String> paragraphs,
    required List<(String, T?, tiamat.ButtonType)> buttons}) {
  return AdaptiveDialog.show<T>(context, title: title, builder: (context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: tiamat.Text.label(p),
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, value, type) in buttons)
                  tiamat.Button(
                      text: label,
                      type: type,
                      onTap: () => Navigator.of(context).pop(value)),
              ],
            ),
          ],
        ),
      ),
    );
  });
}

class LocalDataPanel extends StatefulWidget {
  const LocalDataPanel({super.key});

  @override
  State<LocalDataPanel> createState() => _LocalDataPanelState();
}

enum _ConfirmOn { restart, nextStart }

class _LocalDataPanelState extends State<LocalDataPanel> {
  LocalDataPanelStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await LocalDataKeys.panelStatus();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _switch(bool on) async {
    if (on) {
      final answer = await localDataDialog<_ConfirmOn>(context,
          title: localDataConfirmOnTitle,
          paragraphs: [
            localDataConfirmOnBody
          ],
          buttons: [
            if (ExperimentRegistry.canRelaunch)
              (
                localDataRestartNow,
                _ConfirmOn.restart,
                tiamat.ButtonType.secondary
              ),
            (localDataCancel, null, tiamat.ButtonType.secondary),
            (
              localDataEncryptNextStart,
              _ConfirmOn.nextStart,
              tiamat.ButtonType.primary
            ),
          ]);
      if (answer == null) return;
      if (!await _choose(true)) return;
      if (answer == _ConfirmOn.restart) {
        await ExperimentRegistry.restart();
        return;
      }
    } else {
      final ok = await localDataDialog<bool>(context,
          title: localDataConfirmOffTitle,
          paragraphs: [
            localDataConfirmOffBody
          ],
          buttons: [
            (localDataCancel, false, tiamat.ButtonType.secondary),
            (localDataDecryptNextStart, true, tiamat.ButtonType.primary),
          ]);
      if (ok != true) return;
      if (!await _choose(false)) return;
    }
    await _load();
  }

  /// Saves the setting; when it couldn't be saved, says so (nothing
  /// changed).
  Future<bool> _choose(bool encrypt) async {
    if (await LocalDataKeys.choose(encrypt, source: "settings")) return true;
    if (mounted) {
      await localDataDialog<bool>(context,
          title: localDataSettingSaveFailedTitle,
          paragraphs: [
            localDataSettingSaveFailedBody
          ],
          buttons: [
            (localDataCancel, false, tiamat.ButtonType.primary),
          ]);
    }
    await _load();
    return false;
  }

  Future<void> _moveTo(LocalDataKeyPlace place) async {
    final status = _status;
    if (status == null || status.place == place || _busy) return;
    final toFile = place == LocalDataKeyPlace.file;
    if (toFile) {
      final ok = await localDataDialog<bool>(context,
          title: localDataMoveToFileTitle,
          paragraphs: [
            localDataMoveToFileBody,
            localDataMoveToFileNoMoveBack
          ],
          buttons: [
            (localDataCancel, false, tiamat.ButtonType.secondary),
            (localDataMoveToFileConfirm, true, tiamat.ButtonType.primary),
          ]);
      if (ok != true) return;
    }
    while (mounted) {
      setState(() => _busy = true);
      // Moving to the file turns the automatic move back off.
      final moved = await LocalDataKeys.moveKey(place, pin: toFile);
      if (!mounted) return;
      setState(() => _busy = false);
      if (moved) break;
      final retry = await localDataDialog<bool>(context,
          title: localDataMoveFailedTitle,
          paragraphs: [
            localDataMoveFailedBody
          ],
          buttons: [
            (localDataCancel, false, tiamat.ButtonType.secondary),
            (localDataTryAgain, true, tiamat.ButtonType.primary),
          ]);
      if (retry != true) break;
    }
    await _load();
  }

  Future<void> _setAutoMove(bool on) async {
    setState(() => _busy = true);
    await LocalDataKeys.moveKey(LocalDataKeyPlace.file, pin: !on);
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!LocalDataKeys.supported) return const SizedBox.shrink();
    final status = _status;
    final encrypt = LocalDataKeys.encrypt;
    return SettingsSearchTarget(
      ids: [localDataSettingId, localDataSettingsTitle],
      child: tiamat.Panel(
        header: localDataSettingsTitle,
        mode: tiamat.TileType.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: tiamat.Text.labelEmphasised(localDataSwitch)),
              tiamat.Switch(
                  state: encrypt,
                  onChanged: _busy ? null : (on) => _switch(on)),
            ]),
            if (status != null) ...(encrypt ? _on(status) : _off(status)),
          ],
        ),
      ),
    );
  }

  List<Widget> _off(LocalDataPanelStatus status) {
    final failed = status.failedAccount;
    final bytes = status.bytesToFree;
    return [
      tiamat.Text.labelLow(localDataOffDescription),
      if (!status.allPlain) ...[
        const SizedBox(height: 10),
        _statusLine(Icons.lock_clock_outlined, localDataNotDecryptedYet,
            localDataPendingDecrypt,
            warning: false),
      ],
      if (bytes != null)
        _box(
            Icons.warning_amber_rounded,
            localDataNoSpaceDecryptTitle,
            localDataNoSpaceDecrypt(TextUtils.readableFileSize(bytes),
                localDataAccountName(status.noSpaceAccount))),
      if (failed != null)
        _box(
            Icons.error_outline,
            localDataDecryptFailedTitle(localDataAccountName(failed)),
            localDataDecryptFailedBody,
            action: localDataTryAgainNextStart,
            onAction: _retryNextStart),
    ];
  }

  Future<void> _retryNextStart() async {
    await LocalDataKeys.retryMigrationNextStart();
    await _load();
  }

  List<Widget> _on(LocalDataPanelStatus status) {
    final failed = status.failedAccount;
    final bytes = status.bytesToFree;
    String state(bool encrypted) =>
        encrypted ? localDataEncrypted : localDataNotEncryptedYet;
    return [
      const SizedBox(height: 10),
      if (status.allEncrypted)
        _statusLine(Icons.lock_outline, localDataEncrypted,
            localDataEncryptedDescription)
      else
        _statusLine(Icons.lock_clock_outlined, localDataNotEncryptedYet,
            localDataPendingEncrypt,
            warning: bytes != null || failed != null),
      const SizedBox(height: 8),
      for (final row in status.accounts)
        _row(localDataRowMessages(localDataAccountName(row.account)),
            state(row.encrypted), row.encrypted),
      _row(localDataRowMedia, state(status.appDataEncrypted),
          status.appDataEncrypted),
      if (bytes != null)
        _box(
            Icons.warning_amber_rounded,
            localDataNoSpaceTitle,
            localDataNoSpaceEncrypt(TextUtils.readableFileSize(bytes),
                localDataAccountName(status.noSpaceAccount))),
      if (failed != null)
        _box(
            Icons.error_outline,
            localDataFailedTitle(localDataAccountName(failed)),
            localDataFailedBody,
            action: localDataTryAgainNextStart,
            onAction: _retryNextStart),
      const SizedBox(height: 14),
      tiamat.Text.labelEmphasised(localDataWhereKept),
      if (status.place != null) ...[
        const SizedBox(height: 4),
        tiamat.Text.labelLow(
            localDataRightNow(localDataPlaceName(status.place!))),
      ],
      const SizedBox(height: 6),
      ..._places(status),
      const SizedBox(height: 12),
      tiamat.Text.labelLow(localDataFooter),
    ];
  }

  List<Widget> _places(LocalDataPanelStatus status) {
    if (Platform.isAndroid)
      return [tiamat.Text.labelLow(localDataAndroidDescription)];
    if (Platform.isIOS) return [tiamat.Text.labelLow(localDataIosDescription)];
    final ready = status.vaultReady && !_busy;
    final options = <Widget>[];
    if (Platform.isWindows) {
      options.add(_option(LocalDataKeyPlace.windows, localDataPlaceWindows,
          localDataWindowsDescription,
          recommended: true, enabled: ready, status: status));
    } else if (Platform.isMacOS) {
      options.add(_option(
          LocalDataKeyPlace.mac, localDataPlaceMac, localDataMacUnavailable,
          enabled: false, status: status));
    } else {
      final place = status.place == LocalDataKeyPlace.portal
          ? LocalDataKeyPlace.portal
          : LocalDataKeyPlace.keyring;
      options.add(_option(
          place,
          localDataPlaceKeyring,
          status.keyringAvailable
              ? localDataKeyringDescription
              : localDataNoKeyringFound,
          recommended: true,
          enabled: ready && status.keyringAvailable,
          status: status));
    }
    options.add(_option(
        LocalDataKeyPlace.file, localDataPlaceFile, localDataFileDescription,
        enabled: ready, status: status));
    if (status.place == LocalDataKeyPlace.file && status.keyringChoosable) {
      options.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelEmphasised(localDataAutoMove),
                tiamat.Text.labelLow(localDataAutoMoveDescription),
              ],
            ),
          ),
          tiamat.Switch(
              state: !status.pinnedToFile,
              onChanged: ready ? (on) => _setAutoMove(on) : null),
        ]),
      ));
    }
    return options;
  }

  Widget _option(LocalDataKeyPlace place, String title, String description,
      {bool recommended = false,
      required bool enabled,
      required LocalDataPanelStatus status}) {
    final selected = status.place == place ||
        (place == LocalDataKeyPlace.keyring &&
            status.place == LocalDataKeyPlace.portal);
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled || selected ? 1 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled && !selected ? () => _moveTo(place) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 1, 10, 0),
                child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? theme.colorScheme.primary : null),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 8, children: [
                      tiamat.Text.labelEmphasised(title),
                      if (recommended)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(localDataRecommended,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer)),
                        ),
                    ]),
                    tiamat.Text.labelLow(description),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLine(IconData icon, String title, String description,
      {bool warning = false}) {
    final color =
        warning ? Colors.amber : Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 1, 10, 0),
          child: Icon(icon, size: 20, color: color),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.labelEmphasised(title),
              tiamat.Text.labelLow(description),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String state, bool good) {
    return Padding(
      padding: const EdgeInsets.only(left: 30, top: 2, bottom: 2),
      child: Row(children: [
        Expanded(child: tiamat.Text.labelLow(label)),
        const SizedBox(width: 8),
        Text(state,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: good
                    ? Theme.of(context).colorScheme.primary
                    : Colors.amber)),
      ]),
    );
  }

  Widget _box(IconData icon, String title, String body,
      {String? action, Future<void> Function()? onAction}) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 1, 10, 0),
            child: Icon(icon, size: 20, color: Colors.amber),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelEmphasised(title),
                Text(body, style: theme.textTheme.bodySmall),
                if (action != null && onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: tiamat.Button.secondary(
                        text: action, onTap: () => onAction()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
