// Vommet: the strip above the message box in a direct message when the other
// person's identity changed, or when they never set up secure messaging.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/identity_pins.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/encryption_marker.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';

class DmTrustBanner extends StatefulWidget {
  const DmTrustBanner(this.room, {this.onLetThemKnow, super.key});

  final Room room;

  /// Puts a friendly heads-up into the message box.
  final void Function(String text)? onLetThemKnow;

  static final StringListPreference _dismissed =
      StringListPreference("vommet_dm_trust_dismissed", defaultValue: []);

  static bool get enabled => preferences.experimentDmTrustWarnings.value;

  /// Before starting a brand-new direct message: if the person never set up
  /// secure messaging, say so and let the user decide. Returns false to cancel.
  static Future<bool> confirmNewDirectMessage(
      BuildContext context, Client client, String userId, String name) async {
    if (!enabled || client is! MatrixClient) return true;
    final mx = client.getMatrixClient();
    try {
      await mx.updateUserDeviceKeys(
          additionalUsers: {userId}).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Offline or slow: don't block starting the chat.
      return true;
    }
    final keys = mx.userDeviceKeys[userId];
    if (keys == null || keys.masterKey != null) return true;
    if (!context.mounted) return true;

    final go = await AdaptiveDialog.show<bool>(context,
        title: "We can't confirm this is really $name",
        builder: (context) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("$name hasn't set up secure messaging. Usually "
                        "that's all it is, but it also means Vommet can't tell "
                        "if someone is impersonating them, and some messages "
                        "may not reach all their devices. You can still "
                        "message them."),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text("Message $name",
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    TextButton(
                      onPressed: () => LinkUtils.open(
                          Uri.parse("$secureMessagingHelpUrl#cant-confirm")),
                      child: const Text("What does this mean?"),
                    ),
                  ],
                ),
              ),
            ));
    return go == true;
  }

  @override
  State<DmTrustBanner> createState() => _DmTrustBannerState();
}

class _DmTrustBannerState extends State<DmTrustBanner> {
  late final List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      widget.room.onUpdate.listen((_) => _refresh()),
      preferences.onSettingChanged.listen((_) => _refresh()),
    ];
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  String? get _partner {
    final dms = widget.room.client.getComponent<DirectMessagesComponent>();
    if (dms?.isRoomDirectMessage(widget.room) != true) return null;
    return dms!.getDirectMessagePartnerId(widget.room);
  }

  @override
  Widget build(BuildContext context) {
    if (!DmTrustBanner.enabled) return const SizedBox.shrink();
    final room = widget.room;
    if (room is! MatrixRoom) return const SizedBox.shrink();
    final partner = _partner;
    if (partner == null) return const SizedBox.shrink();

    final name = room.displayName;
    switch (EncryptionMarker.peerIdentity(room)) {
      case PeerIdentity.changed:
        return _strip(
          context,
          color: Theme.of(context).colorScheme.error,
          icon: Icons.gpp_maybe,
          text: "$name's identity changed. If they didn't tell you they "
              "reset it, someone could be impersonating them.",
          actions: [
            TextButton(
              onPressed: () async {
                await IdentityPins.acknowledge(room.matrixRoom.client, partner);
                _refresh();
              },
              child: const Text("It was them"),
            ),
            TextButton(
              onPressed: () => _verify(context, room, partner),
              child: Text("Verify $name",
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        );
      case PeerIdentity.notSetUp:
        if (DmTrustBanner._dismissed.value.contains(room.identifier)) {
          return const SizedBox.shrink();
        }
        return _strip(
          context,
          color: EncryptionMarker.warningColor(context),
          icon: Icons.shield_outlined,
          text: "We can't confirm $name's devices are really theirs. Usually "
              "they just haven't set up secure messaging, but someone could "
              "be impersonating them. Some messages may not reach all their "
              "devices.",
          onClose: () => DmTrustBanner._dismissed
              .set([...DmTrustBanner._dismissed.value, room.identifier]),
          actions: [
            TextButton(
              onPressed: () => LinkUtils.open(
                  Uri.parse("$secureMessagingHelpUrl#cant-confirm")),
              child: const Text("What does this mean?"),
            ),
            if (widget.onLetThemKnow != null)
              TextButton(
                onPressed: () => widget.onLetThemKnow!(
                    "Hey! Your account hasn't set up secure messaging yet, so "
                    "you might miss some of my messages. It takes 2 minutes: "
                    "$secureMessagingHelpUrl"),
                child: const Text("Let them know"),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _verify(
      BuildContext context, MatrixRoom room, String partner) async {
    final keys = room.matrixRoom.client.userDeviceKeys[partner];
    if (keys == null) return;
    final request = await keys.startVerification();
    if (!context.mounted) return;
    await AdaptiveDialog.show(context,
        builder: (_) => MatrixVerificationPage(request: request),
        title: "Verify ${room.displayName}");
    _refresh();
  }

  Widget _strip(BuildContext context,
      {required Color color,
      required IconData icon,
      required String text,
      required List<Widget> actions,
      VoidCallback? onClose}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface, height: 1.3)),
                ),
                if (onClose != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: "Dismiss",
                    icon: Icon(Icons.close,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                    onPressed: onClose,
                  ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
