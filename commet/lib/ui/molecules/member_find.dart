// Vommet: the member list's find box (one row with the invite button, pinned
// under the tabs): filters the room's members by name or Matrix ID.
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A member with its name and Matrix ID lowercased once, so a keystroke in a
/// room of thousands only compares strings.
class MemberFindKey {
  MemberFindKey(this.member)
      : name = member.displayName.toLowerCase(),
        id = member.identifier.toLowerCase();
  final Member member;
  final String name;
  final String id;
}

/// A member the query matched, with the matched part of the name and of the
/// Matrix ID (null where that one doesn't match).
class MemberFindMatch {
  const MemberFindMatch(this.member, {this.nameRange, this.idRange});
  final Member member;
  final TextRange? nameRange;
  final TextRange? idRange;
}

/// The members of [keys] whose name or Matrix ID holds [query], ignoring
/// case, in [keys]' order.
List<MemberFindMatch> memberFindMatches(
  String query,
  Iterable<MemberFindKey> keys,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final result = <MemberFindMatch>[];
  for (final key in keys) {
    final inName = key.name.indexOf(q);
    final inId = key.id.indexOf(q);
    if (inName < 0 && inId < 0) continue;
    result.add(
      MemberFindMatch(
        key.member,
        nameRange: inName < 0
            ? null
            : TextRange(start: inName, end: inName + q.length),
        idRange: inId < 0 ? null : TextRange(start: inId, end: inId + q.length),
      ),
    );
  }
  return result;
}

/// The membership chips under the box: Banned and Left only for people
/// allowed to ban.
List<MemberMembership> memberFindChips({required bool canBan}) => canBan
    ? MemberMembership.values
    : const [MemberMembership.joined, MemberMembership.invited];

/// The member menu for an Invited or Left result: the normal menu without
/// Set role (they are not in the room), and for Left also without Kick (the
/// server refuses it; for an invite, Kick revokes it). Ban stays.
List<tiamat.ContextMenuItem> memberFindMenuItems(
    MemberMembership membership, List<tiamat.ContextMenuItem> items) {
  const setRole = "Set Role", kick = "Kick";
  return switch (membership) {
    MemberMembership.invited => [
        for (final i in items)
          if (i.text != setRole) i
      ],
    MemberMembership.left => [
        for (final i in items)
          if (i.text != setRole && i.text != kick) i
      ],
    _ => items,
  };
}

/// Whether the results start with "Invite <query>": nobody joined matches
/// and the user may invite.
bool memberFindOffersInvite({
  required String query,
  required int joinedMatches,
  required bool canInvite,
}) =>
    canInvite && query.trim().isNotEmpty && joinedMatches == 0;

/// A full Matrix ID (`@name:server`).
bool memberFindIsUserId(String query) =>
    RegExp(r'^@[^:\s]+:[^\s]+$').hasMatch(query.trim());

class MemberFindStrings {
  /// [count] is the room's member count, formatted ([formatCount]).
  static String memberFindIn(String count) => Intl.message(
        "Find in $count members",
        args: [count],
        name: "memberFindIn",
        desc: "Member list: hint of the find box above the members; count is "
            "the room's member count",
      );

  static String formatCount(int count) =>
      NumberFormat.decimalPattern().format(count);

  static String get memberFindInviteMembers => Intl.message(
        "Invite members",
        name: "memberFindInviteMembers",
        desc: "Member list: tooltip of the invite button beside the find box",
      );

  static String get memberFindClear => Intl.message(
        "Clear",
        name: "memberFindClear",
        desc: "Member list: tooltip of the find box's ✕ button",
      );

  static String memberFindCount(String matches, String total) => Intl.message(
        "$matches of $total · name or ID",
        args: [matches, total],
        name: "memberFindCount",
        desc: "Member list: label above the find results: how many members "
            "match out of how many, matched by name or Matrix ID",
      );

  static String get memberFindLoadingAll => Intl.message(
        "Loading all members…",
        name: "memberFindLoadingAll",
        desc: "Member list: shown under the find box while the room's full "
            "member list is still loading",
      );

