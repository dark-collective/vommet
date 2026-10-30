import 'package:commet/ui/organisms/share_history/share_history.dart';
import 'package:commet/ui/atoms/clickable_gesture_detector.dart';
import 'dart:async';
import 'dart:ui';

import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/atoms/tiny_pill.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/color_utils.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:timezone/standalone.dart' as tz;
import 'package:commet/utils/clock_format.dart';

class UserProfileView extends StatefulWidget {
  const UserProfileView(
      {super.key,
      this.userAvatar,
      required this.displayName,
      required this.userColor,
      this.userBanner,
      required this.identifier,
      this.clientId,
      required this.isSelf,
      this.presence,
      this.onSetBanner,
      this.timezone,
      this.bannerHeight = 230.0,
      this.width = 700,
      this.setPreviewColor,
      this.hasColorOverride = false,
      this.setPreviewBrightness,
      this.setColorOverride,
      this.setPetName,
      this.currentPetName,
      this.hasPetName = false,
      this.shareCurrentTimezone,
      this.removeTimezone,
      this.onSetAvatar,
      this.bio,
      this.mutual,
      this.contactButton,
      this.linkPreviews,
      this.onSetStatus,
      this.editBadges,
      this.setBio,
      this.badges = const [],
      this.clearBio,
      this.showMessageButton = true,
      this.doSafeArea = true,
      this.onChangeName,
      this.maxBioHeight = 200,
      this.showSource,
      this.pronouns = const [],
      this.clearStatus,
      this.savePreviewTheme,
      this.isBlocked = false,
      this.onBlock,
      this.onUnblock,
      this.onShareHistory,
      this.bridgedChip,
      this.cantMessageReason,
      this.onMessageButtonClicked});
  final ImageProvider? userAvatar;
  final ImageProvider? userBanner;
  final UserPresence? presence;
  final String displayName;
  final String identifier;

  /// The client the profile is shown from; makes links in the status
  /// message tappable.
  final String? clientId;
  final bool doSafeArea;
  final List<String> pronouns;
  final List<ProfileBadge> badges;
  final Color userColor;
  final bool isSelf;
  final bool showMessageButton;
  final double bannerHeight;
  final double maxBioHeight;
  final bool hasColorOverride;
  final String? timezone;
  final double width;
  final Future<void> Function()? onSetBanner;
  final Future<void> Function()? onSetAvatar;
  final Future<void> Function()? onSetStatus;
  final Future<void> Function()? onChangeName;
  final Future<void> Function()? shareCurrentTimezone;
  final Future<void> Function()? removeTimezone;
  final Future<void> Function()? setBio;
  final Future<void> Function()? clearBio;
  final Future<void> Function()? clearStatus;
  final Future<void> Function()? editBadges;
  final void Function()? showSource;
  final void Function(Color)? setPreviewColor;
  final Widget? bio;

  /// Vommet: mutual spaces and rooms, shown under the bio.
  final Widget? mutual;

  /// Vommet: the Add contact / Contact button, shown under Message.
  final Widget? contactButton;

  /// Vommet issue 676: Ask/Always/Never for the link previews this person's
  /// app attaches; not on your own profile.
  final Widget? linkPreviews;
  final Future<void> Function(Brightness)? setPreviewBrightness;
  final Future<void> Function(String?)? setPetName;
  final String? currentPetName;
  final bool hasPetName;
  final Future<void> Function()? onMessageButtonClicked;
  final Future<void> Function()? savePreviewTheme;
  final Future<void> Function(Color?)? setColorOverride;

  /// Vommet: blocking (experiment). Null callbacks hide the menu entry.
  final bool isBlocked;
  final Future<void> Function()? onBlock;
  final Future<void> Function()? onUnblock;

  /// Vommet issue 744: share the history of the room the card was opened
  /// from with this person. Null hides the menu entry.
  final Future<void> Function()? onShareHistory;

