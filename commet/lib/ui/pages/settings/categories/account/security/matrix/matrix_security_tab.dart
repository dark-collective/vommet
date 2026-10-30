import 'dart:async';

import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_flow.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/client/alert.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/account/security/blocked_users/blocked_users_panel.dart';
import 'package:commet/ui/molecules/alert_view.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/matrix_session.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/renamed_session_last_seen.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:tiamat/tiamat.dart' show Panel, TileType;
import 'package:tiamat/tiamat.dart' as tiamat;

import 'cross_signing/cross_signing_page.dart';
import 'key_file/key_file_row.dart';
import 'recovery_checkins_row.dart';
import 'shared_history_setting.dart';
import 'unverified_sessions_setting.dart';

class MatrixSecurityTab extends StatefulWidget {
  const MatrixSecurityTab(this.client, {super.key});
  final MatrixClient client;
  @override
  State<MatrixSecurityTab> createState() => _MatrixSecurityTabState();
}

class _MatrixSecurityTabState extends State<MatrixSecurityTab> {
  bool crossSigningEnabled = false;
  bool? messageBackupEnabled;
  bool isVerified = false;
  bool encryptionDisabled = false;
  List<Device>? devices;
  late DateTime time;

  Map<String, Object?>? authMetadata;

  bool? supportsLegacyUIA;

  Uri? get accountManagementUri {
    var str = authMetadata?.tryGet<String>("account_management_uri");
    if (str == null) return null;
    return Uri.tryParse(str);
  }

  List<String>? get supportedActions =>
      authMetadata?.tryGetList<String>("account_management_actions_supported");

  bool get canRemoveDeviceOAuth =>
      supportedActions?.contains("org.matrix.device_delete") == true &&
      accountManagementUri != null;

  String get labelMatrixCrossSigning => Intl.message("Cross signing",
      desc: "Title label for matrix cross signing",
      name: "labelMatrixCrossSigning");

  String get labelMatrixCrossSigningAndBackup => Intl.message(
      "Cross Signing & Backup",
      desc: "Header label for matrix cross signing and message backup section",
      name: "labelMatrixCrossSigningAndBackup");

  String get labelMatrixAccountSessions => Intl.message("Sessions",
      desc: "Title label for account sessions",
      name: "labelMatrixAccountSessions");

  String get labelMatrixCrossSigningExplanation =>
      Intl.message("Setup to verify and keep track of all your sessions",
          desc: "Explains what matrix cross signing does",
          name: "labelMatrixCrossSigningExplanation");

  String get labelMatrixResetCrossSigningTitle =>
      Intl.message("Reset cross signing",
          desc: "Title for the popup dialog when resetting cross signing",
          name: "labelMatrixResetCrossSigningTitle");

  String get labelMatrixMessageBackup => Intl.message("Message backup",
      desc: "TItle label for matrix message backup settings",
      name: "labelMatrixMessageBackup");

  String get labelMatrixMessageBackupExplanation => Intl.message(
      "Maintains a backup of your message history, in case you lose all your sessions. Your messages will be encrypted before uploading",
      desc: "Explains what matrix message backup does",
      name: "labelMatrixMessageBackupExplanation");

  String get promptSetupMatrixMessageBackup => Intl.message("Setup backup",
      desc: "Text on the button to begin the setup process for message backup",
      name: "promptSetupMatrixMessageBackup");

  String get labelRestoreMatrixBackupTitle => Intl.message("Restore backup",
      desc: "Title of the popup dialog for restoring message backup",
      name: "labelRestoreMatrixBackupTitle");

  /// Vommet: follows this device being confirmed from another device (a
  /// verification Element started, say) while this page is open.
  StreamSubscription<SecureMessagingStatus>? _statusSub;
  SecureMessagingState? _lastState;

  @override
  void initState() {
    time = DateTime.now();
    checkState();
    getDevices();
    _statusSub =
        SecureMessaging.watchConfirmation(widget.client).listen(_onStatus);

    widget.client.hasServerDisabledEncryption().then((v) => setState(() {
          encryptionDisabled = v;
        }));

    super.initState();
  }