  static String memberFindInviteUserId(String userId) => Intl.message(
        "Invite $userId",
        args: [userId],
        name: "memberFindInviteUserId",
        desc: "Member list: find result that invites the typed Matrix ID",
      );

  static String memberFindInviteName(String name) => Intl.message(
        "Invite \"$name\"…",
        args: [name],
        name: "memberFindInviteName",
        desc: "Member list: find result that opens the invite dialog with the "
            "typed name",
      );

  static String get memberFindNotInRoom => Intl.message(
        "Not in this room yet",
        name: "memberFindNotInRoom",
        desc:
            "Member list: second line of the find result that invites someone",
      );

  static String get memberFindBanned => Intl.message(
        "Banned",
        name: "memberFindBanned",
        desc: "Member list: chip showing banned members, and the tag on their "
            "rows",
      );

  static String memberFindUnbanPrompt(String name) => Intl.message(
        "Unban $name? They'll be able to join again.",
        args: [name],
        name: "memberFindUnbanPrompt",
        desc: "Member list: confirmation before lifting a ban from a find "
            "result",
      );

  static String get memberFindJoined => Intl.message(
        "Joined",
        name: "memberFindJoined",
        desc: "Member list: chip showing members who joined",
      );

  static String get memberFindInvited => Intl.message(
        "Invited",
        name: "memberFindInvited",
        desc: "Member list: chip showing invited members",
      );

  static String get memberFindLeft => Intl.message(
        "Left",
        name: "memberFindLeft",
        desc: "Member list: chip showing members who left",
      );

  static String chip(MemberMembership membership) => switch (membership) {
        MemberMembership.joined => memberFindJoined,
        MemberMembership.invited => memberFindInvited,
        MemberMembership.banned => memberFindBanned,
        MemberMembership.left => memberFindLeft,
      };
}

/// The row: the find box, and the square invite button when [onInvite] is
/// set (people allowed to invite); without it the box is full width.
class MemberFindRow extends StatelessWidget {
  const MemberFindRow({
    required this.controller,
    required this.focusNode,
    required this.memberCount,
    this.onInvite,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final int memberCount;
  final VoidCallback? onInvite;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(10);
    return Container(
      height: height,
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    controller.clear,
              },
              child: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, _) => TextField(
                  key: const ValueKey("member-panel-find"),
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerLowest,
                    hintText: MemberFindStrings.memberFindIn(
                      MemberFindStrings.formatCount(memberCount),
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey("member-panel-find-clear"),
                            tooltip: MemberFindStrings.memberFindClear,
                            iconSize: 18,
                            icon: const Icon(Icons.close),
                            onPressed: controller.clear,
                          ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: radius,
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: radius,
                      borderSide: BorderSide(color: scheme.primary),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onInvite != null) ...[
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: 40,
              child: Tooltip(
                message: MemberFindStrings.memberFindInviteMembers,
                child: Material(
                  key: const ValueKey("member-panel-invite-button"),
                  color: scheme.surfaceContainerHigh,
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    onTap: onInvite,
                    child: Icon(
                      Icons.person_add_alt_1,
                      size: 20,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pins [MemberFindRow] under the tab strip while the list scrolls.
class MemberFindHeaderDelegate extends SliverPersistentHeaderDelegate {
  MemberFindHeaderDelegate(this.child);
  final Widget child;

  @override
  double get minExtent => MemberFindRow.height;
  @override
  double get maxExtent => MemberFindRow.height;

  @override
  Widget build(context, shrinkOffset, overlapsContent) => child;

  @override
  bool shouldRebuild(MemberFindHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}

/// [text] with [range] bold on a translucent amber background.
class MemberFindHighlight extends StatelessWidget {
  const MemberFindHighlight(
    this.text, {
    required this.range,
    this.style,
    super.key,
  });
  final String text;
  final TextRange? range;
  final TextStyle? style;

  static TextStyle highlightStyle(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.amber.withValues(alpha: 0.3),
      );

  @override
  Widget build(BuildContext context) {
    final r = range;
    if (r == null || r.end > text.length) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: r.textBefore(text)),
          TextSpan(text: r.textInside(text), style: highlightStyle(style)),
          TextSpan(text: r.textAfter(text)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
