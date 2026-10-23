// Vommet: a one-line note above a call that isn't encrypted, shown before
// joining and for the whole call (Vommet issue 131). Amber in a direct
// message, grey in an invite-only room; public and space rooms get no strip,
// only the grey icon after their name. An identity change is already shown by
// the DM's own banner, which stays on screen below the call.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/encryption_marker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

enum CallEncryptionNote {
  /// An unencrypted call in a direct message: amber.
  direct,

  /// An unencrypted call in an invite-only room: grey.
  private,
}

class CallEncryptionStrip extends StatefulWidget {
  const CallEncryptionStrip(this.room, {super.key});

  final Room room;

  static String get callEncryptionStripNotEncrypted => Intl.message(
      "This call isn't encrypted. The server can listen in.",
      name: "callEncryptionStripNotEncrypted",
      desc:
          "One-line note above a call in a direct message or invite-only room that isn't encrypted");

  /// Which note [room]'s call gets, or null for none.
  static CallEncryptionNote? noteFor(Room room) {
    if (!EncryptionMarker.enabled || room.isE2EE) return null;
    switch (EncryptionMarker.kindFor(room)) {
      case EncryptionMarkerKind.notEncryptedDirect:
        return CallEncryptionNote.direct;
      case EncryptionMarkerKind.notEncrypted:
        return isInviteOnly(room) ? CallEncryptionNote.private : null;
      default:
        // An unencrypted DM whose partner's identity also changed: the DM
        // banner covers that, and the call is still not encrypted.
        return EncryptionMarker.peerIdentity(room) == null
            ? null
            : CallEncryptionNote.direct;
    }
  }

  /// Invite-only (or knock) rooms: people expect them to be private. Public
  /// and space-restricted rooms are open to many, so no strip there.
  static bool isInviteOnly(Room room) {
    if (room is! MatrixRoom) return false;
    return switch (room.matrixRoom.joinRules) {
      matrix.JoinRules.invite ||
      matrix.JoinRules.knock ||
      matrix.JoinRules.private =>
        true,
      _ => false,
    };
  }

  @override
  State<CallEncryptionStrip> createState() => _CallEncryptionStripState();
}

class _CallEncryptionStripState extends State<CallEncryptionStrip> {
  late final List<StreamSubscription> _subs;
  CallEncryptionNote? _note;

  @override
  void initState() {
    super.initState();
    _note = CallEncryptionStrip.noteFor(widget.room);
    _subs = [
      widget.room.onUpdate.listen((_) => _refresh()),
      preferences.onSettingChanged.listen((_) => _refresh()),
    ];
  }

  void _refresh() {
    final note = CallEncryptionStrip.noteFor(widget.room);
    if (mounted && note != _note) setState(() => _note = note);
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
    final note = _note;
    if (note == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final kind = note == CallEncryptionNote.direct
        ? EncryptionMarkerKind.notEncryptedDirect
        : EncryptionMarkerKind.notEncrypted;
    final color = EncryptionMarker.colorFor(context, kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Material(
        color: color.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => EncryptionMarker.explain(context, kind),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.no_encryption_outlined, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    CallEncryptionStrip.callEncryptionStripNotEncrypted,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
