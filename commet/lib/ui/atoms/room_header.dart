import 'dart:async'; // For StreamSubscription

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart'; // For preferences
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/encryption_marker.dart';
import 'package:commet/ui/molecules/room_translation_views.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_bar.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search_views.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/user_profile/profile_contact_button.dart';
import 'package:commet/utils/notification_utils.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import '../../client/client.dart';
import 'room_view_mode.dart';

class RoomHeader extends StatefulWidget {
  const RoomHeader(this.room,
      {super.key,
      this.onTap,
      this.onBurgerMenuTap,
      this.menu,
      this.showBurger});
  final Room room;

  /// Vommet: shows the menu button on the desktop layout too, while its side
  /// column is hidden (Vommet issue 456). Defaults to the mobile layout only.
  final bool? showBurger;
  final Widget? menu;
  final Function()? onTap;

  final void Function()? onBurgerMenuTap;
  @override
  State<RoomHeader> createState() => _RoomHeaderState();
}

class _RoomHeaderState extends State<RoomHeader> {
  late List<StreamSubscription> _subs;
  UserPresenceStatus? status;
  String? directMessagePartner;

  UserPresenceComponent? presence;

  /// Vommet: the marker last drawn, to redraw only when it changes.
  EncryptionMarkerKind? _markerKind;

  @override
  void initState() {
    super.initState();

    final comp = widget.room.client.getComponent<DirectMessagesComponent>();
    bool isDm = comp?.isRoomDirectMessage(widget.room) == true;

    if (isDm) {
      status = UserPresenceStatus.unknown;
      presence = widget.room.client.getComponent<UserPresenceComponent>();
      directMessagePartner = comp!.getDirectMessagePartnerId(widget.room);
    }

    if (presence != null && directMessagePartner != null) {
      presence!.getUserPresence(directMessagePartner!).then((presence) {
        if (mounted) {
          setState(() {
            status = presence.status;
          });
        }
      });
    }

    _subs = [
      preferences.onSettingChanged.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      widget.room.onUpdate.listen((_) {
        if (mounted) setState(() {});
      }),
      // Vommet: a contact's identity can change without a room update; redraw
      // the marker when it does.
      EncryptionMarker.keysUpdated(widget.room).listen((_) {
        if (!mounted || !EncryptionMarker.enabled) return;
        if (EncryptionMarker.kindFor(widget.room) != _markerKind) {
          setState(() {});
        }
      }),
      if (presence != null)
        presence!.onPresenceChanged.listen(onUserPresenceChanged),
      // Vommet (issue 737): the title's Add as contact follows the contacts.
      if (isDm) ...[
        if (widget.room.client.getComponent<FriendsComponent>()
            case final friends?)
          friends.onFriendsChanged.listen((_) {
            if (mounted) setState(() {});
          }),
        experimentNewHome.onChanged.listen((_) {
          if (mounted) setState(() {});
        }),
      ],
    ];
    RoomViewMode.showingText.addListener(onViewModeChanged);
  }

  @override
  void dispose() {
    for (var sub in _subs) {
      sub.cancel();
    }
    RoomViewMode.showingText.removeListener(onViewModeChanged);
    super.dispose();
  }

  void onViewModeChanged() {
    if (mounted) setState(() {});
  }

