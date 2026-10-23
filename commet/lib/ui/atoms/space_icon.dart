import 'dart:async';

import 'package:commet/client/space.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/banned_space_icon.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';

class SpaceIcon extends StatefulWidget {
  const SpaceIcon(
      {super.key,
      this.width = 44,
      this.onTap,
      this.showUser = false,
      this.selectionBorder = true,
      this.onUpdate,
      required this.spaceId,
      required this.clientId,
      this.avatar,
      this.placeholderColor,
      this.notificationCount = 0,
      this.highlightedNotificationCount = 0,
      required this.displayName,
      this.userAvatar,
      this.userDisplayName,
      this.userColor,
      this.callBadge});
  final double width;
  final void Function()? onTap;
  final bool showUser;

  /// Vommet: false on the sidebar rail, where a pill marks the selected
  /// space instead (see RailSlot).
  final bool selectionBorder;
  final String spaceId;
  final String clientId;
  final Stream<void>? onUpdate;
  final String displayName;
  final Color? placeholderColor;
  final int notificationCount;
  final int highlightedNotificationCount;
  final ImageProvider? avatar;
  final ImageProvider? userAvatar;
  final String? userDisplayName;
  final Color? userColor;

  /// Vommet: the space's call mark (see SpaceCallBadge), bottom-right, or
  /// bottom-left when the account's avatar takes that corner.
  final Widget? callBadge;

  @override
  State<SpaceIcon> createState() => _SpaceIconState();
}

class _SpaceIconState extends State<SpaceIcon> {
  StreamSubscription? subscription;
  StreamSubscription? spaceSelectionSub;
  @override
  void initState() {
    subscription = widget.onUpdate?.listen((event) {
      setState(() {});
    });

    spaceSelectionSub =
        EventBus.onSelectedSpaceChanged.stream.listen(onSelectedSpaceChanged);

    super.initState();
  }

  bool selected = false;

  void onSelectedSpaceChanged(Space? event) {
    setState(() {
      selected = event?.identifier == widget.spaceId &&
          event?.client.identifier == widget.clientId;
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    spaceSelectionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vommet: a space we were banned from is faded, with a ban mark
    final space =
        clientManager?.getClient(widget.clientId)?.getSpace(widget.spaceId);
    // Vommet: the space's current avatar, not the one the icon was built
    // with. A space whose avatar state arrived after the rail was built
    // (first load in a browser) stayed a blank square: onUpdate rebuilt the
    // icon with the parent's stale null.
    final avatar = space != null ? space.avatar : widget.avatar;
    if (space?.isBanned == true) {
      return BannedSpaceIcon(buildIcon(context, avatar));
    }
    return buildIcon(context, avatar);
  }

  Widget buildIcon(BuildContext context, ImageProvider? avatar) {
    // Vommet: redacted mode hides the picture and name (Vommet issue 400).
    final redaction = RedactionScope.of(context);
    final hidden = redaction.hidesAvatars;
    final letter = redaction.avatarLetter(widget.spaceId);
    return Stack(children: [
      AspectRatio(
        aspectRatio: 1.0,
        child: ImageButton(
          border: selected && widget.selectionBorder
              ? Border.all(
                  color: ColorScheme.of(context).inverseSurface,
                  width: 3,
                  strokeAlign: 0.5)
              : null,
          image: hidden ? null : avatar,
          onTap: widget.onTap,
          size: widget.width,
          placeholderColor: hidden
              ? redaction.identityColor(widget.spaceId)
              : widget.placeholderColor,
          placeholderText: hidden
              ? (letter.isEmpty ? " " : letter)
              : redaction.roomName(widget.displayName, widget.spaceId),
        ),
      ),
      if (widget.showUser) avatarOverlay(),
      if (widget.callBadge != null)
        Positioned(
          right: widget.showUser ? null : 0,
          left: widget.showUser ? 0 : null,
          bottom: 0,
          child: IgnorePointer(child: widget.callBadge!),
        ),
      if (widget.highlightedNotificationCount > 0) notificationOverlay(),
    ]);
  }

  Positioned avatarOverlay() {
    return Positioned(
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 20,
          height: 20,
          child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black, blurRadius: 4)
                ],
              ),
              child: Avatar(
                radius: 10,
                image: widget.userAvatar,
                placeholderColor: widget.userColor,
                placeholderText: widget.userDisplayName,
              )),
        ),
      ),
    );
  }

  Positioned notificationOverlay() {
    return Positioned(
      right: 0,
      top: 0,
      child: NotificationBadge(widget.highlightedNotificationCount),
    );
  }

  Positioned messageOverlay() {
    return Positioned(
      left: 0,
      child: SizedBox(
        width: 8,
        height: 8,
        child: DecoratedBox(
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface,
              borderRadius: BorderRadius.circular(5)),
        ),
      ),
    );
  }
}
