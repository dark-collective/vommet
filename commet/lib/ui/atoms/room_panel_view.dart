import 'dart:async';
import 'dart:math';

import 'package:commet/config/room_row_size.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/dot_indicator.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/ui/atoms/shimmer_loading.dart';
import 'package:commet/ui/molecules/typing_indicators_widget.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/bold_text.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomPanelView extends StatefulWidget {
  const RoomPanelView(
      {required this.displayName,
      this.nameTrailing,
      this.nameSuffix,
      this.nameHighlight,
      this.subtitle,
      this.subtitleHighlight,
      this.avatar,
      this.onPrimaryButtonPressed,
      this.primaryButtonLabel,
      this.onSecondaryButtonPressed,
      this.secondaryButtonLabel,
      this.userColor,
      this.onTap,
      this.color,
      this.body,
      this.recentEventSender,
      this.recentEventSenderColor,
      this.userAvatar,
      this.loading = false,
      this.directMessagePartner,
      this.random = 1,
      this.userDisplayName,
      this.userPresence,
      this.showUserAvatar = false,
      this.notificationCount = 0,
      this.highlightNotificationCount = 0,
      this.highlightNoisy = true,
      this.typingMembers,
      this.avatarBadge,
      this.selectedColor,
      super.key});
  final ImageProvider? avatar;
  final ImageProvider? userAvatar;
  final Color? userColor;
  final String? userDisplayName;
  final String displayName;

  /// Vommet: a small icon right after the name (e.g. a DM trust marker).
  final Widget? nameTrailing;

  /// Vommet (New Home Rooms section): muted text after the name, e.g. the
  /// room's space ("general · Fox Den"). Cut off before the name is.
  final String? nameSuffix;

  /// Vommet (New Home search): the part of the name a search matched,
  /// drawn bold in the accent color.
  final ({int start, int end})? nameHighlight;

  /// Vommet: one low-emphasis line under the name, e.g. a DM's topic
  /// (Vommet issue 564). Nothing is drawn when it's null.
  final String? subtitle;

  /// Vommet: the part of [subtitle] a search matched (a topic's).
  final ({int start, int end})? subtitleHighlight;
  final Color? color;
  final String? body;
  final String? recentEventSender;
  final Color? recentEventSenderColor;
  final String? primaryButtonLabel;
  final Future<void> Function()? onPrimaryButtonPressed;
  final Function()? onTap;
  final String? secondaryButtonLabel;
  final Future<void> Function()? onSecondaryButtonPressed;
  final bool showUserAvatar;
  final List<Member>? typingMembers;
  final bool loading;
  final String? directMessagePartner;
  final double random;
  final int notificationCount;
  final int highlightNotificationCount;

  /// Vommet issue 719: whether [highlightNotificationCount] is red.
  final bool highlightNoisy;
  final UserPresence? userPresence;

  /// Room-type mark on the avatar's corner, e.g. a speaker for voice rooms.
  final IconData? avatarBadge;

  /// Vommet: the open room's background (the theme's "Selected room" colour,
  /// Vommet issue 639); null draws no highlight, as before.
  final Color? selectedColor;
  @override
  State<RoomPanelView> createState() => _RoomPanelViewState();
}

class _RoomPanelViewState extends State<RoomPanelView> {
  bool get showPrimaryButton =>
      widget.primaryButtonLabel != null &&
      widget.onPrimaryButtonPressed != null;

  bool get showSecondaryButton =>
      widget.secondaryButtonLabel != null &&
      widget.onSecondaryButtonPressed != null;

  bool get showOnlyPrimaryButton => showPrimaryButton && !showSecondaryButton;

  bool get showAnyButton => showPrimaryButton || showSecondaryButton;

  bool primaryButtonLoading = false;
  bool secondaryButtonLoading = false;

  @override
  void initState() {
    if (widget.typingMembers?.isNotEmpty == true) {
      startTimer();
    }

    super.initState();
  }

