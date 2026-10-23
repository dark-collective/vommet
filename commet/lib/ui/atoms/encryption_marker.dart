// Vommet: the one icon after a room's name that says whether it is encrypted,
// and, for direct messages, the most important thing about the other person.
// Encrypted rooms show nothing; everything else is an exception worth seeing.
import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/identity_pins.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

enum EncryptionMarkerKind {
  /// Encrypted, nothing notable: no icon.
  none,

  /// A room (public or invite-only) that isn't encrypted: grey.
  notEncrypted,

  /// A direct message that isn't encrypted (bridges, bots, old chats): amber.
  notEncryptedDirect,

  /// A direct message with someone whose identity you verified: green.
  verifiedDirect,

  /// A direct message with someone whose identity changed since we last saw
  /// it: red. Takes priority over everything else.
  identityChangedDirect,
}

const String secureMessagingHelpUrl =
    "https://vommet.app/help/secure-messaging";

class EncryptionMarker {
  static String get encryptionMarkerLabelEncrypted => Intl.message("Encrypted",
      name: "encryptionMarkerLabelEncrypted",
      desc:
          "Encryption marker next to a room name: tooltip for an encrypted room");

  static String get encryptionMarkerLabelNotEncrypted => Intl.message(
      "Not encrypted",
      name: "encryptionMarkerLabelNotEncrypted",
      desc:
          "Encryption marker next to a room name: tooltip for a room that isn't encrypted");

  static String get encryptionMarkerChatNotEncrypted => Intl.message(
      "This chat is not encrypted",
      name: "encryptionMarkerChatNotEncrypted",
      desc:
          "Encryption marker next to a room name: tooltip and dialog title for a direct message that isn't encrypted");

  static String get encryptionMarkerLabelVerified => Intl.message("Verified",
      name: "encryptionMarkerLabelVerified",
      desc:
          "Encryption marker next to a room name: tooltip for a direct message with a verified person");

  static String get encryptionMarkerIdentityChanged => Intl.message(
      "Their identity changed",
      name: "encryptionMarkerIdentityChanged",
      desc:
          "Encryption marker next to a room name: tooltip and dialog title when the other person's identity changed");

  static String get encryptionMarkerEncryptedTitle =>
      Intl.message("This chat is encrypted",
          name: "encryptionMarkerEncryptedTitle",
          desc: "Title of the dialog explaining an encrypted chat");

  static String get encryptionMarkerEncryptedBody => Intl.message(
      "Only the people in this chat can read its messages. Not even the server can.",
      name: "encryptionMarkerEncryptedBody",
      desc: "Body of the dialog explaining an encrypted chat");

  static String get encryptionMarkerRoomNotEncryptedTitle =>
      Intl.message("This room is not encrypted",
          name: "encryptionMarkerRoomNotEncryptedTitle",
          desc: "Title of the dialog explaining a room that isn't encrypted");

  static String get encryptionMarkerRoomNotEncryptedBody => Intl.message(
      "Your server, and anyone who joins this room, can read its messages, including old ones. Calls in this room aren't encrypted either.",
      name: "encryptionMarkerRoomNotEncryptedBody",
      desc: "Body of the dialog explaining a room that isn't encrypted");

  static String get encryptionMarkerDirectNotEncryptedBody => Intl.message(
      "Your server can read these messages and listen to calls here. That's unusual for a direct message: it often means the chat goes through a bridge or a bot, or was started by an app without encryption.",
      name: "encryptionMarkerDirectNotEncryptedBody",
      desc:
          "Body of the dialog explaining a direct message that isn't encrypted");

  static String get encryptionMarkerVerifiedTitle => Intl.message(
      "You verified this person",
      name: "encryptionMarkerVerifiedTitle",
      desc:
          "Title of the dialog explaining a direct message with a verified person");

  static String get encryptionMarkerVerifiedBody => Intl.message(
      "You checked that this account's devices really belong to them. Vommet will warn you if that ever changes.",
      name: "encryptionMarkerVerifiedBody",
      desc:
          "Body of the dialog explaining a direct message with a verified person");

  static String get encryptionMarkerIdentityChangedBody => Intl.message(
      "Their secure messaging was reset since you last talked. That happens when someone loses all their devices, but it's also what it looks like when someone is impersonating them. Check with them another way before sharing anything private.",
      name: "encryptionMarkerIdentityChangedBody",
      desc:
          "Body of the dialog shown when the other person's identity changed");

  static String get encryptionMarkerLearnMore => Intl.message("Learn more",
      name: "encryptionMarkerLearnMore",
      desc:
          "Button in the encryption explanation dialog that opens the help page");

  static bool get enabled => preferences.experimentEncryptionMarkers.value;

  static EncryptionMarkerKind kindFor(Room room) {
    final dms = room.client.getComponent<DirectMessagesComponent>();
    final isDirect = dms?.isRoomDirectMessage(room) == true;

    final identity = peerIdentity(room);
    if (identity == PeerIdentity.changed) {
      return EncryptionMarkerKind.identityChangedDirect;
    }

    if (!room.isE2EE) {
      return isDirect
          ? EncryptionMarkerKind.notEncryptedDirect
          : EncryptionMarkerKind.notEncrypted;
    }

    if (identity == PeerIdentity.verified) {
      return EncryptionMarkerKind.verifiedDirect;
    }

    return EncryptionMarkerKind.none;
  }

