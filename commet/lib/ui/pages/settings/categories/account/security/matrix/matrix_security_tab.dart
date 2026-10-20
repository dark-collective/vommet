import 'dart:async';

import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_flow.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/client/alert.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/account/security/blocked_users/blocked_users_panel.dart';
import 'package:commet/ui/molecules/alert_view.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/matrix_session.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'cross_signing/cross_signing_page.dart';
import 'key_file/key_file_row.dart';
import 'shared_history_setting.dart';

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
        sessionsPanel(),
        // Vommet: blocking is an experiment.
        if (preferences.experimentBlockUsers.value)
          BlockedUsersPanel(widget.client),
      ],
    );
  }

  Iterable<Device> get inactiveDevices =>
      devices?.where((i) => isDeviceInactive(i)) ?? [];

  Panel sessionsPanel() {
    return Panel(
      header: labelMatrixAccountSessions,
      mode: TileType.surfaceContainerLow,
      child: devices == null
          ? SizedBox(
              height: 300,
              child: Center(child: const CircularProgressIndicator()))
          : Column(
              children: [
                if (supportsLegacyUIA == true && inactiveDevices.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                    child: Container(
                      decoration: BoxDecoration(
                          color: ColorScheme.of(context).surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Flexible(
                              child: AlertView(
                                Alert(
                                  AlertType.warning,
                                  messageGetter: () =>
                                      "You have ${inactiveDevices.length} sessions which have not been used recently",
                                  titleGetter: () => "Inactive Devices",
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: tiamat.IconButton(
                                size: 15,
                                icon: Icons.logout,
                                onPressed: () {
                                  removeInactiveDevices();
                                },
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    var device = devices![index];
                    return Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: MatrixSession(
                        device,
                        widget.client.getMatrixClient(),
                        inactive: isDeviceInactive(device),
                        removeSession: supportsLegacyUIA == true
                            ? () => removeDeviceUIA(device.deviceId)
                            : canRemoveDeviceOAuth
                                ? () => removeDeviceOAuth(device.deviceId)
                                : null,
                      ),
                    );
                  },
                  itemCount: devices!.length,
                ),
              ],
            ),
    );
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

  Panel crossSigningPanel() {
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
                  SecureMessaging.of(widget.client).state ==
                      SecureMessagingState.notSetUp)
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
              // Vommet: replace the recovery key (Vommet issue 129).
              if (SecureSetupGate.enabled &&
                  SecureMessaging.of(widget.client).state ==
                      SecureMessagingState.ready)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                      onPressed: () => SecureSetupGate.open(
                          context, widget.client,
                          start: SecureSetupStart.replaceKey),
                      icon: const Icon(Icons.vpn_key_outlined),
                      label: tiamat.Text.label("Replace my recovery key")),
                ),
              crossSigning(),
              const tiamat.Seperator(),
              messageBackup(),
              // Vommet: export/import a key file.
              const tiamat.Seperator(),
              KeyFileRow(widget.client),
            ],
          ),
        ));
  }

  Widget crossSigning() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.label(unconfirmed
                  ? "Device confirmation"
                  : labelMatrixCrossSigning),
              tiamat.Text.labelLow(unconfirmed
                  ? "Not confirmed yet: other people see this device as unverified"
                  : labelMatrixCrossSigningExplanation)
            ],
          ),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
            child: unconfirmed
                ? tiamat.Button.secondary(
                    text: "Enter recovery key",
                    onTap: () => openSetup(SecureSetupStart.enterKey))
                : crossSigningEnabled
                    ? tiamat.Button.danger(
                        text: CommonStrings.promptReset,
                        onTap: () => AdaptiveDialog.show(context,
                            builder: (_) => MatrixCrossSigningPage(
                                  client: widget.client,
                                  mode:
                                      MatrixCrossSigningMode.resetCrossSigning,
                                  onComplete: checkState,
                                ),
                            dismissible: true,
                            title: labelMatrixResetCrossSigningTitle),
                      )
                    : tiamat.Button.secondary(
                        text: CommonStrings.promptEnable,
                        onTap: () => AdaptiveDialog.show(context,
                            builder: (_) => MatrixCrossSigningPage(
                                  client: widget.client,
                                  onComplete: checkState,
                                ),
                            dismissible: true,
                            title: labelMatrixCrossSigning),
                      )),
      ],
    );
  }

  Widget messageBackup() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.label(unconfirmed
                  ? "Message history backup"
                  : labelMatrixMessageBackup),
              tiamat.Text.labelLow(unconfirmed && messageBackupEnabled == true
                  ? "On. Your encrypted history is backed up; this device gets it once it's confirmed"
                  : labelMatrixMessageBackupExplanation)
            ],
          ),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
            child: messageBackupEnabled == true
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
                    : const CircularProgressIndicator())
      ],
    );
  }

  bool isDeviceInactive(Device device) {
    if (device.lastSeenTs == null) return false;

    var date = DateTime.fromMillisecondsSinceEpoch(device.lastSeenTs!);
    var diff = time.difference(date);

    return diff.inDays > 60;
  }
}