  @override
  void didUpdateWidget(covariant RoomPanelView oldWidget) {
    // Vommet: (re)start only when someone starts typing; restarting on
    // every rebuild while typing ran onTimer at each rebuild.
    if (widget.typingMembers?.isNotEmpty == true) {
      if (timer?.isActive != true) startTimer();
    } else {
      timer?.cancel();
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    // Vommet: the typing animation's timer outlived the panel.
    timer?.cancel();
    super.dispose();
  }

  /// Vommet: the name, with [RoomPanelView.nameHighlight] bold in the
  /// accent color, then [RoomPanelView.nameSuffix] in muted text, as one
  /// line: an ellipsis takes the suffix before the name.
  Widget nameWithSuffix(BuildContext context) {
    final theme = Theme.of(context);
    final suffix = widget.nameSuffix;
    return tiamat.TooltipWhenCutOff(
      text: suffix == null
          ? widget.displayName
          : "${widget.displayName} · $suffix",
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: MediaQuery.textScalerOf(context),
        text: TextSpan(children: [
          ...highlighted(
              context,
              widget.displayName,
              widget.nameHighlight,
              theme.textTheme.labelLarge!
                  .copyWith(fontWeight: FontWeight.w400)),
          if (suffix != null)
            TextSpan(
                text: " · $suffix",
                style: theme.textTheme.bodyMedium!.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }

  /// [text] in [style], with [hit] (when inside it) bold in the accent
  /// color.
  static List<TextSpan> highlighted(BuildContext context, String text,
      ({int start, int end})? hit, TextStyle style) {
    if (hit == null ||
        hit.start < 0 ||
        hit.end > text.length ||
        hit.start >= hit.end) {
      return [TextSpan(text: text, style: style)];
    }
    final accent = style.copyWith(
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.primary);
    return [
      TextSpan(text: text.substring(0, hit.start), style: style),
      TextSpan(text: text.substring(hit.start, hit.end), style: accent),
      TextSpan(text: text.substring(hit.end), style: style),
    ];
  }

  /// Vommet: [RoomPanelView.subtitle] with its search hit.
  Widget highlightedSubtitle(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
          children: highlighted(
              context,
              widget.subtitle!,
              widget.subtitleHighlight,
              theme.textTheme.bodyMedium!.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: theme.colorScheme.onSurfaceVariant))),
    );
  }

  /// Vommet issue 639: the open room's row on the theme's "Selected room"
  /// colour, with readable text on top (as in `RoomTextButton`).
  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedColor;
    if (selected == null) return buildPanel(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = RoomTextButton.readableOn(selected, scheme);
    final soft = fg.withAlpha(200);
    return Material(
      color: selected,
      borderRadius: BorderRadius.circular(10),
      child: fg == scheme.onSurface
          ? Builder(builder: buildPanel)
          : Theme(
              data: theme.copyWith(
                  colorScheme: scheme.copyWith(
                      onSurface: fg, onSurfaceVariant: soft, secondary: soft)),
              child: Builder(builder: buildPanel)),
    );
  }

  Widget buildPanel(BuildContext context) {
    var shimmerColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    bool shimmer = widget.loading;
    // Vommet issue 796: Standard or Large rows.
    final size = roomRowSize;

    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Shimmer(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: widget.onTap,
            child: Container(
              decoration:
                  BoxDecoration(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: size.rowPadding,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  ShimmerLoading(
                                    isLoading: widget.loading,
                                    child: Stack(
                                      alignment: AlignmentGeometry.bottomRight,
                                      children: [
                                        Padding(
                                          padding: EdgeInsetsGeometry.all(3),
                                          child: Avatar(
                                            radius: size.panelAvatarRadius,
                                            image: widget.avatar,
                                            placeholderText: shimmer
                                                ? " "
                                                : widget.displayName,
                                            placeholderColor: shimmer
                                                ? shimmerColor
                                                : widget.color,
                                          ),
                                        ),
                                        if (widget.avatarBadge != null &&
                                            !shimmer &&
                                            widget.typingMembers?.isNotEmpty !=
                                                true)
                                          AvatarBadge(widget.avatarBadge!,
                                              size: 16),
                                      ],
                                    ),
                                  ),
                                  typingIndicators(),
                                  if (widget.showUserAvatar)
                                    Avatar(
                                      radius: 10,
                                      image: widget.userAvatar,
                                      placeholderText: widget.userDisplayName,
                                      placeholderColor: widget.userColor,
                                    ),
                                ],
                              ),
                              Flexible(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(4, 0, 8, 0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (shimmer)
                                        ShimmerLoading(
                                          isLoading: shimmer,
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                0, 4, 0, 0),
                                            child: Container(
                                              height: 16,
                                              width: (widget.random * 80) + 20,
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  color: shimmerColor),
                                            ),
                                          ),
                                        ),
                                      if (shimmer)
                                        ShimmerLoading(
                                          isLoading: shimmer,
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                0, 4, 0, 0),
                                            child: Container(
                                              height: 12,
                                              width: (widget.random * 200) + 20,
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  color: shimmerColor),
                                            ),
                                          ),
                                        ),
                                      if (!shimmer)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: widget.nameSuffix ==
                                                          null &&
                                                      widget.nameHighlight ==
                                                          null
                                                  ? tiamat.TooltipWhenCutOff(
                                                      text: widget.displayName,
                                                      child: tiamat.Text
                                                          .labelEmphasised(
                                                        widget.displayName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    )
                                                  : nameWithSuffix(context),
                                            ),
                                            if (widget.nameTrailing != null)
                                              widget.nameTrailing!,
                                          ],
                                        ),
                                      if (!shimmer &&
                                          widget.subtitle != null &&
                                          widget.subtitleHighlight != null)
                                        highlightedSubtitle(context)
                                      else if (!shimmer &&
                                          widget.subtitle != null)
                                        tiamat.Text.labelLow(
                                          widget.subtitle!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if (widget.body != null)
                                        SizedBox(
                                            height: 16 * size.textScale,
                                            child: recentEvent()),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.notificationCount > 0 &&
                            widget.highlightNotificationCount == 0)
                          const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: DotIndicator(),
                          ),
                        if (widget.highlightNotificationCount > 0)
                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: NotificationBadge(
                                widget.highlightNotificationCount,
                                noisy: widget.highlightNoisy),
                          ),
                        if (showAnyButton) actionButtons(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!size.isLarge) return panel;
    return Padding(
      padding: EdgeInsets.only(bottom: size.rowGap),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: size.textScaler(MediaQuery.textScalerOf(context))),
        child: panel,
      ),
    );
  }

  late List<GlobalKey> blobKeys = [
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
  ];

  Timer? timer;

  int prevIndex = 0;
  void startTimer() {
    onTimer();
    timer?.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) => onTimer());
  }

  static final _random = Random();

  void onTimer() {
    var r = _random.nextInt(3);

    if (r == prevIndex) {
      r += 1;
      r = r % blobKeys.length;
    }

    prevIndex = r;

    var key = blobKeys[r];

    if (key.currentState == null) {
      return;
    }

    var state = key.currentState! as SingleTypingIndicatorBlobState;
    state.controller.forward(from: 0);
  }

  Widget typingIndicators() {
    var color = widget.userPresence?.status.getColor();
    var border = null;
    var expanded = widget.typingMembers?.isNotEmpty == true;
    var backgroundColor = ColorScheme.of(context).surfaceContainer;
    if (!expanded && color == null) {
      color = Colors.transparent;
      backgroundColor = Colors.transparent;
    }

    var duration =
        expanded ? Duration(seconds: 1) : Duration(milliseconds: 300);
    var curve = expanded ? Curves.elasticOut : Curves.easeInOutCubic;

    var offset = expanded ? 7.0 : 0.0;
    var rightPad = 2.0;
    return AnimatedContainer(
      duration: duration,
      curve: curve,
      width: (expanded ? 23 : 10) + rightPad,
      decoration: BoxDecoration(
          color: backgroundColor, borderRadius: BorderRadius.circular(5)),
      height: 12,
      child: Stack(
        alignment: AlignmentGeometry.center,
        children: [
          AnimatedPositioned(
              duration: duration,
              right: rightPad,
              curve: curve,
              child: SingleTypingIndicatorBlob(
                key: blobKeys[0],
                border: border,
                color: color,
                playing: expanded,
              )),
          AnimatedPositioned(
              duration: duration,
              right: rightPad + offset,
              curve: curve,
              child: SingleTypingIndicatorBlob(
                key: blobKeys[1],
                border: border,
                color: color,
                playing: expanded,
              )),
          AnimatedPositioned(
              duration: duration,
              right: rightPad + (offset * 2),
              curve: curve,
              child: SingleTypingIndicatorBlob(
                key: blobKeys[2],
                border: border,
                color: color,
                playing: expanded,
              )),
        ],
      ),
    );
  }

  Widget recentEvent() {
    var color = widget.recentEventSenderColor != null
        ? tiamat.Text.adjustColor(context, widget.recentEventSenderColor!)
        : null;

    var style = withBoldText(
        context,
        TextTheme.of(context)
            .labelMedium
            ?.copyWith(fontSize: 12, letterSpacing: 0));
    return SizedBox(
      child: RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(children: [
            if (widget.recentEventSender != null)
              TextSpan(
                text: widget.recentEventSender! + ":",
                style: style?.copyWith(color: color),
              ),
            if (widget.recentEventSender != null)
              WidgetSpan(
                  child: SizedBox(
                width: 4,
              )),
            TextSpan(
                text: widget.body,
                style:
                    style?.copyWith(color: ColorScheme.of(context).secondary))
          ])),
    );
  }

  // Vommet: a failed action (e.g. a join the server refuses) shows the
  // server's error and frees the button, instead of spinning forever.
  Future<void> runAction(Future<void> Function()? action,
      void Function(bool loading) setLoading) async {
    setState(() => setLoading(true));
    try {
      await action?.call();
    } catch (e, s) {
      Log.onError(e, s);
      if (mounted) AdaptiveDialog.showError(context, e, s);
    } finally {
      if (mounted) setState(() => setLoading(false));
    }
  }

  Widget actionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (showPrimaryButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
            child: Button(
              text: widget.primaryButtonLabel!,
              isLoading: primaryButtonLoading,
              onTap: () => runAction(widget.onPrimaryButtonPressed,
                  (loading) => primaryButtonLoading = loading),
            ),
          ),
        if (showSecondaryButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
            child: Button.secondary(
              text: widget.secondaryButtonLabel!,
              isLoading: secondaryButtonLoading,
              onTap: () => runAction(widget.onSecondaryButtonPressed,
                  (loading) => secondaryButtonLoading = loading),
            ),
          ),
      ],
    );
  }
}
