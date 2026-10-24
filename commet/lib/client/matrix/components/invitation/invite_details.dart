import 'package:commet/client/matrix/components/invitation/invite_permission_config.dart';

/// Vommet: what an invite tells you before you accept it, read from the
/// room's stripped state (the events the inviting server sends along).
///
/// Tuwunel sends the create event (space or not), join rules, canonical
/// alias, name, avatar, topic, encryption, the inviter's membership and our
/// own invite membership (with its `reason` and `is_direct`). The member
/// count and a space's rooms aren't in there: [MatrixInvitePreview] asks for
/// them separately and they only show when the server answers.
///
/// Pure logic, so it can be unit tested.
class InviteDetails {
  const InviteDetails({
    required this.roomId,
    this.name,
    this.canonicalAlias,
    this.topic,
    this.avatarUrl,
    this.roomType,
    this.joinRule,
    this.encrypted = false,
    this.inviterId,
    this.inviterDisplayName,
    this.inviterAvatarUrl,
    this.reason,
    this.isDirect = false,
  });

  final String roomId;
  final String? name;
  final String? canonicalAlias;
  final String? topic;
  final String? avatarUrl;

  /// `m.room.create`'s `type`, e.g. `m.space`.
  final String? roomType;

  /// `m.room.join_rules`' `join_rule` (`public`, `invite`, `knock`, ...).
  final String? joinRule;
  final bool encrypted;

  final String? inviterId;
  final String? inviterDisplayName;
  final String? inviterAvatarUrl;

  /// The note the inviter wrote, if any.
  final String? reason;

  /// The inviter marked this as a direct message.
  final bool isDirect;

  bool get isSpace => roomType == "m.space";

  bool get isPublic => joinRule == "public";

  /// The inviter's server (no port), e.g. `example.org`.
  String? get inviterServer => InvitePermissionConfig.serverOf(inviterId);

  /// Builds the details from stripped state events. Each event is a map
  /// with `type`, `state_key`, `sender` and `content`. [myUserId] finds our
  /// own invite membership, whose sender is the inviter. [fallbackInviterId]
  /// is used when that membership is missing.
  static InviteDetails fromStrippedState(
    String roomId,
    String myUserId,
    Iterable<Map<String, dynamic>> events, {
    String? fallbackInviterId,
  }) {
    Map<String, dynamic>? find(String type, [String stateKey = ""]) {
      for (final e in events) {
        if (e["type"] == type && (e["state_key"] ?? "") == stateKey) {
          return e;
        }
      }
      return null;
    }

    Map<String, dynamic> contentOf(Map<String, dynamic>? event) {
      final c = event?["content"];
      return c is Map ? Map<String, dynamic>.from(c) : const {};
    }

    String? str(Map<String, dynamic> content, String key) {
      final v = content[key];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    final me = find("m.room.member", myUserId);
    final meContent = contentOf(me);
    final invitedByMe = meContent["membership"] == "invite";

    String? inviterId;
    if (invitedByMe && me?["sender"] is String && me!["sender"] != myUserId) {
      inviterId = me["sender"] as String;
    }
    inviterId ??= fallbackInviterId;

    final inviterContent = inviterId == null
        ? const <String, dynamic>{}
        : contentOf(find("m.room.member", inviterId));

    final encryption = contentOf(find("m.room.encryption"));

    return InviteDetails(
      roomId: roomId,
      name: str(contentOf(find("m.room.name")), "name"),
      canonicalAlias: str(contentOf(find("m.room.canonical_alias")), "alias"),
      topic: str(contentOf(find("m.room.topic")), "topic"),
      avatarUrl: str(contentOf(find("m.room.avatar")), "url"),
      roomType: str(contentOf(find("m.room.create")), "type"),
      joinRule: str(contentOf(find("m.room.join_rules")), "join_rule"),
      encrypted: str(encryption, "algorithm") != null,
      inviterId: inviterId,
      inviterDisplayName: str(inviterContent, "displayname"),
      inviterAvatarUrl: str(inviterContent, "avatar_url"),
      reason: invitedByMe ? str(meContent, "reason") : null,
      isDirect: invitedByMe && meContent["is_direct"] == true,
    );
  }
}
