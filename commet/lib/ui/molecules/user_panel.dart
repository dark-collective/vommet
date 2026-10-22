import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/atoms/shimmer_loading.dart';
import 'package:commet/ui/molecules/member_subtitle.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UserPanel extends material.StatefulWidget {
  const UserPanel(
      {super.key,
      required this.userId,
      required this.client,
      required this.contextRoom,
      this.initialMember,
      this.isDirectMessage = false,
      this.activity,
      this.memberList = false,
      this.onTap});
  final String userId;

  /// Vommet: a row of the room's member list, which follows Settings ›
  /// Appearance › Member list and falls back to the profile's status.
  final bool memberList;

  /// Vommet: what the member is doing in the room's call, shown under the
  /// name like Discord's "In voice".
  final MemberActivity? activity;
  final Client client;
  final Member? initialMember;
  final Room contextRoom;
  final bool isDirectMessage;
  final void Function()? onTap;

  @override
  State<UserPanel> createState() => _UserPanelState();
}

class _UserPanelState extends material.State<UserPanel> {
  late String displayName;
  late Color color;
  ImageProvider? avatar;
  String? detail;
  TextStyle? detailStringStyle;
  late UserPresence presence;

  // Vommet: the status kept in the profile (chat.commet.profile_status),
  // for people whose presence carries none.
  String? profileStatus;

  StreamSubscription? sub;

  @override
  initState() {
    presence = UserPresence(UserPresenceStatus.unknown);

    super.initState();
    initPresence();
    getInfoFromMember();
  }

  void getInfoFromMember() {
    if (widget.isDirectMessage) {
      displayName = widget.contextRoom.displayName;
      color = widget.contextRoom.defaultColor;
      avatar = widget.contextRoom.avatar;
      return;
    }

    final member = widget.initialMember ??
        widget.contextRoom.getMemberOrFallback(widget.userId);
    displayName = member.displayName;
    color = member.defaultColor;
    avatar = member.avatar;
    detail = member.detail;
  }

  @override
  void didUpdateWidget(covariant UserPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    getInfoFromMember();
  }

  @override
  dispose() {
    super.dispose();
    sub?.cancel();
  }

  initPresence() async {
    final presenceComponent =
        widget.client.getComponent<UserPresenceComponent>();

    if (presenceComponent == null) {
      return;
    }

    sub = presenceComponent.onPresenceChanged
        .where((tuple) => tuple.$1 == widget.userId)
        .listen(onChanged);

    final p = await presenceComponent.getUserPresence(widget.userId);

    if (mounted) {
      setState(() {
        presence = p;
      });
      if (widget.memberList && p.message == null) loadProfileStatus();
    }
  }

  /// Vommet: the profile card falls back to the profile's status; the
  /// member list does too. Profiles are cached, and rows are built lazily,
  /// so only visible members are looked up.
  Future<void> loadProfileStatus() async {
    if (MemberListSubtitle.current == MemberListSubtitle.statusOff) return;
    final profiles = widget.client.getComponent<UserProfileComponent>();
    if (profiles == null) return;
    try {
      final profile = await profiles.getProfile(widget.userId);
      // Profile and ProfileWithPresence are unrelated, so no promotion.
      final message = profile is ProfileWithPresence
          ? (profile as ProfileWithPresence).precence?.message?.message
          : null;
      if (mounted && message != null && message.trim().isNotEmpty) {
        setState(() => profileStatus = message);
      }
    } catch (_) {
      // No profile: the row keeps the homeserver.
    }
  }

  /// The presence the row shows: the profile's status when presence has
  /// none, and no status at all with "Status off".
  UserPresence get shownPresence {
    if (!widget.memberList) return presence;
    if (MemberListSubtitle.current == MemberListSubtitle.statusOff) {
      return UserPresence(presence.status);
    }
    final status = profileStatus;
    if (presence.message == null && status != null) {
      return UserPresence(presence.status,
          message: UserPresenceMessage(status, PresenceMessageType.userCustom));
    }
    return presence;
  }