  /// Vommet issue 853: "Probably Telegram" for a bridged user, under the
  /// pronouns.
  final Widget? bridgedChip;

  /// Vommet issue 853: set for a voice bridge puppet, whose Message button
  /// becomes a disabled "Can't message them" with this as its tooltip.
  final String? cantMessageReason;

  @override
  State<UserProfileView> createState() => UserProfileViewState();
}

class UserProfileViewState extends State<UserProfileView> {
  bool isLoadingDirectMessage = false;

  String get promptOpenDirectMessage => Intl.message("Message",
      desc: "Prompt on the button to open a direct message with another user",
      name: "promptOpenDirectMessage");

  String get promptProfileChangeBanner => Intl.message("Change Banner",
      desc: "Prompt to change the banner on the user's profile",
      name: "promptProfileChangeBanner");

  static String get promptProfileSetStatus =>
      Intl.message("Set Status", name: "promptProfileSetStatus");

  String get promptProfileClearStatus =>
      Intl.message("Clear Status", name: "promptProfileClearStatus");

  String get promptProfileSetBadges =>
      Intl.message("Set Badges", name: "promptProfileSetBadges");

  String get promptProfileSetBio =>
      Intl.message("Set Bio", name: "promptProfileSetBio");

  String get promptProfileClearBio =>
      Intl.message("Clear Bio", name: "promptProfileClearBio");

  String get promptProfileShareTimezone => Intl.message("Share Timezone",
      name: "promptProfileShareTimezone",
      desc:
          "Prompt the user to add their current timezone to their user profile");

  String get promptProfileClearTimezone => Intl.message("Remove Timezone",
      name: "promptProfileClearTimezone",
      desc: "Prompt to remove the shared timezone from a users profile");

  String get promptProfileEditColorScheme => Intl.message("Edit Color Scheme",
      name: "promptProfileEditColorScheme",
      desc: "Prompt to edit the color scheme of the user's own profile");

  String get promptProfileSetColorOverride => Intl.message("Set Color Override",
      name: "promptProfileSetColorOverride",
      desc: "Prompt to override the display color of a user");

  String get promptProfileClearColorOverride =>
      Intl.message("Clear Color Override",
          name: "promptProfileClearColorOverride",
          desc: "Prompt to remove an override of the display color of a user");

  String get promptProfileShowRawProfile => Intl.message("Show Raw Profile",
      name: "promptProfileShowRawProfile",
      desc:
          "Show the raw data of a user profile, typically this is hidden behind developer mode");

  bool editingColorScheme = false;

  Timer? timezoneTimer;

  tz.TZDateTime? localTime;

  ScrollController bioScrollController = ScrollController();

  @override
  void initState() {
    if (widget.timezone != null) {
      timezoneTimer =
          Timer.periodic(Duration(seconds: 1), (_) => updateLocalTime());
      updateLocalTime();
    }

    super.initState();
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);

    timezoneTimer?.cancel();

