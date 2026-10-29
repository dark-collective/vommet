import 'dart:async';

import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/matrix/components/invitation/invite_details.dart';
import 'package:commet/client/matrix/components/invitation/matrix_invitation_component.dart';
import 'package:commet/client/matrix/components/invitation/matrix_invite_preview.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/decline_and_block_sheet.dart';
import 'package:commet/ui/organisms/invitation_view/invite_strings.dart';
import 'package:commet/ui/organisms/space_join_picker/space_join_picker.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const Color _amber = Color(0xfff0b232);

/// Vommet: an invite opened from Home › Invitations. On a phone it's a page
/// of its own; on desktop it fills the Home pane ([InvitePreviewHost]).
/// Shows only what the invite carries plus what the server answers; member
/// count and a space's rooms are left out when the server won't say.
class InvitePreviewPage extends StatefulWidget {
  const InvitePreviewPage(
      {required this.client,
      required this.component,
      required this.invitation,
      this.onClose,
      super.key});

  final MatrixClient client;
  final InvitationComponent component;
  final Invitation invitation;

  /// Closes the page (pops the route on phones).
  final VoidCallback? onClose;

  /// Opens [invitation]: in the Home pane on desktop, as a page on phones.
  static void open(BuildContext context,
      {required InvitationComponent component,
      required Invitation invitation}) {
    final client = component.client;
    if (client is! MatrixClient) return;
    if (MediaQuery.of(context).desktop &&
        InvitePreviewHost.show(client, component, invitation)) {
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (routeContext) => Scaffold(
        body: InvitePreviewPage(
          client: client,
          component: component,
          invitation: invitation,
          onClose: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    ));
  }

  @override
  State<InvitePreviewPage> createState() => _InvitePreviewPageState();
}

class _InvitePreviewPageState extends State<InvitePreviewPage> {
  late MatrixInvitePreview preview;
  late InviteDetails details;

  int? memberCount;
  InviteSpaceChildren? spaceRooms;
  List<String>? sharedRooms;

  bool busy = false;
  bool _closed = false;
  StreamSubscription? _listSub;

  /// Vommet issue 734: on a grouped space invite, the ticked rooms and
  /// whether to join the space itself. Rooms that join the group later
  /// start ticked.
  final Set<String> picked = {};
  final Set<String> _offered = {};
  bool joinSpace = true;

  Invitation get invitation => widget.invitation;
  bool get isGroup => invitation.isGroup;

  void _syncPicked() {
    final ids = {for (final r in invitation.groupedRooms) r.roomId};
    picked.removeWhere((id) => !ids.contains(id));
    _offered.removeWhere((id) => !ids.contains(id));
    for (final id in ids) {
      if (_offered.add(id)) picked.add(id);
    }
  }

  /// Closes once, whether we declined here or the invite went elsewhere.
  void _close() {
    if (_closed) return;
    _closed = true;
    widget.onClose?.call();
  }

  @override
  void initState() {
    super.initState();
    preview = MatrixInvitePreview(widget.client);
    details = preview.details(widget.invitation.roomId,
        fallbackInviterId: widget.invitation.senderId ??
            (isGroup ? invitation.groupedRooms.first.senderId : null));
    _syncPicked();
    _load();
    // Accepted or declined somewhere else: nothing left to show.
    _listSub = widget.component.invitations.onListUpdated.listen((_) {
      if (!widget.component.invitations
          .any((i) => identical(i, widget.invitation))) {
        _close();
      } else if (mounted) {
        setState(_syncPicked);
      }
    });
  }

  @override
  void dispose() {
    _listSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final inviter = details.inviterId;
    if (inviter != null) {
      preview
          .sharedRoomNames(inviter, excludeRoomId: details.roomId)
          .then((names) {
        if (mounted) setState(() => sharedRooms = names);
      });
    }
    if (details.isDirect) return;
    if (details.isSpace) {
      final (rooms, members) = await preview.spaceChildren(details.roomId);
      if (!mounted) return;
      setState(() {
        spaceRooms = rooms;
        memberCount = members;
      });
    }
    if (memberCount == null) {
      final count = await preview.memberCount(details);
      if (mounted && count != null) setState(() => memberCount = count);
    }
  }

