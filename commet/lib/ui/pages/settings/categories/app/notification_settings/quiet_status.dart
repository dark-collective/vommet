import 'dart:async';

import 'package:commet/client/components/push_notification/modifiers/suppress_other_device_active.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' show Device;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: "Right now: …" under the "Quiet notifications while I'm chatting
/// on another device" setting: whether another of your devices is online,
/// which is what lets a chat's notifications go quiet here. Which chats are
/// quiet is decided per message (did you write there from that device in the
/// last 5 minutes), so this doesn't name rooms. Rechecks every minute while
/// shown.
class QuietNotificationsStatus extends StatefulWidget {
  const QuietNotificationsStatus({super.key});

  @override
  State<QuietNotificationsStatus> createState() =>
      _QuietNotificationsStatusState();
}

class _QuietNotificationsStatusState extends State<QuietNotificationsStatus> {
  Timer? _timer;
  StreamSubscription? _sub;
  String? _text;

  @override
  void initState() {
    super.initState();
    _sub = preferences.silenceNotifications.onChanged.listen((_) => _check());
    _check();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final text = await describe();
    if (mounted) setState(() => _text = text);
  }

  static Future<String> describe() async {
    if (!preferences.silenceNotifications.value) {
      return "Right now: off, so every notification makes its normal sound.";
    }
    final now = DateTime.now();
    Device? latest;
    for (final client in clientManager?.clients.whereType<MatrixClient>() ??
        <MatrixClient>[]) {
      final mx = client.getMatrixClient();
      try {
        final devices = await mx.getDevices() ?? const <Device>[];
        for (final device in devices) {
          if (device.deviceId == mx.deviceID) continue;
          if (!NotificationModifierSuppressOtherActiveDevice.otherDeviceOnline(
              [device], mx.deviceID, now)) {
            continue;
          }
          if (latest == null ||
              (device.lastSeenTs ?? 0) > (latest.lastSeenTs ?? 0)) {
            latest = device;
          }
        }
      } catch (_) {
        return "Right now: couldn't check your other devices, so "
            "notifications make their normal sound.";
      }
    }
    if (latest == null) {
      return "Right now: none of your other devices is online, so every "
          "notification makes its normal sound.";
    }
    final name = latest.displayName?.trim().isNotEmpty == true
        ? latest.displayName!.trim()
        : latest.deviceId;
    final minutes = now
        .difference(DateTime.fromMillisecondsSinceEpoch(latest.lastSeenTs!))
        .inMinutes;
    final when = minutes < 1 ? "just now" : "$minutes min ago";
    return "Right now: $name was online $when. A chat you write in there "
        "notifies quietly here for 5 minutes; everything else makes its "
        "normal sound.";
  }

  @override
  Widget build(BuildContext context) {
    if (_text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: tiamat.Text.labelLow(_text!),
    );
  }
}