    if (widget.timezone != null) {
      timezoneTimer =
          Timer.periodic(Duration(seconds: 1), (_) => updateLocalTime());
      updateLocalTime();
    }
  }

  @override
  void dispose() {
    timezoneTimer?.cancel();
    super.dispose();
  }

  void updateLocalTime() {
    try {
      setState(() {
        if (widget.timezone != null) ;
        var location = tz.getLocation(widget.timezone!);
        localTime = tz.TZDateTime.now(location);
      });
    } catch (_) {}
  }

  // Vommet: show the avatar full size.
  void openAvatar() {
    if (widget.userAvatar != null) {
      Lightbox.show(context, image: widget.userAvatar!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidesPictures = RedactionScope.of(context).hidesAvatars;
    var background = Theme.of(context).colorScheme.primaryContainer;
    final bannerHeight = widget.bannerHeight;
    const avatarOverlap = 50.0;

    return ClipRRect(
      borderRadius: BorderRadiusGeometry.circular(8),
      child: Container(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.width),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 0,
            children: [
              SizedBox(
                child: Stack(
                  children: [
                    SizedBox(
                      height: bannerHeight,
                      width: double.infinity,
                      child: widget.userBanner != null && !hidesPictures
                          // Vommet: tap the banner to see it full size.
                          ? ClickableGestureDetector(
                              onTap: () => Lightbox.show(context,
                                  image: widget.userBanner!),
                              child: RedactedImage(
                                child: Image(
                                  image: widget.userBanner!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                          : widget.userAvatar != null && !hidesPictures
                              ? ClipRect(
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                        sigmaX: 40,
                                        sigmaY: 40,
                                        tileMode: TileMode.repeated),
                                    child: Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainer,
                                      child: Image(
                                        image: widget.userAvatar!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                ),
                    ),
                    Align(
                        alignment: AlignmentGeometry.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: ClipRRect(
                            borderRadius: BorderRadiusGeometry.circular(15),
                            child: SizedBox(
                                width: 30,
                                height: 30,
                                child: Material(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withAlpha(100),
                                  child: AdaptiveContextMenu(
                                    modal: true,
                                    items: contextMenuItems(context),
                                    child: Icon(
                                      Icons.more_vert,
                                      size: 15,
                                    ),
                                  ),
                                )),
                          ),
                        )),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          0, bannerHeight - avatarOverlap, 0, 0),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                0, avatarOverlap - 2, 0, 0),
                            child: Container(
                              color: background,
                              child: ScaledSafeArea(
                                  bottom: widget.doSafeArea,
                                  top: widget.doSafeArea,
                                  left: widget.doSafeArea,
                                  right: widget.doSafeArea,
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        8, avatarOverlap, 8, 8),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainer,
                                      ),
                                      child: Column(
                                        spacing: 8,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      12, 4, 12, 4),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Flexible(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        displayName(),
                                                        username(context),
                                                        pronouns(),
                                                        if (widget
                                                                .bridgedChip !=
                                                            null)
                                                          widget.bridgedChip!,
                                                      ],
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .fromLTRB(0, 8, 0, 0),
                                                    child: Column(
                                                      spacing: 8,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        if (localTime != null &&
                                                            widget.timezone !=
                                                                null)
                                                          userLocalTime(),
                                                        badges(),
                                                      ],
                                                    ),
                                                  )
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (widget.bio != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      8, 0, 8, 0),
                                              child: buildBio(context),
                                            ),
                                          if (widget.mutual != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      8, 0, 8, 0),
                                              child: widget.mutual!,
                                            ),
                                          if (!widget.isSelf &&
                                              widget.showMessageButton)
                                            Padding(
                                              // Vommet: the column's 8 px
                                              // spacing is the gap above the
                                              // contact button.
                                              padding: EdgeInsets.fromLTRB(
                                                  8,
                                                  8,
                                                  8,
                                                  widget.contactButton == null
                                                      ? 8
                                                      : 0),
                                              child: widget.cantMessageReason !=
                                                      null
                                                  ? Tooltip(
                                                      message: widget
                                                          .cantMessageReason!,
                                                      child: SizedBox(
                                                        width: double.infinity,
                                                        child:
                                                            OutlinedButton.icon(
                                                          key: const ValueKey(
                                                              "userProfileCantMessage"),
                                                          onPressed: null,
                                                          icon: const Icon(
                                                              Icons
                                                                  .speaker_notes_off_outlined,
                                                              size: 18),
                                                          label: Text(
                                                              bridgedCantMessage),
                                                        ),
                                                      ),
                                                    )
                                                  : tiamat.Button(
                                                      text:
                                                          promptOpenDirectMessage,
                                                      isLoading:
                                                          isLoadingDirectMessage,
                                                      onTap: clickMessageButton,
                                                    ),
                                            ),
                                          if (!widget.isSelf &&
                                              widget.contactButton != null)
                                            widget.contactButton!,
                                          if (!widget.isSelf &&
                                              widget.linkPreviews != null)
                                            widget.linkPreviews!,
                                          if (editingColorScheme)
                                            buildColorSchemeEditor()
                                        ],
                                      ),
                                    ),
                                  )),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                MouseRegion(
                                    cursor: widget.isSelf ||
                                            widget.userAvatar != null
                                        ? SystemMouseCursors.click
                                        : MouseCursor.defer,
                                    child: GestureDetector(
                                        // Vommet: others' avatars open full
                                        // size on tap; your own (tap edits
                                        // it) on right-click or long-press.
                                        onTap: widget.isSelf
                                            ? widget.onSetAvatar
                                            : openAvatar,
                                        onSecondaryTap: openAvatar,
                                        onLongPress:
                                            widget.isSelf ? openAvatar : null,
                                        child: tiamat.Avatar.large(
                                          border: BoxBorder.all(
                                              color: background,
                                              width: 8,
                                              strokeAlign: 0.9),
                                          image: widget.userAvatar,
                                          placeholderColor: widget.userColor,
                                          placeholderText: widget.displayName,
                                          redactionKey: widget.identifier,
                                        ))),
                                if (widget.presence?.message != null)
                                  Flexible(
                                      child: buildPresenceDisplay(background))
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Padding username(BuildContext context) {
    // Vommet issue 475: the user ID names the person, so it goes with names.
    if (RedactionScope.of(context).redactsNames) {
      return const Padding(padding: EdgeInsets.zero);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Opacity(
          opacity: 0.8,
          child: Row(
            children: [
              Text(
                widget.identifier,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: "Code",
                    color: Theme.of(context).colorScheme.onSurface),
              ),
              tiamat.IconButton(
                icon: Icons.copy,
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: widget.identifier)),
                size: Theme.of(context).textTheme.labelSmall?.fontSize ?? 12,
                iconColor: Theme.of(context).colorScheme.onSurface,
              ),
            ],
          )),
    );
  }

  Container buildBio(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxBioHeight),
              child: Scrollbar(
                thumbVisibility: true,
                controller: bioScrollController,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(0),
                  controller: bioScrollController,
                  child: widget.bio,
                ),
              ),
            )));
  }

  Widget userLocalTime() {
    final l = localTime!;
    var t = DateTime(l.year, l.month, l.day, l.hour, l.minute, l.second);

    var localDay = DateFormat(DateFormat.WEEKDAY).format(DateTime.now());
    var day = DateFormat(DateFormat.WEEKDAY).format(t);
    // Vommet: the clock setting (Vommet issue 347).
    var time = ClockFormat.time(use24: ClockFormat.use24Of(context)).format(t);

    var result = time;
    if (day != localDay) {
      result = "$day, $time";
    }

    final colors = Theme.of(context).colorScheme;
    return tiamat.Tooltip(
      child: TinyPill(result,
          background: colors.tertiary, foreground: colors.onTertiary),
      text: "Local Timezone: ${widget.timezone!}",
    );
  }

  List<tiamat.ContextMenuItem> contextMenuItems(BuildContext context) {
    return [
      // Vommet: tapping your own name also does this, but nobody finds it.
      if (widget.isSelf && widget.onChangeName != null)
        profileMenuItem(
            text: profileMenuChangeDisplayName,
            tooltip: profileMenuChangeDisplayNameTooltip,
            onPressed: () => widget.onChangeName?.call(),
            icon: Icons.edit),
      // Vommet: tapping your own picture also does this, but nobody finds it.
      if (widget.isSelf && widget.onSetAvatar != null)
        profileMenuItem(
            text: profileMenuChangeProfilePicture,
            tooltip: profileMenuChangeProfilePictureTooltip,
            onPressed: () => widget.onSetAvatar?.call(),
            icon: Icons.account_circle),
      if (widget.isSelf)
        profileMenuItem(
            text: promptProfileChangeBanner,
            tooltip: profileMenuBannerTooltip,
            onPressed: () => widget.onSetBanner?.call(),
            icon: Icons.image),
      if (widget.isSelf)
        profileMenuItem(
            text: promptProfileSetStatus,
            tooltip: profileMenuStatusTooltip,
            onPressed: () => widget.onSetStatus?.call(),
            onClearPressed: widget.presence?.message != null
                ? () => widget.clearStatus?.call()
                : null,
            icon: Icons.short_text),
      if (widget.isSelf)
        profileMenuItem(
            text: promptProfileSetBadges,
            tooltip: profileMenuBadgesTooltip,
            onPressed: () => widget.editBadges?.call(),
            icon: Icons.star),
      if (widget.isSelf)
        profileMenuItem(
            text: promptProfileSetBio,
            tooltip: profileMenuBioTooltip,
            onPressed: () => widget.setBio?.call(),
            icon: Icons.text_snippet,
            onClearPressed: () => widget.clearBio?.call()),
      if (widget.isSelf)
        profileMenuItem(
            text: promptProfileShareTimezone,
            tooltip: profileMenuTimezoneTooltip,
            onPressed: () => widget.shareCurrentTimezone?.call(),
            icon: Icons.share_arrival_time,
            onClearPressed: widget.timezone != null
                ? () => widget.removeTimezone?.call()
                : null),
      if (widget.isSelf)
        profileMenuItem(
            text: promptProfileEditColorScheme,
            tooltip: profileMenuColorSchemeTooltip,
            onPressed: () => setState(() {
                  editingColorScheme = true;
                }),
            icon: Icons.color_lens),
      profileMenuItem(
          text: promptProfileSetColorOverride,
          tooltip: profileMenuColorOverrideTooltip,
          onClearPressed: widget.hasColorOverride
              ? () => widget.setColorOverride?.call(null)
              : null,
          onPressed: () async {
            var color = await AdaptiveDialog.show<Color>(
              title: promptProfileSetColorOverride,
              context,
              builder: (context) {
                return SizedBox(
                  width: 500,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: tiamat.Text.labelLow(
                            "Set a local color override for a user. This is only visible to you"),
                      ),
                      GridView(
                          shrinkWrap: true,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisSpacing: 3,
                                  mainAxisSpacing: 3,
                                  crossAxisCount:
                                      MediaQuery.of(context).mobile ? 5 : 10),
                          children: [
                            for (int i = 0; i < 20; i++)
                              buildColorSchemeItem(
                                color: HSVColor.fromAHSV(1.0,
                                        (i.toDouble() / 21) * 360, 0.8, 1.0)
                                    .toColor(),
                                onTap: (c) {
                                  Navigator.of(context).pop(c);
                                },
                              )
                          ]),
                    ],
                  ),
                );
              },
            );

            if (color != null) {
              widget.setColorOverride?.call(color);
            }
          },
          icon: Icons.colorize),
      // Vommet: a nickname for yourself only confused people looking for
      // "Change Display Name", so it is offered for other people only.
      if (!widget.isSelf)
        profileMenuItem(
          text: profileMenuSetNickname,
          icon: Icons.badge,
          tooltip: profileMenuSetNicknameTooltip,
          onClearPressed:
              widget.hasPetName ? () => widget.setPetName?.call(null) : null,
          onPressed: () async {
            final text = await AdaptiveDialog.textPrompt(
              context,
              initialText: widget.currentPetName ?? '',
              title: profileMenuSetNickname,
              hintText: profileMenuNicknameHint,
            );
            if (text != null) {
              await widget.setPetName
                  ?.call(text.trim().isEmpty ? null : text.trim());
            }
          },
        ),
      if (!widget.isSelf && widget.onShareHistory != null)
        profileMenuItem(
          text: ShareHistoryStrings.menuItem,
          icon: Icons.history,
          onPressed: () => widget.onShareHistory?.call(),
        ),
      if (!widget.isSelf && !widget.isBlocked && widget.onBlock != null)
        profileMenuItem(
          text: profileMenuBlock,
          icon: Icons.block,
          tooltip: profileMenuBlockTooltip,
          onPressed: () => widget.onBlock?.call(),
        ),
      if (!widget.isSelf && widget.isBlocked && widget.onUnblock != null)
        profileMenuItem(
          text: profileMenuUnblock,
          icon: Icons.block,
          tooltip: profileMenuUnblockTooltip,
          onPressed: () => widget.onUnblock?.call(),
        ),
      if (preferences.developerMode.value)
        profileMenuItem(
            text: promptProfileShowRawProfile,
            tooltip: "Developer: the profile data as the server sends it",
            onPressed: () => widget.showSource?.call(),
            icon: Icons.code),
    ];
  }

  tiamat.ContextMenuItem profileMenuItem(
      {required String text,
      required IconData icon,
      required Function onPressed,
      Function? onClearPressed,
      String? tooltip}) {
    return tiamat.ContextMenuItem(
      text: text,
      icon: icon,
      onPressed: onPressed,
      customBuilder: (context, onClicked, {closeMenu}) {
        var c = Theme.of(context).colorScheme.onSurface;

        final item = Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              spacing: 8,
              children: [
                Expanded(
                  child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      onTap: onClicked,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.max,
                            spacing: 8,
                            children: [
                              Icon(
                                icon,
                                color: c,
                                size: 20,
                              ),
                              tiamat.Text(text,
                                  type: tiamat.TextType.body,
                                  maxLines: 1,
                                  color: c),
                            ],
                          ))),
                ),
                if (onClearPressed != null)
                  tiamat.IconButton(
                    icon: Icons.close,
                    size: 18,
                    iconColor: Colors.red,
                    // Vommet: close the menu first. Closing it after
                    // popped whatever the action opened instead (bio's "Are
                    // you sure?" dialog, answered "no" before it showed), so
                    // the bio was never cleared.
                    onPressed: () {
                      closeMenu?.call();
                      onClearPressed.call();
                    },
                  ),
              ],
            ),
          ),
        );
        // Vommet: explain each option (hover on desktop, a line under it in
        // the mobile sheet).
        if (tooltip == null) return item;
        if (MediaQuery.of(context).desktop) {
          return tiamat.Tooltip(text: tooltip, child: item);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            item,
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 16, 6),
              child: tiamat.Text.labelLow(tooltip),
            ),
          ],
        );
      },
    );
  }

  Widget buildColorSchemeEditor() {
    var run = 8;
    var count = run * 2;
    return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainer,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  GridView(
                    shrinkWrap: true,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisSpacing: 3,
                        mainAxisSpacing: 3,
                        crossAxisCount: run),
                    children: [
                      for (int i = 0; i < count; i++)
                        buildColorSchemeItem(
                          color: HSVColor.fromAHSV(1.0,
                                  (i.toDouble() / (count + 1)) * 360, 0.5, 0.8)
                              .toColor(),
                          onTap: (c) => widget.setPreviewColor?.call(c),
                        ),
                      buildColorSchemeItem(
                          icon: Icons.light_mode,
                          onTap: (_) => widget.setPreviewBrightness
                              ?.call(Brightness.light)),
                      buildColorSchemeItem(
                          icon: Icons.dark_mode,
                          onTap: (_) => widget.setPreviewBrightness
                              ?.call(Brightness.dark)),
                      buildColorSchemeItem(
                        icon: Icons.tag,
                        onTap: (_) async {
                          var hexCode = await AdaptiveDialog.textPrompt(context,
                              title: "Enter Color Code", hintText: "#FFFFFF");
                          if (hexCode != null) {
                            var color = ColorUtils.fromHexCode(hexCode);
                            widget.setPreviewColor?.call(color);
                          }
                        },
                      ),
                      buildColorSchemeItem(
                        icon: Icons.save,
                        onTap: (_) {
                          widget.savePreviewTheme?.call();
                          setState(() {
                            editingColorScheme = false;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ));
  }

  Widget buildColorSchemeItem({
    Color? color,
    IconData? icon,
    Function(Color)? onTap,
  }) {
    var c = color ?? Theme.of(context).colorScheme.primaryContainer;
    return Material(
      clipBehavior: Clip.antiAlias,
      color: c,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => onTap?.call(c),
        child: SizedBox(
          height: 30,
          width: 30,
          child: icon != null
              ? Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                )
              : null,
        ),
      ),
    );
  }

  Widget buildPresenceDisplay(Color background) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Container(
          decoration: BoxDecoration(
              border: BoxBorder.all(color: background, width: 4),
              color: Theme.of(context).colorScheme.secondary,
              borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: buildPresenceMessage(widget.presence!.message!.message),
          )),
    );
  }

  // Vommet issue 717: links in the status open (and long-press copies them)
  // like in messages. They keep the status color, underlined, so they stay
  // readable on the status bubble.
  Widget buildPresenceMessage(String message) {
    var color = Theme.of(context).colorScheme.onSecondary;
    var clientId = widget.clientId;
    var redaction = RedactionScope.of(context);
    if (redaction.redactsText) message = redaction.text(message);
    if (clientId == null ||
        redaction.redactsText ||
        !TextUtils.containsUrl(message)) {
      return tiamat.Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        color: color,
      );
    }

    var style = Theme.of(context)
        .textTheme
        .labelLarge!
        .copyWith(fontWeight: FontWeight.w300, color: color);
    var spans = TextUtils.linkifyString(message,
            style: style, context: context, clientId: clientId)
        .map((span) => span is TextSpan && span.recognizer != null
            ? TextSpan(
                text: span.text,
                recognizer: span.recognizer,
                style: style.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: color))
            : span)
        .toList();
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget actionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        tiamat.Button(
          text: promptOpenDirectMessage,
          onTap: clickMessageButton,
          isLoading: isLoadingDirectMessage,
        ),
      ],
    );
  }

  Future<void> clickMessageButton() async {
    setState(() {
      isLoadingDirectMessage = true;
    });

    await widget.onMessageButtonClicked?.call();

    setState(() {
      isLoadingDirectMessage = false;
    });
  }

  Widget buildBadge(ProfileBadge i) {
    var doOutline = i.brightness == null
        ? false
        : Theme.of(context).brightness == i.brightness;

    return tiamat.Tooltip(
      text: i.body,
      child: SizedBox(
          width: 30,
          height: 30,
          child: Stack(
            children: [
              if (doOutline)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                        Theme.of(context)
                            .colorScheme
                            .inverseSurface
                            .withAlpha(200),
                        BlendMode.srcIn),
                    child: Image(
                      image: i.image,
                    ),
                  ),
                ),
              Image(
                image: i.image,
              ),
            ],
          )),
    );
  }

  Widget displayName() {
    return MouseRegion(
      cursor: widget.isSelf ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.isSelf ? widget.onChangeName : null,
        child: Text(
          RedactionScope.of(context)
              .name(widget.displayName, widget.identifier),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget pronouns() {
    if (widget.pronouns.isEmpty) return Container();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: widget.pronouns
            .map((i) => TinyPill(RedactionScope.of(context).text(i)))
            .toList(),
      ),
    );
  }

  Widget badges() {
    return Material(
      clipBehavior: Clip.hardEdge,
      borderRadius: BorderRadius.circular(8),
      color: widget.badges.isEmpty && widget.isSelf
          ? ColorScheme.of(context).surfaceContainerLow
          : Colors.transparent,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: widget.isSelf ? () => widget.editBadges?.call() : null,
        child: Padding(
            padding: EdgeInsetsGeometry.fromLTRB(2, 2, 2, 2),
            child: Wrap(
              spacing: 8,
              children: widget.badges.map((i) => buildBadge(i)).toList(),
            )),
      ),
    );
  }
}