  // ------------------------------------------------------------- naming

  String get inviterName =>
      details.inviterDisplayName ??
      _localpart(details.inviterId) ??
      widget.invitation.senderId ??
      "";

  static String? _localpart(String? id) {
    if (id == null || !id.startsWith("@") || !id.contains(":")) return null;
    return id.substring(1, id.indexOf(":"));
  }

  String get roomName {
    if (details.isDirect && details.name == null) return inviterName;
    return details.name ??
        widget.invitation.displayName ??
        details.canonicalAlias ??
        details.roomId;
  }

  ImageProvider? get inviterAvatar {
    final url = details.inviterAvatarUrl;
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != "mxc") return null;
    return MatrixMxcImage(uri, widget.client.matrixClient,
        autoLoadFullRes: false);
  }

  Color get inviterColor => MatrixPeer.hashColor(details.inviterId ?? "");

  // ------------------------------------------------------------- actions

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _accept() => _run(() async {
        try {
          final component = widget.component;
          if (isGroup && component is MatrixInvitationComponent) {
            await component.acceptGroup(invitation,
                joinSpace: joinSpace, roomIds: Set.of(picked));
          } else {
            await widget.component.acceptInvitation(widget.invitation);
          }
          _close();
        } catch (e, s) {
          Log.onError(e, s, content: "Could not accept the invitation");
          if (mounted) AdaptiveDialog.showError(context, e, s);
        }
      });

  Future<void> _decline() => _run(() async {
        try {
          await widget.component.rejectInvitation(widget.invitation);
          _close();
        } catch (e, s) {
          Log.onError(e, s, content: "Could not decline the invitation");
          if (mounted) AdaptiveDialog.showError(context, e, s);
        }
      });