  /// Fires after each sync once everyone's device keys are up to date, so a
  /// contact's identity change shows without waiting for another room update.
  static Stream<void> keysUpdated(Room room) {
    if (room is! MatrixRoom) return const Stream.empty();
    return room.matrixRoom.client.onSyncStatus.stream
        .where((s) => s.status == matrix.SyncStatus.finished);
  }

  /// The other person's identity state in a direct message, or null when
  /// this isn't a Matrix direct message.
  static PeerIdentity? peerIdentity(Room room) {
    if (room is! MatrixRoom) return null;
    final dms = room.client.getComponent<DirectMessagesComponent>();
    if (dms?.isRoomDirectMessage(room) != true) return null;
    final partner = dms!.getDirectMessagePartnerId(room);
    if (partner == null) return null;
    return IdentityPins.check(room.matrixRoom.client, partner);
  }

  /// Amber for "you'd expect this to be private". Picked per brightness so it
  /// stays readable on light and dark themes, then nudged toward the theme's
  /// primary colour so it sits well in gradient and Material You themes.
  static Color warningColor(BuildContext context) =>
      _harmonize(context, const Color(0xffffb74d), const Color(0xff9a5b00));

  static Color verifiedColor(BuildContext context) =>
      _harmonize(context, const Color(0xff81c784), const Color(0xff1f7a3a));

  static Color _harmonize(BuildContext context, Color dark, Color light) {
    final theme = Theme.of(context);
    final base = theme.brightness == Brightness.dark ? dark : light;
    return Color.lerp(base, theme.colorScheme.primary, 0.12)!;
  }

  static IconData? iconFor(EncryptionMarkerKind kind) => switch (kind) {
        EncryptionMarkerKind.none => null,
        EncryptionMarkerKind.notEncrypted => Icons.no_encryption_outlined,
        EncryptionMarkerKind.notEncryptedDirect => Icons.no_encryption_outlined,
        EncryptionMarkerKind.verifiedDirect => Icons.verified_user,
        EncryptionMarkerKind.identityChangedDirect => Icons.gpp_maybe,
      };

  static Color colorFor(BuildContext context, EncryptionMarkerKind kind) =>
      switch (kind) {
        EncryptionMarkerKind.notEncryptedDirect => warningColor(context),
        EncryptionMarkerKind.verifiedDirect => verifiedColor(context),
        EncryptionMarkerKind.identityChangedDirect =>
          Theme.of(context).colorScheme.error,
        _ => Theme.of(context).colorScheme.onSurfaceVariant,
      };

  static String labelFor(EncryptionMarkerKind kind) => switch (kind) {
        EncryptionMarkerKind.none => encryptionMarkerLabelEncrypted,
        EncryptionMarkerKind.notEncrypted => encryptionMarkerLabelNotEncrypted,
        EncryptionMarkerKind.notEncryptedDirect =>
          encryptionMarkerChatNotEncrypted,
        EncryptionMarkerKind.verifiedDirect => encryptionMarkerLabelVerified,
        EncryptionMarkerKind.identityChangedDirect =>
          encryptionMarkerIdentityChanged,
      };

  static Future<void> explain(BuildContext context, EncryptionMarkerKind kind) {
    final (title, body) = switch (kind) {
      EncryptionMarkerKind.none => (
          encryptionMarkerEncryptedTitle,
          encryptionMarkerEncryptedBody
        ),
      EncryptionMarkerKind.notEncrypted => (
          encryptionMarkerRoomNotEncryptedTitle,
          encryptionMarkerRoomNotEncryptedBody
        ),
      EncryptionMarkerKind.notEncryptedDirect => (
          encryptionMarkerChatNotEncrypted,
          encryptionMarkerDirectNotEncryptedBody
        ),
      EncryptionMarkerKind.verifiedDirect => (
          encryptionMarkerVerifiedTitle,
          encryptionMarkerVerifiedBody
        ),
      EncryptionMarkerKind.identityChangedDirect => (
          encryptionMarkerIdentityChanged,
          encryptionMarkerIdentityChangedBody
        ),
    };

    return AdaptiveDialog.show(context,
        title: title,
        builder: (context) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    tiamat.Text.body(body),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => LinkUtils.open(Uri.parse(
                            kind == EncryptionMarkerKind.identityChangedDirect
                                ? "$secureMessagingHelpUrl#identity-changed"
                                : "$secureMessagingHelpUrl#which-chats")),
                        child: Text(encryptionMarkerLearnMore),
                      ),
                    ),
                  ],
                ),
              ),
            ));
  }
}

/// The marker icon itself; tap to explain. Renders nothing for encrypted rooms.
class EncryptionMarkerIcon extends StatelessWidget {
  const EncryptionMarkerIcon(this.kind, {this.size = 17, super.key});

  final EncryptionMarkerKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = EncryptionMarker.iconFor(kind);
    if (icon == null) return const SizedBox.shrink();

    return Tooltip(
      message: EncryptionMarker.labelFor(kind),
      child: Semantics(
        button: true,
        label: EncryptionMarker.labelFor(kind),
        child: InkWell(
          borderRadius: BorderRadius.circular(size),
          onTap: () => EncryptionMarker.explain(context, kind),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon,
                size: size, color: EncryptionMarker.colorFor(context, kind)),
          ),
        ),
      ),
    );
  }
}