  void _onStatus(SecureMessagingStatus status) {
    final before = _lastState;
    _lastState = status.state;
    if (!mounted) return;
    if (before == SecureMessagingState.thisDeviceUnverified &&
        status.state == SecureMessagingState.ready) {
      Log.i("Security settings: this device was confirmed elsewhere");
      unawaited(
          SecureMessaging.finishConfirmation(widget.client.getMatrixClient())
              .catchError((Object e, StackTrace s) =>
                  Log.onError(e, s, content: "Couldn't finish device approval"))
              .whenComplete(() {
        if (mounted) checkState();
      }));
    }
    checkState();
    // The first status is the one initState already showed.
    if (before != null) getDevices();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  void checkState() {
    setState(() {
      var encryption = widget.client.getMatrixClient().encryption;
      crossSigningEnabled = encryption?.crossSigning.enabled ?? false;
      messageBackupEnabled = encryption?.keyManager.enabled ?? false;
      isVerified = widget.client.matrixClient.isUnknownSession == false;
    });
  }

  void getDevices() async {
    var gotDevices = await widget.client.getMatrixClient().getDevices();

    if (supportsLegacyUIA == null) {
      try {
        await widget.client.matrixClient
            .request(RequestType.DELETE, "/client/v3/devices/_", data: {
          "auth": {
            "type": "m.login.dummy",
          }
        });
      } catch (e) {
        if (e case MatrixException mx) {
          if (mx.error == MatrixError.M_FORBIDDEN) {
            supportsLegacyUIA = true;
          } else {
            supportsLegacyUIA = false;
          }
        }
      }
    }

    if (supportsLegacyUIA != true) {
      if (authMetadata == null) {
        try {
          authMetadata = await widget.client.matrixClient
              .request(RequestType.GET, "/client/v1/auth_metadata");
        } catch (e, s) {
          Log.onError(e, s);
        }
      }
    }

    // Vommet: undo the last-seen a rename stamped on a session.
    final userId = widget.client.matrixClient.userID;
    if (gotDevices != null && userId != null) {
      await RenamedSessionLastSeen(preferences.vommetSharedPreferences)
          .restore(userId, gotDevices);
    }

    gotDevices
        ?.sort((a, b) => (b.lastSeenTs ?? 0).compareTo(a.lastSeenTs ?? 0));

    if (mounted)
      setState(() {
        devices = gotDevices;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      spacing: 4,
      children: [
        crossSigningPanel(),
        // Vommet issue 439.
        SharedHistoryPanel(widget.client),
        // Vommet issue 947.
        const UnverifiedSessionsPanel(),
        sessionsPanel(),
        // Vommet: blocking is an experiment.
        if (preferences.experimentBlockUsers.value)
          BlockedUsersPanel(widget.client),
      ],
    );
  }

  Iterable<Device> get inactiveDevices =>
      shownDevices.where((i) => isDeviceInactive(i));

  bool isCurrentDevice(Device device) =>
      device.deviceId == widget.client.getMatrixClient().deviceID;

  DeviceKeys? keysOf(Device device) {
    final mx = widget.client.getMatrixClient();
    return knownSessionKeys(mx.userDeviceKeys, mx.userID, device.deviceId);
  }

  /// Vommet: every session except the dehydrated device (MSC3814), which
  /// only holds keys while you're offline; signing it out would break that.
  Iterable<Device> get shownDevices =>
      devices?.where((d) => !isDehydratedSession(
          displayName: d.displayName,
          deviceKeys: keysOf(d)?.toJson(),
          sdkDisplayName:
              widget.client.getMatrixClient().dehydratedDeviceDisplayName)) ??
      [];

  Iterable<Device> get otherDevices =>
      shownDevices.where((d) => !isCurrentDevice(d));

  /// Other sessions we know the keys of that aren't verified.
  Iterable<Device> get unverifiedDevices => otherDevices.where((d) {
        final keys = keysOf(d);
        return keys != null && !keys.verified;
      });

  Function? removeSessionFor(Device device) {
    if (isCurrentDevice(device)) return null;
    if (supportsLegacyUIA == true) {
      return () => removeDeviceUIA(device.deviceId);
    }
    if (canRemoveDeviceOAuth) return () => removeDeviceOAuth(device.deviceId);
    return null;
  }

  Widget session(Device device) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MatrixSession(
          device,
          widget.client.getMatrixClient(),
          key: ValueKey(device.deviceId),
          inactive: isDeviceInactive(device),
          onUpdated: getDevices,
          removeSession: removeSessionFor(device),
        ),
      );

  Widget sectionLabel(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    letterSpacing: .8,
                    fontWeight: FontWeight.w700,
                    color: ColorScheme.of(context).onSurfaceVariant)),
          ),
          if (trailing != null) trailing,
        ]),
      );

  /// Vommet: points out sessions worth a look (unverified, or unused for
  /// 60 days), with a one-tap sign-out for the unused ones.
  Widget? cleanupHint() {
    final unverified = unverifiedDevices.length;
    final inactive = inactiveDevices.length;
    if (unverified == 0 && inactive == 0) return null;
    final parts = [
      if (unverified == 1) "1 session isn't verified",
      if (unverified > 1) "$unverified sessions aren't verified",
      if (inactive == 1) "1 hasn't been used in 60 days",
      if (inactive > 1) "$inactive haven't been used in 60 days",
    ];
    var text = parts.join(" and ");
    if (unverified == 0) {
      text = inactive == 1
          ? "1 session hasn't been used in 60 days"
          : "$inactive sessions haven't been used in 60 days";
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
          color: Colors.orange.withAlpha(28),
          borderRadius: BorderRadius.circular(10)),
      child: Row(spacing: 10, children: [
        Icon(Icons.cleaning_services_outlined,
            color: Colors.orange.shade400, size: 20),
        Expanded(
            child: tiamat.Text.labelLow(
                "$text. Sign out of any you don't recognize.")),
        if (supportsLegacyUIA == true && inactive > 0)
          tiamat.Button.secondary(
              text: "Sign out unused", onTap: removeInactiveDevices),
      ]),
    );
  }

  Panel sessionsPanel() {
    final current = shownDevices.where(isCurrentDevice).firstOrNull;
    final others = otherDevices.toList();
    final hint = devices == null ? null : cleanupHint();
    return Panel(
      header: labelMatrixAccountSessions,
      mode: TileType.surfaceContainerLow,
      child: devices == null
          ? SizedBox(
              height: 300,
              child: Center(child: const CircularProgressIndicator()))
          : Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (current != null) ...[
                    sectionLabel("This device"),
                    session(current),
                  ],
                  if (others.isNotEmpty) ...[
                    sectionLabel("Other sessions · ${others.length}",
                        trailing: supportsLegacyUIA == true
                            ? InkWell(
                                mouseCursor: WidgetStateMouseCursor.clickable,
                                borderRadius: BorderRadius.circular(6),
                                onTap: removeOtherDevices,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  child: Text("Sign out of all others",
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                              color: ColorScheme.of(context)
                                                  .error)),
                                ),
                              )
                            : null),
                    if (hint != null) hint,
                    for (final device in others) session(device),
                  ],
                ],
              ),
            ),
    );
  }

  void removeOtherDevices() async {
    final others = otherDevices.map((i) => i.deviceId).toList();
    if (others.isEmpty) return;
    var confirm = await AdaptiveDialog.confirmation(context,
        dangerous: true,
        prompt: others.length == 1
            ? "Sign out of your other session?"
            : "Sign out of all ${others.length} other sessions?");

    if (confirm != true) return;

    await widget.client.matrixClient.uiaRequestBackground((auth) async {
      await widget.client.matrixClient.deleteDevices(others, auth: auth);
    });

    getDevices();
  }

  void removeDeviceUIA(String deviceID) async {
    await widget.client.matrixClient.uiaRequestBackground((auth) async {
      await widget.client.matrixClient.deleteDevice(deviceID, auth: auth);

      getDevices();
    });
  }

  void removeInactiveDevices() async {
    var confirm = await AdaptiveDialog.confirmation(context,
        dangerous: true,
        prompt:
            "Are you sure you want to log out of ${inactiveDevices.length} sessions?");

    if (confirm != true) return;

    await widget.client.matrixClient.uiaRequestBackground((auth) async {
      await widget.client.matrixClient.deleteDevices(
          inactiveDevices.map((i) => i.deviceId).toList(),
          auth: auth);
    });

    getDevices();
  }

  void removeDeviceOAuth(String deviceID) {
    LinkUtils.open(
        accountManagementUri!.replace(queryParameters: {
          "action": "org.matrix.device_delete",
          "device_id": deviceID
        }),
        context: context,
        filterTrackingParameters: false,
        bypassConfirmation: false);
  }

  void onUpdated() {
    setState(() {
      getDevices();
    });
  }

  /// Vommet: the account has secure messaging but this device isn't
  /// confirmed yet; the panel then leads with "Confirm this device".
  bool get unconfirmed =>
      SecureSetupGate.enabled &&
      SecureMessaging.of(widget.client).state ==
          SecureMessagingState.thisDeviceUnverified;

  Future<void> openSetup(SecureSetupStart start) async {
    await SecureSetupGate.open(context, widget.client, start: start);
    if (mounted) {
      checkState();
      setState(() {});
    }
  }

  /// Vommet: one clear way in for an unconfirmed device, instead of the
  /// recovery key hiding behind "Message backup › Restore".
  Widget confirmThisDevice() {
    final scheme = ColorScheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: scheme.primaryContainer.withAlpha(40),
          border: Border.all(color: scheme.primary.withAlpha(140)),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(spacing: 8, children: [
            Icon(Icons.phonelink_lock_outlined, color: scheme.primary),
            Flexible(child: tiamat.Text.largeTitle("Confirm this device")),
          ]),
          tiamat.Text.labelLow(
              "Your account already has secure messaging. Enter your recovery key (or recovery phrase) to read your encrypted messages here and show others this device is really you."),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: () => openSetup(SecureSetupStart.enterKey),
                icon: const Icon(Icons.vpn_key_outlined),
                label: tiamat.Text.label("Enter recovery key")),
            OutlinedButton.icon(
                onPressed: () => openSetup(SecureSetupStart.approve),
                icon: const Icon(Icons.devices_outlined),
                label: tiamat.Text.label("Use another device instead")),
          ]),
          tiamat.Text.labelLow(
              "Lost your recovery key? You can reset it, but older encrypted messages may become unreadable."),
        ],
      ),
    );
  }

  SecureMessagingState get secureState =>
      SecureMessaging.of(widget.client).state;

  bool get secureReady =>
      SecureSetupGate.enabled && secureState == SecureMessagingState.ready;

  /// Vommet: a row with a leading icon, title, explanation and buttons.
  Widget settingRow(IconData icon, Widget content) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(icon,
                size: 22, color: ColorScheme.of(context).onSurfaceVariant),
          ),
          Expanded(child: content),
        ]),
      );

  Widget rowContent(String title, String body, Widget action) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                tiamat.Text.label(title),
                tiamat.Text.labelLow(body),
              ],
            ),
          ),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 0, 0), child: action),
        ],
      );

  /// Vommet: one line saying everything is in order.
  Widget secureStatus() {
    const green = Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: green.withAlpha(30),
          border: Border.all(color: green.withAlpha(110)),
          borderRadius: BorderRadius.circular(10)),
      child: Row(spacing: 10, children: [
        const Icon(Icons.verified_user_outlined, color: green, size: 22),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              tiamat.Text.labelEmphasised("Secure messaging is on"),
              tiamat.Text.labelLow(messageBackupEnabled == true
                  ? "This device is confirmed and your message history is backed up."
                  : "This device is confirmed."),
            ],
          ),
        ),
      ]),
    );
  }

  /// Vommet: replacing the recovery key (Vommet issue 129) in a row of its
  /// own, instead of a lone button above the panel.
  Widget recoveryKey() => settingRow(
      Icons.vpn_key_outlined,
      rowContent(
          "Recovery key",
          "Unlocks your messages on a new device. Replace it if you've lost it or someone else may have seen it.",
          tiamat.Button.secondary(
              text: "Replace key",
              onTap: () => openSetup(SecureSetupStart.replaceKey))));

  /// Vommet: the old cross-signing Reset, set apart and explained, since it
  /// is only for when the recovery key and every other device are gone.
  Widget resetEncryption() {
    final scheme = ColorScheme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
          border: Border.all(color: scheme.error.withAlpha(120)),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Icon(Icons.restart_alt_rounded, size: 22, color: scheme.error),
        ),
        Expanded(
          child: rowContent(
              "Reset encryption",
              "Only if you've lost your recovery key and all your other devices. Starts over with a new key; older encrypted messages may become unreadable, and people will need to verify you again.",
              tiamat.Button.danger(
                text: "Reset…",
                onTap: () => AdaptiveDialog.show(context,
                    builder: (_) => MatrixCrossSigningPage(
                          client: widget.client,
                          mode: MatrixCrossSigningMode.resetCrossSigning,
                          onComplete: checkState,
                        ),
                    dismissible: true,
                    title: "Reset encryption"),
              )),
        ),
      ]),
    );
  }

  Panel crossSigningPanel() {
    final hasKeyFile = widget.client.getMatrixClient().encryption != null;
    return Panel(
        header: "Encryption & recovery",
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            spacing: 4,
            children: [
              if (encryptionDisabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: Container(
                    decoration: BoxDecoration(
                        color: ColorScheme.of(context).surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: AlertView(Alert(AlertType.info,
                          messageGetter: () =>
                              "Your homeserver has force-disabled encryption",
                          titleGetter: () => "Encryption Disabled")),
                    ),
                  ),
                ),
              if (unconfirmed) confirmThisDevice(),
              if (!isVerified && !unconfirmed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: Container(
                    decoration: BoxDecoration(
                        color: ColorScheme.of(context).surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: AlertView(Alert(AlertType.warning,
                          messageGetter: () =>
                              "Your current session is not verified. You will not be able to participate in encrypted chats.",
                          titleGetter: () => "Unverified")),
                    ),
                  ),
                ),
              // Vommet: the guided setup (Vommet issue 129).
              if (SecureSetupGate.enabled &&
                  secureState == SecureMessagingState.notSetUp)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                      onPressed: () async {
                        await SecureSetupGate.open(context, widget.client);
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.shield_outlined),
                      label: tiamat.Text.label("Set up secure messaging")),
                ),
              if (secureReady) ...[
                secureStatus(),
                recoveryKey(),
                // Vommet: the "Still have your recovery key?" check-ins.
                RecoveryCheckInsRow(
                    SecureSetupRecords(widget.client.getMatrixClient().userID!),
                    client: widget.client.getMatrixClient()),
                const tiamat.Seperator(),
              ],
              if (unconfirmed || !crossSigningEnabled) ...[
                crossSigning(),
                const tiamat.Seperator(),
              ],
              messageBackup(),
              // Vommet: export/import a key file.
              if (hasKeyFile) ...[
                const tiamat.Seperator(),
                settingRow(
                    Icons.description_outlined, KeyFileRow(widget.client)),
              ],
              if (crossSigningEnabled) resetEncryption(),
            ],
          ),
        ));
  }

  Widget crossSigning() {
    return settingRow(
        Icons.devices_outlined,
        rowContent(
            unconfirmed ? "Device confirmation" : labelMatrixCrossSigning,
            unconfirmed
                ? "Not confirmed yet: other people see this device as unverified"
                : labelMatrixCrossSigningExplanation,
            unconfirmed
                ? tiamat.Button.secondary(
                    text: "Enter recovery key",
                    onTap: () => openSetup(SecureSetupStart.enterKey))
                : tiamat.Button.secondary(
                    text: CommonStrings.promptEnable,
                    onTap: () => AdaptiveDialog.show(context,
                        builder: (_) => MatrixCrossSigningPage(
                              client: widget.client,
                              onComplete: checkState,
                            ),
                        dismissible: true,
                        title: labelMatrixCrossSigning),
                  )));
  }

  Widget messageBackup() {
    final on = messageBackupEnabled == true;
    // Vommet Deep Search: its keys line's Details opens Security here.
    return SettingsSearchTarget(
        ids: const [messageBackupSettingId], child: _messageBackupRow(on));
  }

  Widget _messageBackupRow(bool on) {
    return settingRow(
        on ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        rowContent(
            "Message history backup",
            unconfirmed && on
                ? "On. Your encrypted history is backed up; this device gets it once it's confirmed"
                : on
                    ? "On. An encrypted copy of your history, in case you lose all your devices."
                    : labelMatrixMessageBackupExplanation,
            on
                ? tiamat.Button.secondary(
                    text: CommonStrings.promptRestore,
                    onTap: () => AdaptiveDialog.show(context,
                        builder: (_) => MatrixCrossSigningPage(
                              client: widget.client,
                              onComplete: checkState,
                              mode: MatrixCrossSigningMode.restoreBackup,
                            ),
                        dismissible: true,
                        title: labelRestoreMatrixBackupTitle),
                  )
                : messageBackupEnabled == false
                    ? tiamat.Button.secondary(
                        text: CommonStrings.promptEnable,
                        onTap: () => AdaptiveDialog.show(context,
                            builder: (_) => MatrixCrossSigningPage(
                                  client: widget.client,
                                  onComplete: checkState,
                                  mode: MatrixCrossSigningMode.enableBackup,
                                ),
                            dismissible: true,
                            title: promptSetupMatrixMessageBackup),
                      )
                    : const CircularProgressIndicator()));
  }

  bool isDeviceInactive(Device device) {
    if (device.lastSeenTs == null) return false;

    var date = DateTime.fromMillisecondsSinceEpoch(device.lastSeenTs!);
    var diff = time.difference(date);

    return diff.inDays > 60;
  }
}