String get profileMenuChangeDisplayName => Intl.message("Change display name",
    name: "profileMenuChangeDisplayName",
    desc: "Profile menu item for changing your own display name");

String get profileMenuChangeDisplayNameTooltip =>
    Intl.message("The name everyone sees for you",
        name: "profileMenuChangeDisplayNameTooltip",
        desc: "Tooltip of the profile menu item 'Change Display Name'");

String get profileMenuChangeProfilePicture =>
    Intl.message("Change profile picture",
        name: "profileMenuChangeProfilePicture",
        desc: "Profile menu item for changing your own profile picture");

String get profileMenuChangeProfilePictureTooltip =>
    Intl.message("The picture shown next to your name",
        name: "profileMenuChangeProfilePictureTooltip",
        desc: "Tooltip of the profile menu item 'Change profile picture'");

String get profileMenuBannerTooltip =>
    Intl.message("The picture at the top of your profile",
        name: "profileMenuBannerTooltip",
        desc: "Tooltip of the profile menu item 'Change Banner'");

String get profileMenuStatusTooltip =>
    Intl.message("A short message shown next to your name",
        name: "profileMenuStatusTooltip",
        desc: "Tooltip of the profile menu item for setting a status");

String get profileMenuBadgesTooltip =>
    Intl.message("Little badges shown on your profile",
        name: "profileMenuBadgesTooltip",
        desc: "Tooltip of the profile menu item for setting badges");

