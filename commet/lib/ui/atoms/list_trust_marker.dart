// Vommet: the small icon after a direct message's name in chat lists. Lists
// only flag what needs a look before opening the chat: a DM that isn't
// encrypted (amber) or someone whose identity changed (red). Verified and
// plain encrypted DMs stay quiet here; the room header shows those.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/encryption_marker.dart';
import 'package:flutter/material.dart';

class ListTrustMarker extends StatefulWidget {
  const ListTrustMarker(this.room, {this.size = 14, super.key});

  final Room room;
  final double size;

  /// The kind a chat list shows for [kind], or null for no icon.
  static EncryptionMarkerKind? shownKind(EncryptionMarkerKind kind) =>
      switch (kind) {
        EncryptionMarkerKind.notEncryptedDirect ||
        EncryptionMarkerKind.identityChangedDirect =>
          kind,
        _ => null,
      };

  @override
  State<ListTrustMarker> createState() => _ListTrustMarkerState();
}

class _ListTrustMarkerState extends State<ListTrustMarker> {
  late final List<StreamSubscription> _subs;
  EncryptionMarkerKind? _kind;

  @override
  void initState() {
    super.initState();
    _kind = _compute();
    _subs = [
      widget.room.onUpdate.listen((_) => _refresh()),
      preferences.onSettingChanged.listen((_) => _refresh()),
      // A contact's keys change without any room update: re-check after sync.
      EncryptionMarker.keysUpdated(widget.room).listen((_) => _refresh()),
    ];
  }

  EncryptionMarkerKind? _compute() => EncryptionMarker.enabled
      ? ListTrustMarker.shownKind(EncryptionMarker.kindFor(widget.room))
      : null;

  // Only rebuild when the icon changes: this runs after every sync.
  void _refresh() {
    final kind = _compute();
    if (mounted && kind != _kind) setState(() => _kind = kind);
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
    final kind = _kind;
    if (kind == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: EncryptionMarkerIcon(kind, size: widget.size),
    );
  }
}