  Future<void> _declineAndBlock() async {
    final choice = await DeclineAndBlockSheet.show(context,
        roomName: roomName,
        inviterId: details.inviterId,
        inviterServer: details.inviterServer,
        ownServer: preview.ownServer);
    if (choice == null || !mounted) return;

    await _run(() async {
      final problems = <String>[];
      final inviter = details.inviterId;

      // Report first: the server only takes it while it knows the room.
      if (choice.reportRoom) {
        try {
          await preview.reportRoom(
              details.roomId, inviteReportReason(inviter ?? roomName));
        } catch (e) {
          Log.w("Room report failed: $e");
          problems.add(inviteReportFailed);
        }
      }

      try {
        await widget.component.rejectInvitation(widget.invitation);
      } catch (e, s) {
        Log.onError(e, s, content: "Could not decline the invitation");
        problems.add(inviteDeclineFailed);
      }

      var blockFailed = false;
      if (choice.blockUser && inviter != null) {
        try {
          final blocking = widget.client.getComponent<UserBlockingComponent>();
          if (blocking == null) throw StateError("no blocking component");
          await blocking.block(inviter);
        } catch (e, s) {
          Log.onError(e, s, content: "Could not block the inviter");
          blockFailed = true;
        }
      }
      if (choice.blockServer && details.inviterServer != null) {
        try {
          await preview.blockServer(details.inviterServer!);
        } catch (e, s) {
          Log.onError(e, s, content: "Could not block the inviter's server");
          blockFailed = true;
        }
      }
      if (blockFailed) problems.add(inviteBlockFailed);

      if (problems.isNotEmpty && mounted) {
        await AdaptiveDialog.show(context,
            title: inviteSomethingFailed,
            builder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in problems)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: tiamat.Text.label(p),
                      ),
                  ],
                ));
      }
      if (!problems.contains(inviteDeclineFailed)) _close();
    });
  }

  void _openInviter() {
    final id = details.inviterId;
    if (id == null) return;
    UserProfile.show(context, client: widget.client, userId: id);
  }

  // ------------------------------------------------------------- pieces

  Widget _chip(IconData icon, String text) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withAlpha(30), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(text,
            style:
                TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  List<Widget> _roomChips() => [
        if (details.isSpace) _chip(Icons.workspaces_outline, inviteChipSpace),
        if (memberCount != null)
          _chip(Icons.people_outline, inviteChipMembers(memberCount!)),
        details.encrypted
            ? _chip(Icons.lock_outline, inviteChipEncrypted)
            : _chip(Icons.no_encryption_outlined, inviteChipNotEncrypted),
        switch (details.joinRule) {
          "public" => _chip(Icons.public, inviteChipPublic),
          "knock" ||
          "knock_restricted" =>
            _chip(Icons.front_hand_outlined, inviteChipAskToJoin),
          "restricted" => _chip(Icons.group_outlined, inviteChipSpaceMembers),
          _ => _chip(Icons.mail_lock_outlined, inviteChipInviteOnly),
        },
      ];

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10)),
        child: child,
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _fact(IconData icon, String text, {Color? color}) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon,
            size: 16,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: c))),
      ]),
    );
  }

  /// "You're both in …", or the amber warning. Nothing while loading.
  Widget? _sharedFact() {
    final names = sharedRooms;
    if (names == null) return null;
    if (names.isEmpty) {
      return _fact(Icons.person_search_outlined, inviteNoSharedRooms,
          color: _amber);
    }
    final shown = names.take(3).join(", ");
    return _fact(Icons.groups_2_outlined,
        inviteSharedRooms(names.length, names.length > 3 ? "$shown…" : shown),
        color: Theme.of(context).colorScheme.onSurfaceVariant);
  }

  Widget _roomAvatar(double size) {
    final image = widget.invitation.avatar;
    final color =
        widget.invitation.color ?? MatrixPeer.hashColor(details.roomId);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4.4),
      child: SizedBox(
        width: size,
        height: size,
        child: image != null
            ? Image(image: image, fit: BoxFit.cover)
            : Container(
                color: color,
                alignment: Alignment.center,
                child: Text(
                  roomName.isEmpty
                      ? "?"
                      : roomName.characters.first.toUpperCase(),
                  style: TextStyle(
                      fontSize: size * 0.45,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
      ),
    );
  }

  Widget _inviterCard() {
    final scheme = Theme.of(context).colorScheme;
    final shared = _sharedFact();
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        key: const ValueKey("invite-inviter-card"),
        borderRadius: BorderRadius.circular(10),
        onTap: details.inviterId == null ? null : _openInviter,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              tiamat.Avatar(
                  radius: 18,
                  image: inviterAvatar,
                  placeholderText: inviterName,
                  placeholderColor: inviterColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: inviteInvitedBy,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                        TextSpan(
                            text: inviterName,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface)),
                      ])),
                      if (details.inviterId != null &&
                          details.inviterId != inviterName)
                        Text(details.inviterId!,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                    ]),
              ),
              if (details.inviterId != null)
                Icon(Icons.chevron_right,
                    color: scheme.onSurfaceVariant.withAlpha(140)),
            ]),
            if (details.reason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(
                            color: scheme.onSurfaceVariant, width: 3))),
                child: Text("“${details.reason}”",
                    style: TextStyle(fontSize: 13.5, color: scheme.onSurface)),
              ),
            ],
            if (shared != null) ...[const SizedBox(height: 8), shared],
          ]),
        ),
      ),
    );
  }

  Widget? _spaceRoomsBox() {
    final rooms = spaceRooms;
    if (rooms == null || rooms.rooms.isEmpty) return null;
    const shownMax = 4;
    return _box(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(rooms.complete
            ? inviteInsideRooms(rooms.rooms.length)
            : inviteInside),
        for (final (name, type) in rooms.rooms.take(shownMax))
          _fact(
              switch (type) {
                "m.space" => Icons.workspaces_outline,
                "org.matrix.msc3417.call" => Icons.headphones,
                _ => Icons.tag,
              },
              name),
        if (rooms.complete && rooms.rooms.length > shownMax)
          Text(inviteMoreRooms(rooms.rooms.length - shownMax),
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ));
  }

  /// Vommet issue 734: tick boxes for the space and the rooms whose
  /// invites came with it.
  Widget? _groupBox() {
    if (!isGroup) return null;
    final scheme = Theme.of(context).colorScheme;
    Widget tick(String key, bool value, ValueChanged<bool> onChanged,
            Widget icon, String name,
            {bool bold = false}) =>
        InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(8),
          onTap: busy ? null : () => setState(() => onChanged(!value)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Checkbox(
                  value: value,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => onChanged(v ?? false))),
              icon,
              const SizedBox(width: 8),
              Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: bold ? FontWeight.w600 : null,
                          color: value
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant))),
            ]),
          ),
        );
    Widget pill(String key, String text, VoidCallback onTap) => TextButton(
        key: ValueKey(key),
        onPressed: busy ? null : () => setState(onTap),
        child: Text(text, style: const TextStyle(fontSize: 12.5)));

    final rooms = invitation.groupedRooms;
    return _box(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: _label(inviteGroupPickHeader)),
          pill("invite-group-all", spaceJoinSelectAll, () {
            picked.addAll(rooms.map((r) => r.roomId));
            joinSpace = true;
          }),
          pill("invite-group-none", spaceJoinSelectNone, picked.clear),
        ]),
        if (invitation.spaceJoined)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _fact(Icons.check_circle_outline, inviteGroupAlreadyMember),
          )
        else
          tick(
              "invite-group-space",
              joinSpace,
              (v) => joinSpace = v,
              const Icon(Icons.workspaces_outline, size: 18),
              inviteGroupSpaceRow,
              bold: true),
        for (final room in rooms)
          tick(
              "invite-group-room-${room.roomId}",
              picked.contains(room.roomId),
              (v) => v ? picked.add(room.roomId) : picked.remove(room.roomId),
              tiamat.Avatar(
                  radius: 10,
                  image: room.avatar,
                  placeholderText: room.displayName ?? room.roomId,
                  placeholderColor: room.color),
              room.displayName ?? room.roomId),
        const SizedBox(height: 4),
        Text(inviteGroupUntickedNote,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    ));
  }

  Widget _dmFacts() {
    final inviter = details.inviterId;
    final shared = _sharedFact();
    final (hadChat, haveChat) = inviter == null
        ? (false, false)
        : preview.directChatsWith(inviter, excludeRoomId: details.roomId);
    final verified = inviter != null && preview.isVerified(inviter);
    return _box(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(inviteWhatYouKnow),
        if (shared != null) shared,
        _fact(
            Icons.history,
            haveChat
                ? inviteHaveChat
                : hadChat
                    ? inviteHadChatBefore
                    : inviteNeverMessaged),
        _fact(verified ? Icons.verified_user : Icons.verified_user_outlined,
            verified ? inviteVerified : inviteNotVerified),
      ],
    ));
  }

  Widget _note(String text) => Text(text,
      textAlign: TextAlign.center,
      style: TextStyle(
          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant));

  Widget _blockLink() {
    final red = Theme.of(context).colorScheme.error;
    return TextButton(
      key: const ValueKey("invite-decline-and-block"),
      onPressed: busy ? null : _declineAndBlock,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 15, color: red),
        const SizedBox(width: 6),
        Text(inviteDeclineAndBlockLink,
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: red)),
        Icon(Icons.arrow_drop_down, size: 18, color: red),
      ]),
    );
  }

  Widget _declineButton() => SizedBox(
        height: 40,
        child: tiamat.Button.secondary(
            key: const ValueKey("invite-decline"),
            text: isGroup ? inviteDeclineAll : inviteDecline,
            onTap: busy ? null : _decline),
      );

  Widget _acceptButton() => SizedBox(
        height: 40,
        child: tiamat.Button(
            key: const ValueKey("invite-accept"),
            text: _acceptText,
            isLoading: busy,
            onTap: busy || (isGroup && !_groupHasWork) ? null : _accept),
      );

  bool get _groupHasWork =>
      picked.isNotEmpty || (joinSpace && !invitation.spaceJoined);

  String get _acceptText {
    if (!isGroup) return details.isSpace ? inviteJoinSpace : inviteAccept;
    if (joinSpace && !invitation.spaceJoined) {
      return inviteJoinSpaceAndRooms(picked.length);
    }
    return inviteJoinRooms(picked.length);
  }

  // ------------------------------------------------------------- layouts

  Widget _titleBlock({required bool centered}) {
    final scheme = Theme.of(context).colorScheme;
    final align =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    if (details.isDirect) {
      return Column(crossAxisAlignment: align, children: [
        tiamat.Avatar(
            radius: 40,
            image: inviterAvatar,
            placeholderText: inviterName,
            placeholderColor: inviterColor),
        const SizedBox(height: 12),
        tiamat.Text.largeTitle(inviterName),
        if (details.inviterId != null && details.inviterId != inviterName)
          Text(details.inviterId!,
              textAlign: textAlign,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text(inviteWantsDm,
            textAlign: textAlign,
            style: TextStyle(fontSize: 14, color: scheme.onSurface)),
      ]);
    }
    return Column(crossAxisAlignment: align, children: [
      _roomAvatar(80),
      const SizedBox(height: 12),
      tiamat.Text.largeTitle(roomName),
      if (details.canonicalAlias != null)
        Text(details.canonicalAlias!,
            textAlign: textAlign,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
    ]);
  }

  List<Widget> _chips() => details.isDirect
      ? [
          details.encrypted
              ? _chip(Icons.lock_outline, inviteChipEncrypted)
              : _chip(Icons.no_encryption_outlined, inviteChipNotEncrypted),
          if (details.inviterServer != null)
            _chip(Icons.dns_outlined, details.inviterServer!),
        ]
      : _roomChips();

  Widget _topic({required bool centered}) => Text(details.topic!,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      maxLines: 8,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 14, color: Theme.of(context).colorScheme.onSurface));

  Widget _narrow() {
    final rooms = _spaceRoomsBox();
    final group = _groupBox();
    return Column(children: [
      _appBar(),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titleBlock(centered: true),
              const SizedBox(height: 10),
              Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: _chips()),
              if (!details.isDirect && details.topic != null) ...[
                const SizedBox(height: 14),
                _topic(centered: true),
              ],
              const SizedBox(height: 16),
              if (details.isDirect) ...[
                _dmFacts(),
                const SizedBox(height: 10),
                _box(Row(children: [
                  Icon(Icons.mark_email_unread_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(inviteDmHiddenNote,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant))),
                ])),
              ] else ...[
                _inviterCard(),
                if (group != null) ...[const SizedBox(height: 10), group],
                if (rooms != null) ...[const SizedBox(height: 10), rooms],
                const SizedBox(height: 10),
                _note(inviteNothingShared),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: _declineButton()),
            const SizedBox(width: 10),
            Expanded(child: _acceptButton()),
          ]),
          if (!invitation.spaceJoined) ...[
            const SizedBox(height: 4),
            Center(child: _blockLink()),
          ],
        ]),
      ),
    ]);
  }

  Widget _appBar() => SizedBox(
        height: 52,
        child: Row(children: [
          IconButton(
            key: const ValueKey("invite-back"),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _close,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: tiamat.Text.labelEmphasised(
                details.isDirect ? inviteMessageRequestTitle : invitePageTitle),
          ),
        ]),
      );

  /// Desktop: header beside the avatar, the cards side by side.
  Widget _wide() {
    final rooms = _spaceRoomsBox();
    final group = _groupBox();
    final left = details.isDirect ? _dmFacts() : _inviterCard();
    final right = details.isDirect
        ? _box(Row(children: [
            Icon(Icons.mark_email_unread_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
                child: Text(inviteDmHiddenNote,
                    style: TextStyle(
                        fontSize: 12.5,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant))),
          ]))
        : rooms;
    return Stack(children: [
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (details.isDirect)
                    tiamat.Avatar(
                        radius: 28,
                        image: inviterAvatar,
                        placeholderText: inviterName,
                        placeholderColor: inviterColor)
                  else
                    _roomAvatar(56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          tiamat.Text.largeTitle(
                              details.isDirect ? inviterName : roomName),
                          if (details.isDirect)
                            Text("${details.inviterId ?? ""} · $inviteWantsDm",
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant))
                          else if (details.canonicalAlias != null)
                            Text(details.canonicalAlias!,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                        ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: _chips()),
                if (!details.isDirect && details.topic != null) ...[
                  const SizedBox(height: 12),
                  _topic(centered: false),
                ],
                const SizedBox(height: 16),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: left),
                      if (right != null) ...[
                        const SizedBox(width: 12),
                        Expanded(child: right),
                      ],
                    ],
                  ),
                ),
                if (group != null) ...[
                  const SizedBox(height: 12),
                  group,
                ],
                if (!details.isDirect) ...[
                  const SizedBox(height: 10),
                  _note(inviteNothingShared),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  if (!invitation.spaceJoined) _blockLink(),
                  const Spacer(),
                  SizedBox(width: 160, child: _declineButton()),
                  const SizedBox(width: 10),
                  SizedBox(width: 210, child: _acceptButton()),
                ]),
              ],
            ),
          ),
        ),
      ),
      Positioned(
        top: 8,
        left: 8,
        child: IconButton(
          key: const ValueKey("invite-back"),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _close,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ScaledSafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= 720 ? _wide() : _narrow(),
      ),
    );
  }
}