String get profileMenuBioTooltip =>
    Intl.message("A few lines about yourself, shown on your profile",
        name: "profileMenuBioTooltip",
        desc: "Tooltip of the profile menu item for setting a bio");

String get profileMenuTimezoneTooltip =>
    Intl.message("Show others your local time on your profile",
        name: "profileMenuTimezoneTooltip",
        desc: "Tooltip of the profile menu item for sharing your timezone");

String get profileMenuColorSchemeTooltip => Intl.message(
    "The colors of your profile card",
    name: "profileMenuColorSchemeTooltip",
    desc:
        "Tooltip of the profile menu item for editing the profile colour scheme");

String get profileMenuColorOverrideTooltip => Intl.message(
    "Pick the color this person's name has for you (only you see it)",
    name: "profileMenuColorOverrideTooltip",
    desc:
        "Tooltip of the profile menu item for overriding someone's name colour");

String get profileMenuSetNickname => Intl.message("Set nickname",
    name: "profileMenuSetNickname",
    desc:
        "Profile menu item and dialog title for setting a private nickname for another user");

String get profileMenuSetNicknameTooltip => Intl.message(
    "A name only you see for this person, instead of their display name",
    name: "profileMenuSetNicknameTooltip",
    desc: "Tooltip of the profile menu item 'Set Nickname'");

String get profileMenuNicknameHint => Intl.message("Only visible to you",
    name: "profileMenuNicknameHint", desc: "Hint in the nickname text field");

String get profileMenuBlock => Intl.message("Block",
    name: "profileMenuBlock", desc: "Profile menu item that blocks the user");

String get profileMenuBlockTooltip => Intl.message(
    "Hide their messages, invites, and calls on all your devices. They aren't told.",
    name: "profileMenuBlockTooltip",
    desc: "Tooltip of the profile menu item 'Block'");

String get profileMenuUnblock => Intl.message("Unblock",
    name: "profileMenuUnblock",
    desc: "Profile menu item that unblocks the user");

String get profileMenuUnblockTooltip =>
    Intl.message("Show their messages, invites, and calls again",
        name: "profileMenuUnblockTooltip",
        desc: "Tooltip of the profile menu item 'Unblock'");