  /// Vommet: a voice room's header switches between its call and its chat
  /// (experiment `experiment_voice_room_chat`).
  Widget? withViewSwitch(Widget? menu) {
    menu = withSearchButton(menu);
    if (!RoomViewMode.offersChat(widget.room)) return menu;
    final showingText = RoomViewMode.showingText.value;
    final button = tiamat.Tooltip(
      text: showingText ? "Back to the call" : "Open chat",
      child: SizedBox(
        width: 34,
        height: 34,
        child: tiamat.IconButton(
          size: 20,
          icon: showingText ? m.Icons.headphones : m.Icons.chat_bubble_outline,
          onPressed: () => showingText
              ? RoomViewMode.openCall(widget.room)
              : RoomViewMode.openChat(widget.room),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [button, if (menu != null) menu],
    );
  }

  /// Vommet issue 611: the magnifier that opens the in-chat search. On a
  /// phone it sits in the header; the desktop header has it among the room's
  /// quick actions.
  Widget? withSearchButton(Widget? menu) {
    if (!MediaQuery.of(context).mobile ||
        !InChatSearch.availableIn(widget.room) ||
        (RoomViewMode.offersChat(widget.room) &&
            !RoomViewMode.showingText.value)) {
      return menu;
    }
    final button = SizedBox(
      width: 34,
      height: 34,
      child: tiamat.IconButton(
        size: 20,
        icon: m.Icons.search,
        onPressed: () => InChatSearch.of(widget.room).open(),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [button, if (menu != null) menu],
    );
  }

  void onUserPresenceChanged((String, UserPresence) event) {
    if (event.$1 == directMessagePartner) {
      setState(() {
        status = event.$2.status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Vommet: while messages are selected, the selection bar stands in for
    // the header. Vommet issue 611: so does the in-chat search field.
    return MessageSelectionBar.orHeader(widget.room,
        (context) => InChatSearchField.orHeader(widget.room, buildHeader));
  }

  Widget buildHeader(BuildContext context) {
    final redaction = RedactionScope.of(context);
    bool showRoomIcons = preferences.showRoomAvatars.value;
    bool useGenericIcons = preferences.usePlaceholderRoomAvatars.value;

    bool shouldShowDefaultIcon = (!showRoomIcons && !useGenericIcons) ||
        (showRoomIcons && !useGenericIcons && widget.room.avatar == null);
    IconData defaultIcon = widget.room.icon;
    // Vommet: a voice room shown as its chat gets the chat's #.
    if (RoomViewMode.offersChat(widget.room) &&
        RoomViewMode.showingText.value) {
      defaultIcon = m.Icons.tag;
    }

    Widget iconWidget;

    var iconPadding = EdgeInsets.zero;

    if (shouldShowDefaultIcon) {
      iconPadding = EdgeInsets.fromLTRB(0, 0, 4, 0);
      iconWidget = Opacity(
        opacity: 0.5,
        child: m.Icon(
          defaultIcon,
          size: 20,
        ),
      );
    } else {
      iconPadding = EdgeInsets.fromLTRB(4, 0, 8, 0);
      iconWidget = tiamat.Avatar(
        radius: 15,
        image: showRoomIcons && widget.room.avatar != null
            ? widget.room.avatar
            : null,
        placeholderText:
            (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                    (!showRoomIcons && useGenericIcons)
                ? widget.room.displayName
                : "",
        placeholderColor:
            (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                    (!showRoomIcons && useGenericIcons)
                ? widget.room.defaultColor
                : m.Colors.grey,
        redactionKey: redaction.roomAvatarKey(widget.room),
      );
    }
    final header = HeaderView(
        showBurger: widget.showBurger ?? MediaQuery.of(context).mobile,
        iconWidget: iconWidget,
        text: redaction.roomDisplayName(widget.room),
        iconPadding: iconPadding,
        topic: redaction.roomTopic(widget.room.topic),
        // Vommet: encryption marker after the name, topic on its own line.
        marker: EncryptionMarker.enabled
            ? EncryptionMarkerIcon(
                _markerKind = EncryptionMarker.kindFor(widget.room))
            : null,
        topicBelow: EncryptionMarker.enabled,
        onTap: widget.onTap,
        onBurgerMenuTap: widget.onBurgerMenuTap,
        // Vommet issue 680 phase 2: "Translating from Spanish" while the
        // room is translated.
        menu: withViewSwitch(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoomTranslationChip(room: widget.room),
            if (widget.menu != null) widget.menu!,
          ],
        )),
        status: status);
    // Vommet (issue 737): right-click (long-press on touch) the title of a
    // 1:1 DM to add the person as a contact.
    final addContact = dmAddContactMenuItem(context, widget.room);
    if (addContact == null) return header;
    return AdaptiveContextMenu(items: [addContact], child: header);
  }
}

class HeaderView extends StatelessWidget {
  const HeaderView({
    required this.text,
    this.iconWidget,
    this.iconPadding,
    this.onBurgerMenuTap,
    this.status,
    this.topic,
    this.menu,
    this.showBurger = true,
    this.onTap,
    this.marker,
    this.topicBelow = false,
    super.key,
  });
  final void Function()? onTap;
  final void Function()? onBurgerMenuTap;
  final Widget? iconWidget;
  final UserPresenceStatus? status;
  final EdgeInsets? iconPadding;
  final String text;
  final String? topic;
  final bool showBurger;
  final Widget? menu;

  /// Vommet: shown right after the name, never truncated (the name is).
  final Widget? marker;

  /// Vommet: put the topic on a second line instead of after a dash.
  final bool topicBelow;

  @override
  Widget build(BuildContext context) {
    return m.Material(
      color: m.Colors.transparent,
      child: m.InkWell(
        mouseCursor: m.WidgetStateMouseCursor.clickable,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showBurger)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
                          child: HeaderBurger(
                            onTap: onBurgerMenuTap,
                            highlightColor: m.Colors.red.shade600,
                            notificationColor:
                                m.Theme.of(context).colorScheme.onSurface,
                          )),
                    if (iconWidget != null)
                      Padding(
                        padding: iconPadding ?? EdgeInsets.zero,
                        child: SizedBox(
                          child: Stack(
                            alignment: AlignmentGeometry.bottomRight,
                            children: [
                              iconWidget!,
                              if (status != null)
                                UserPanelView.createPresenceIcon(
                                    context, status!),
                            ],
                          ),
                        ),
                      ),
                    Flexible(
                      child: topicBelow
                          ? LayoutBuilder(
                              builder: (context, constraints) =>
                                  _twoLinesFit(context, constraints.maxHeight)
                                      ? _twoLineTitle(context)
                                      : _oneLineTitle(context))
                          : ClipRect(
                              child: Row(
                                textBaseline: TextBaseline.ideographic,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  m.Text(
                                    text,
                                    style: m.Theme.of(context)
                                        .textTheme
                                        .titleSmall!
                                        .copyWith(
                                            color: m.TextTheme.of(context)
                                                .bodyMedium!
                                                .color),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (topic != null && topic!.isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(8, 0, 8, 0),
                                      child: tiamat.Text.labelLow("—"),
                                    ),
                                  if (topic != null && topic!.isNotEmpty)
                                    Flexible(
                                      child: tiamat.Text.labelLow(
                                        topic!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                ],
                              ),
                            ),
                    )
                  ],
                ),
              ),
              if (topicBelow && menu != null) const SizedBox(width: 8),
              if (menu != null) menu!
            ],
          ),
        ),
      ),
    );
  }
}