/// Vommet: on desktop an opened invite replaces the Home pane's content
/// (where a room would open) until it's closed.
class InvitePreviewHost extends StatefulWidget {
  const InvitePreviewHost({required this.child, super.key});
  final Widget child;

  static final ValueNotifier<(MatrixClient, InvitationComponent, Invitation)?>
      _open = ValueNotifier(null);

  static int _hosts = 0;

  /// Shows the invite in the Home pane. False when no Home pane is on
  /// screen (the caller then opens it as a page).
  static bool show(MatrixClient client, InvitationComponent component,
      Invitation invitation) {
    if (_hosts == 0) return false;
    _open.value = (client, component, invitation);
    return true;
  }

  @override
  State<InvitePreviewHost> createState() => _InvitePreviewHostState();
}

class _InvitePreviewHostState extends State<InvitePreviewHost> {
  @override
  void initState() {
    super.initState();
    InvitePreviewHost._hosts++;
  }

  @override
  void dispose() {
    InvitePreviewHost._hosts--;
    // Leaving Home (e.g. opening a room) closes the invite.
    if (InvitePreviewHost._hosts == 0) InvitePreviewHost._open.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: InvitePreviewHost._open,
      builder: (context, open, child) {
        if (open == null || !MediaQuery.of(context).desktop) return child!;
        final (client, component, invitation) = open;
        return InvitePreviewPage(
          key: ValueKey("invite-preview-${invitation.roomId}"),
          client: client,
          component: component,
          invitation: invitation,
          onClose: () => InvitePreviewHost._open.value = null,
        );
      },
      child: widget.child,
    );
  }
}
