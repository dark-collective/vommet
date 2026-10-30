// Vommet issue 853: the strip above the message box in a direct message with
// a bridged user. Amber for a voice bridge puppet (nobody reads it), blue and
// closable for bridges that only deliver if the person linked their account.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';

class BridgedDmBanner extends StatefulWidget {
  const BridgedDmBanner(this.room, {super.key});

  final Room room;

  @override
  State<BridgedDmBanner> createState() => _BridgedDmBannerState();
}

class _BridgedDmBannerState extends State<BridgedDmBanner> {
  late final List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      preferences.onSettingChanged.listen((_) => _refresh()),
      BridgedUsers.onChanged.listen((_) => _refresh()),
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

  @override
  Widget build(BuildContext context) {
    if (!BridgedUsers.warn.value) return const SizedBox.shrink();
    final room = widget.room;
    final dms = room.client.getComponent<DirectMessagesComponent>();
    if (dms?.isRoomDirectMessage(room) != true) return const SizedBox.shrink();
    final partner = dms!.getDirectMessagePartnerId(room);
    if (partner == null) return const SizedBox.shrink();
    final user = BridgedUsers.of(room.client, partner, ignoreSetting: true);
    if (user == null) return const SizedBox.shrink();

    final name = room.displayName;
    switch (user.dms) {
      case BridgeDmReach.reaches:
        return const SizedBox.shrink();
      case BridgeDmReach.nobody:
        return _strip(context,
            color: const Color(0xFFE0A100),
            icon: Icons.warning_amber_rounded,
            text: bridgedPuppetBanner(name));
      case BridgeDmReach.mayNot:
        if (BridgedUsers.dismissedBanners.value.contains(room.identifier)) {
          return const SizedBox.shrink();
        }
        return _strip(context,
            color: const Color(0xFF3B82F6),
            icon: Icons.info_outline,
            text: bridgedMayNotReachBanner(name, BridgedUsers.labelOf(user)),
            onClose: () => BridgedUsers.dismissedBanners.set(
                [...BridgedUsers.dismissedBanners.value, room.identifier]));
    }
  }

  Widget _strip(BuildContext context,
      {required Color color,
      required IconData icon,
      required String text,
      VoidCallback? onClose}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 10, onClose == null ? 12 : 4, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
                tooltip: CommonStrings.promptDismiss,
                icon: Icon(Icons.close,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}