extension on HeaderView {
  m.TextStyle _nameStyle(BuildContext context) => m.Theme.of(context)
      .textTheme
      .titleSmall!
      .copyWith(color: m.TextTheme.of(context).bodyMedium!.color);

  /// Vommet issue 495: whether the name and the topic line below it fit in
  /// [height] at the current font scale. The header is a fixed 50 px, so a
  /// large font scale clipped the topic line in half.
  bool _twoLinesFit(BuildContext context, double height) {
    if (topic == null || topic!.isEmpty || !height.isFinite) return true;
    final scaler = MediaQuery.textScalerOf(context);
    double lineHeight(m.TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: "Ag", style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final h = painter.height;
      painter.dispose();
      return h;
    }

    // tiamat.Text.labelLow's size.
    final topicStyle = m.Theme.of(context)
        .textTheme
        .bodyMedium!
        .copyWith(fontWeight: FontWeight.w400, fontSize: 12);
    return lineHeight(_nameStyle(context)) + lineHeight(topicStyle) <= height;
  }

  /// The name, its marker and "— topic" on one line, for when two lines
  /// don't fit (issue 495).
  Widget _oneLineTitle(BuildContext context) {
    return ClipRect(
      child: Row(
        children: [
          Flexible(
            child: m.Text(
              text,
              style: _nameStyle(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (marker != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: marker!,
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: tiamat.Text.labelLow("—"),
          ),
          Flexible(
            child: tiamat.Text.labelLow(
              topic!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _twoLineTitle(BuildContext context) {
    final hasTopic = topic != null && topic!.isNotEmpty;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: m.Text(
                text,
                style: m.Theme.of(context)
                    .textTheme
                    .titleSmall!
                    .copyWith(color: m.TextTheme.of(context).bodyMedium!.color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (marker != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: marker!,
              ),
          ],
        ),
        if (hasTopic)
          tiamat.Text.labelLow(
            topic!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class HeaderBurger extends StatefulWidget {
  const HeaderBurger(
      {required this.highlightColor,
      required this.notificationColor,
      this.onTap,
      super.key});
  final Function()? onTap;
  final Color highlightColor;
  final Color notificationColor;

  @override
  State<HeaderBurger> createState() => _HeaderBurgerState();
}

class _HeaderBurgerState extends State<HeaderBurger> {
  int highlightedNotificationCount = 0;
  int notificationCount = 0;
  late Color color;

  late List<StreamSubscription> subs;

  @override
  void initState() {
    super.initState();
    color = widget.notificationColor;
    subs = [
      clientManager!.directMessages.highlightedRoomsList.onListUpdated
          .listen((_) => updateState()),
      clientManager!.onSpaceUpdated.stream.listen((_) => updateState()),
    ];

    updateNotificationCount();
  }

  @override
  void dispose() {
    for (var sub in subs) sub.cancel();
    super.dispose();
  }

  void updateState() {
    setState(() {
      updateNotificationCount();
    });
  }

  void updateNotificationCount() {
    highlightedNotificationCount = 0;
    notificationCount = 0;

    var counts = NotificationUtils.getNotificationCounts();
    highlightedNotificationCount = counts.$1;
    notificationCount = counts.$2;

    if (notificationCount > 0) {
      color = widget.notificationColor;
    }

    if (highlightedNotificationCount > 0) {
      color = widget.highlightColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: AlignmentGeometry.xy(0.4, 0.3),
        children: [
          tiamat.IconButton(
            iconColor: m.ColorScheme.of(context).onSurface,
            icon: m.Icons.menu_rounded,
            size: 20,
            onPressed: widget.onTap,
          ),
          AnimatedScale(
              scale: highlightedNotificationCount + notificationCount > 0
                  ? 1.0
                  : 0.0,
              duration: m.Durations.medium4,
              curve: Curves.easeOutCubic,
              child: createNotificationIcon(context)),
        ],
      ),
    );
  }

  Widget createNotificationIcon(BuildContext context) {
    var scheme = m.Theme.of(context).colorScheme;

    var backgroundColor = scheme.surfaceContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
            width: 3,
            strokeAlign: BorderSide.strokeAlignOutside,
            color: backgroundColor),
      ),
      child: SizedBox(
        width: 8,
        height: 8,
      ),
    );
  }
}
