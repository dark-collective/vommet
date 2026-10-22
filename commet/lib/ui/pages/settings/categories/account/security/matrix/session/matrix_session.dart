import 'dart:async';

import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/matrix_session_view.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/matrix.dart';

import '../../../../../../matrix/verification/matrix_verification_page.dart';

class MatrixSession extends StatefulWidget {
  const MatrixSession(this.device, this.matrixClient,
      {super.key, this.onUpdated, this.inactive = false, this.removeSession});
  final Device device;
  final Client matrixClient;
  final Function? onUpdated;
  final Function? removeSession;
  final bool inactive;
  @override
  State<MatrixSession> createState() => _MatrixSessionState();
}

/// The encryption keys we know for [deviceId], one of [userId]'s sessions.
/// Null for a session that never uploaded device keys (some bots, keyless
/// logins) or before the device list has been loaded; such a session can't
/// be verified.
DeviceKeys? knownSessionKeys(Map<String, DeviceKeysList> userDeviceKeys,
    String? userId, String deviceId) {
  if (userId == null) return null;
  return userDeviceKeys[userId]?.deviceKeys[deviceId];
}

/// Whether we know [deviceId]'s keys, or can't tell yet because the device
/// list hasn't been downloaded (or is being refreshed).
SessionKeysState sessionKeysState(Map<String, DeviceKeysList> userDeviceKeys,
    String? userId, String deviceId) {
  if (knownSessionKeys(userDeviceKeys, userId, deviceId) != null) {
    return SessionKeysState.known;
  }
  if (userId == null) return SessionKeysState.missing;
  final list = userDeviceKeys[userId];
  if (list == null || list.outdated) return SessionKeysState.loading;
  return SessionKeysState.missing;
}

/// Vommet: whether a session is a dehydrated device (MSC3814), the stand-in
/// that collects message keys while all your devices are offline. It isn't
/// a device anyone signs in on, so the sessions list hides it.
bool isDehydratedSession(
    {String? displayName,
    Map<String, Object?>? deviceKeys,
    String sdkDisplayName = "Dehydrated Device"}) {
  if (deviceKeys?["dehydrated"] == true) return true;
  final name = displayName?.trim().toLowerCase();
  return name != null &&
      (name == sdkDisplayName.toLowerCase() || name == "dehydrated device");
}

class _MatrixSessionState extends State<MatrixSession> {
  Function()? previousOnUpdate;
  StreamSubscription? keysSubscription;
  bool editing = false;

  /// Shown until the device list is reloaded after a rename.
  String? renamedTo;

  @override
  void initState() {
    super.initState();
    if (sessionKeys() == null) waitForKeys();
  }

  /// The device list may still be loading, or this session may have signed
  /// in after it was downloaded: look again after each sync until its keys
  /// show up, so Verify appears without reopening the page.
  void waitForKeys() {
    widget.matrixClient.userDeviceKeysLoading?.then((_) {
      if (mounted) setState(() {});
    });
    // "finished" comes after the sync's device list update (onSync before).
    var shown = keysState();
    keysSubscription = widget.matrixClient.onSyncStatus.stream.listen((status) {
      if (status.status != SyncStatus.finished || !mounted) return;
      final state = keysState();
      if (state == shown) return;
      shown = state;
      if (state == SessionKeysState.known) {
        keysSubscription?.cancel();
        keysSubscription = null;
      }
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(MatrixSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (keysSubscription == null && sessionKeys() == null) waitForKeys();
  }

  @override
  void dispose() {
    keysSubscription?.cancel();
    super.dispose();
  }

  SessionKeysState keysState() => sessionKeysState(
      widget.matrixClient.userDeviceKeys,
      widget.matrixClient.userID,
      widget.device.deviceId);

  DeviceKeys? sessionKeys() => knownSessionKeys(
      widget.matrixClient.userDeviceKeys,
      widget.matrixClient.userID,
      widget.device.deviceId);

  @override
  Widget build(BuildContext context) {
    return MatrixSessionView(
      deviceId: widget.device.deviceId,
      displayName: renamedTo ?? widget.device.displayName,
      lastSeenIp: widget.device.lastSeenIp,
      lastSeenTimestamp: widget.device.lastSeenTs,
      verified: isVerified(),
      keysState: keysState(),
      isThisDevice: isCurrentDevice(),
      inactive: widget.inactive,
      beginVerification: beginVerification,
      removeSession: widget.removeSession,
      editing: editing,
      startRename: () => setState(() => editing = true),
      cancelRename: () => setState(() => editing = false),
      rename: rename,
    );
  }

  Future<void> rename(String name) async {
    try {
      await widget.matrixClient
          .updateDevice(widget.device.deviceId, displayName: name);
      if (!mounted) return;
      setState(() {
        renamedTo = name;
        editing = false;
      });
      widget.onUpdated?.call();
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't rename the session");
    }
  }

  bool isVerified() {
    return sessionKeys()?.verified ?? false;
  }

  bool isCurrentDevice() {
    return widget.device.deviceId == widget.matrixClient.deviceID;
  }

  void beginVerification() async {
    var keys = sessionKeys();
    if (keys == null) return;
    var request = await keys.startVerification();
    previousOnUpdate = request.onUpdate;
    request.onUpdate = onRequestUpdate;

    if (mounted)
      AdaptiveDialog.show(context,
          builder: (_) => MatrixVerificationPage(
              request: request, onRestart: beginVerification),
          title: "Verify a device");
  }

  void onRequestUpdate() {
    previousOnUpdate?.call();
    setState(() {});
  }
}