  @override
  material.Widget build(material.BuildContext context) {
    TextStyle? style;

    var currentStyle = material.Theme.of(context).textTheme.bodyMedium;
    style = currentStyle?.copyWith(fontSize: 10);
    final presence = shownPresence;

    if (presence.message != null) {
      style = style?.copyWith(
        fontWeight: FontWeight.w500,
      );
    } else {
      style = style?.copyWith(
        color: Theme.of(context).colorScheme.secondary,
      );
    }

    return UserPanelView(
      displayName: displayName,
      userId: widget.userId,
      avatar: avatar,
      detail: detail,
      detailStringStyle: style,
      color: color,
      avatarColor: color,
      nameColor: widget.isDirectMessage ? null : color,
      avatarSize: widget.isDirectMessage ? 20 : 15,
      presence: presence,
      activity: widget.activity,
      subtitle: widget.memberList ? MemberListSubtitle.current : null,
      onClicked: widget.onTap ?? onUserPanelClicked,
    );
  }

  void onUserPanelClicked() {
    UserProfile.show(context, client: widget.client, userId: widget.userId);
  }

  void onChanged((String, UserPresence) event) {
    if (mounted) {
      setState(() {
        presence = event.$2;
      });
    }
  }
}

class UserPanelView extends material.StatelessWidget {
  const UserPanelView(
      {super.key,
      this.avatar,
      required this.displayName,
      this.color,
      this.avatarColor,
      this.nameColor,
      this.detail,
      this.padding,
      this.shimmer = false,
      this.random = 0,
      this.detailStringStyle,
      this.presence,
      this.activity,
      this.subtitle,
      this.avatarSize = 15,
      this.userId,
      this.onClicked});
  final ImageProvider? avatar;
  final String displayName;

  /// Who this is, for redacted mode. Falls back to [displayName].
  final String? userId;
  final double avatarSize;
  final Color? color;
  final Color? avatarColor;
  final Color? nameColor;
  final String? detail;
  final EdgeInsets? padding;
  final UserPresence? presence;
  final MemberActivity? activity;

  /// Vommet: the member list's layout under the name; null keeps the
  /// original (status, else homeserver).
  final MemberListSubtitle? subtitle;
  final bool shimmer;
  final TextStyle? detailStringStyle;
  final double random;
  final void Function()? onClicked;

  @override
  Widget build(BuildContext context) {
    var shimmerColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final redaction = RedactionScope.of(context);
    final id = userId ?? this.displayName;
    final displayName = redaction.name(this.displayName, id);
    final nameColor = this.nameColor == null
        ? null
        : redaction.nameColor(this.nameColor!, id);
    // The detail line is usually the user ID.
    final detail = redaction.redactsNames ? null : this.detail;

    var widget = ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: material.Material(
        color: material.Colors.transparent,
        child: material.InkWell(
          splashColor: material.Theme.of(context).highlightColor,
          onTap: onClicked,
          child: Padding(
            padding: padding ?? const EdgeInsets.fromLTRB(4, 2, 4, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                material.Stack(
                  alignment: AlignmentGeometry.bottomRight,
                  children: [
                    Avatar(
                      radius: avatarSize,
                      image: shimmer ? null : avatar,
                      placeholderText: shimmer ? " " : displayName,
                      placeholderColor: shimmer ? shimmerColor : avatarColor,
                      redactionKey: id,
                    ),
                    if (presence?.status != null)
                      createPresenceIcon(context, presence!.status),
                  ],
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                    child: Container(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: material.MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (shimmer)
                            Container(
                              height: 10,
                              width: (random * 50) + 50,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: shimmerColor),
                            ),
                          if (shimmer)
                            material.Padding(
                              padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                              child: Container(
                                height: 8,
                                width: (random * 20) + 20,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: shimmerColor),
                              ),
                            ),
                          if (!shimmer)
                            tiamat.Text.name(
                              displayName,
                              color: nameColor,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (subtitle ==
                              MemberListSubtitle.homeserverAndStatus)
                            serverAndStatusRow(context)
                          else if (activity != null)
                            activityRow(context),
                          if (subtitle !=
                                  MemberListSubtitle.homeserverAndStatus &&
                              activity == null &&
                              presence?.message != null)
                            material.Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (presence!.message?.messageType ==
                                    PresenceMessageType.userCustom)
                                  material.Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(0, 0, 4, 0),
                                    child: Icon(
                                      Icons.chat_bubble,
                                      size: 10,
                                    ),
                                  ),
                                Flexible(
                                  child: material.Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(0, 0, 0, 2),
                                      child: statusText(
                                          context,
                                          redaction.text(
                                              presence!.message!.message))),
                                ),
                              ],
                            ),
                          if (subtitle !=
                                  MemberListSubtitle.homeserverAndStatus &&
                              activity == null &&
                              presence?.message == null &&
                              detail != null)
                            material.Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: material.Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(0, 0, 0, 2),
                                    child: buildDetailString(detail),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );

    if (shimmer) {
      return ShimmerLoading(isLoading: true, child: widget);
    }

    return widget;
  }

  /// Vommet: a status, cut with "…"; on desktop, hovering shows all of it.
  material.Widget statusText(material.BuildContext context, String message) {
    final text = material.Text(
      message,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      style: detailStringStyle,
    );
    if (!MediaQuery.of(context).desktop) return text;
    return material.Tooltip(message: message, child: text);
  }

  /// Vommet: "Homeserver and status": the homeserver (at most 20
  /// characters), then the status bubble, or the speaker in voice, and the
  /// status in what's left of the line.
  material.Widget serverAndStatusRow(material.BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final green = Colors.green.shade400;
    final redaction = RedactionScope.of(context);
    final message = presence?.message?.message == null
        ? null
        : redaction.text(presence!.message!.message);
    // The homeserver is part of the user ID.
    final detail = redaction.redactsNames ? null : this.detail;
    final server =
        detail == null || detail.isEmpty ? null : shortServerName(detail);
    final serverStyle = detailStringStyle?.copyWith(
        fontFamily: "Code",
        fontWeight: FontWeight.normal,
        color: scheme.secondary);
    final String? status = message ??
        switch (activity) {
          MemberActivity.sharingScreen => "Sharing their screen",
          MemberActivity.inVoice => "In voice",
          null => null,
        };
    return material.Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
      child: material.Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (server != null)
            material.Text(server, maxLines: 1, style: serverStyle),
          if (server != null && status != null)
            material.Text(" · ", maxLines: 1, style: serverStyle),
          if (status != null) ...[
            if (activity != null)
              Icon(
                  activity == MemberActivity.sharingScreen
                      ? Icons.screen_share
                      : Icons.volume_up,
                  size: 12,
                  color: green)
            else
              const Icon(Icons.chat_bubble, size: 10),
            const material.SizedBox(width: 4),
            Flexible(child: statusText(context, status)),
          ],
        ],
      ),
    );
  }

  /// Vommet: "In voice" / "Sharing their screen" with its icon, followed by
  /// the status message when there is one (Discord's "🔊 • status").
  material.Widget activityRow(material.BuildContext context) {
    final green = Colors.green.shade400;
    final message = presence?.message?.message == null
        ? null
        : RedactionScope.of(context).text(presence!.message!.message);
    return material.Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
            activity == MemberActivity.sharingScreen
                ? Icons.screen_share
                : Icons.volume_up,
            size: 12,
            color: green),
        const material.SizedBox(width: 4),
        Flexible(
          child: statusText(
              context,
              message != null
                  ? "• $message"
                  : activity == MemberActivity.sharingScreen
                      ? "Sharing their screen"
                      : "In voice"),
        ),
      ],
    );
  }

  static material.DecoratedBox createPresenceIcon(
      BuildContext context, UserPresenceStatus status) {
    var scheme = Theme.of(context).colorScheme;

    var backgroundColor = scheme.surfaceContainer;

    var color = status.getColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        // Vommet: unknown (the server doesn't share presence) is a hollow
        // ring, so it doesn't read as offline.
        color: status == UserPresenceStatus.unknown ? backgroundColor : color,
        shape: BoxShape.circle,
        border: Border.all(
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
            color: backgroundColor),
      ),
      child: status == UserPresenceStatus.unknown
          ? DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(width: 1.5, color: color),
              ),
              child: const SizedBox(width: 8, height: 8),
            )
          : const SizedBox(
              width: 8,
              height: 8,
            ),
    );
  }

  Widget buildDetailString(String detail) {
    if (detailStringStyle == null) {
      return tiamat.Text.labelLow(detail);
    }

    return material.Text(
      detail,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      style: detailStringStyle?.copyWith(
        fontFamily: "Code",
      ),
    );
  }
}

/// Vommet: a member's activity in the room's call.
enum MemberActivity { inVoice, sharingScreen }
