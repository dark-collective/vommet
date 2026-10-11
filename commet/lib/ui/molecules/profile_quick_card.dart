import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_server_features.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/image_select_dialog.dart';
import 'package:commet/ui/molecules/user_panel.dart' show UserPanelView;
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Discord-style card that opens from the user panel: status
/// message, edit profile, presence (online / idle / invisible), switch
/// accounts and copy user id.
class ProfileQuickCard extends StatefulWidget {
  const ProfileQuickCard(
      {required this.client, required this.hostContext, super.key});
  final Client client;

  /// Context of the user panel, which outlives the card, for navigating.
  final BuildContext hostContext;

  static const double width = 300;

  /// Opens the card just above the widget [context] belongs to.
  static Future<void> show(BuildContext context, {required Client client}) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;

    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Profile",
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, _, __) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final maxLeft = screen.width - width - 8.0;
        final left = maxLeft < 8.0 ? 8.0 : origin.dx.clamp(8.0, maxLeft);
        return Stack(children: [
          Positioned(
            left: left,
            bottom: screen.height - origin.dy + 8,
            width: width,
            child: ProfileQuickCard(client: client, hostContext: context),
          ),
        ]);
      },
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          alignment: Alignment.bottomLeft,
          scale: Tween(begin: 0.96, end: 1.0).animate(animation),
          child: child,
        ),
      ),
    );
  }

  @override
  State<ProfileQuickCard> createState() => _ProfileQuickCardState();
}

class _ProfileQuickCardState extends State<ProfileQuickCard> {
  static const modes = {
    "online": (
      "Online",
      "Follows whether you're using Vommet",
      UserPresenceStatus.online
    ),
    "idle": (
      "Idle",
      "Shown as away until you change it",
      UserPresenceStatus.unavailable
    ),
    "invisible": (
      "Invisible",
      "Appear offline, but keep using Vommet",
      UserPresenceStatus.offline
    ),
  };

  UserPresenceComponent? presenceComponent;
  UserProfileComponent? profileComponent;
  String? statusMessage;
  StreamSubscription? sub;

  /// What the homeserver supports; until known, nothing is offered.
  MatrixServerFeatures? features;

  /// Shown right away after a change, before the profile reloads.
  ImageProvider? avatarOverride;
  ImageProvider? bannerOverride;
  bool bannerRemoved = false;

  /// Vommet: the client's cached own profile has no profile fields, so its
  /// banner is always null; the card showed only the colour. Load the full
  /// profile (as the profile page does) for the banner.
  ImageProvider? loadedBanner;

  @override
  void initState() {
    presenceComponent = widget.client.getComponent<UserPresenceComponent>();
    profileComponent = widget.client.getComponent<UserProfileComponent>();
    loadBanner();
    if (widget.client case MatrixClient client) {
      MatrixServerFeatures.of(client).then((f) {
        if (!mounted) return;
        setState(() => features = f);
        loadStatusMessage();
      });
    }
    super.initState();
  }

  Future<void> loadBanner() async {
    final self = widget.client.self?.identifier;
    if (self == null || profileComponent == null) return;
    try {
      final profile = await profileComponent!.getProfile(self);
      if (mounted && profile.banner != null) {
        setState(() => loadedBanner = profile.banner);
      }
    } catch (_) {
      // No banner then; the colour stays.
    }
  }

  // Vommet: read the status the way the profile page shows it: presence's
  // message, else Commet's profile field (getProfile combines the two). The
  // profile page writes both, and presence alone often comes back without
  // it, so the card used to offer "Set a status" over an existing one.
  Future<void> loadStatusMessage() async {
    final self = widget.client.self?.identifier;
    final f = features;
    if (self == null || f == null || !f.statusMessage) return;

    if (f.presence && presenceComponent != null) {
      sub = presenceComponent!.onPresenceChanged
          .where((e) => e.$1 == self && e.$2.message != null)
          .listen((e) => setState(() => statusMessage = e.$2.message?.message));
    }
    if (profileComponent == null) return;
    try {
      final profile = await profileComponent!.getProfile(self);
      if (profile is ProfileWithPresence && mounted) {
        setState(() => statusMessage =
            (profile as ProfileWithPresence).precence?.message?.message);
      }
    } catch (_) {
      // Leave the bubble as "Set a status".
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  String get mode => presenceComponent?.presenceMode ?? "online";

  void close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final self = widget.client.self;
    final scheme = ColorScheme.of(context);
    if (self == null) return const SizedBox();

    return Material(
      color: scheme.surfaceContainer,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              children: [
                banner(context, self),
                Positioned(
                  left: 16,
                  top: 56,
                  child: avatar(context, self),
                ),
                if (features?.statusMessage == true)
                  Positioned(
                    left: 120,
                    right: 12,
                    top: 104,
                    child: statusBubble(context),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(self.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(self.identifier,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          section([
            row(
              leading: const Icon(Icons.edit_rounded, size: 18),
              label: "Edit Profile",
              onTap: () {
                close();
                SettingsNavigation.openProfile(widget.hostContext);
              },
            ),
            if (presenceComponent != null && features?.presence == true)
              presenceRow(context),
          ]),
          section([
            if (clientManager!.clients.length > 1) accountsRow(context),
            row(
              leading: const Icon(Icons.badge_outlined, size: 18),
              label: "Copy User ID",
              onTap: () {
                Clipboard.setData(ClipboardData(text: self.identifier));
                close();
              },
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // Discord's popup: a banner across the top, the avatar overlapping its
  // bottom edge, each editable in place when the server allows it.
  Widget banner(BuildContext context, Profile self) {
    final image =
        bannerRemoved ? null : bannerOverride ?? loadedBanner ?? self.banner;
    final canEdit = features?.banner == true && profileComponent != null;

    return SizedBox(
      height: 100,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: self.defaultColor.withValues(alpha: 0.6),
              image: image == null
                  ? null
                  : DecorationImage(image: image, fit: BoxFit.cover),
            ),
          ),
          if (canEdit)
            Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: "Change banner",
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => editBanner(image),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.edit_rounded,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget avatar(BuildContext context, Profile self) {
    final scheme = ColorScheme.of(context);
    final canEdit = features?.avatar == true;

    final picture = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surfaceContainer, width: 5),
      ),
      child: tiamat.Avatar(
        radius: 40,
        image: avatarOverride ?? self.avatar,
        placeholderColor: self.defaultColor,
        placeholderText: self.displayName,
      ),
    );

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        if (canEdit)
          Tooltip(
            message: "Change avatar",
            child: _HoverEdit(onTap: editAvatar, child: picture),
          )
        else
          picture,
        if (features?.presence == true)
          Padding(
            padding: const EdgeInsets.all(7),
            child: Transform.scale(
              scale: 1.8,
              child: UserPanelView.createPresenceIcon(context, modes[mode]!.$3),
            ),
          ),
      ],
    );
  }

  Future<void> editAvatar() async {
    final bytes = await PickerUtils.pickImageAndCrop(context, aspectRatio: 1.0);
    if (bytes == null) return;
    setState(() => avatarOverride = Image.memory(bytes).image);
    await widget.client.setAvatar(bytes, "");
  }

  Future<void> editBanner(ImageProvider? current) async {
    final action = await ImageSelectDialog.show(context, image: current);
    if (!mounted) return;

    if (action == ImageEditAction.remove) {
      setState(() => bannerRemoved = true);
      await profileComponent!.removeBanner();
      return;
    }
    if (action != ImageEditAction.pick) return;

    final bytes =
        await PickerUtils.pickImageAndCrop(context, aspectRatio: 700 / 230);
    if (bytes == null) return;
    setState(() {
      bannerRemoved = false;
      bannerOverride = Image.memory(bytes).image;
    });
    await profileComponent!.setBanner(bytes);
  }

  Widget statusBubble(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: editStatusMessage,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                if (statusMessage == null)
                  Icon(Icons.add_circle_rounded,
                      size: 14, color: scheme.onSurfaceVariant),
                Flexible(
                  child: Text(
                    statusMessage ?? "Set a status",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: statusMessage == null
                            ? FontStyle.italic
                            : FontStyle.normal),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> editStatusMessage() async {
    final text = await AdaptiveDialog.textPrompt(context,
        title: "Set a status",
        submitText: "Save",
        hintText: "What's on your mind? (empty to clear)",
        initialText: statusMessage);
    if (text == null) return;

    // Written to both places, as the profile page does, so the two never
    // disagree.
    final message = text.trim();
    final f = features;
    if (f == null || !f.statusMessage) return;
    if (f.profileStatus && profileComponent != null) {
      await profileComponent!.setStatus(message.isEmpty ? null : message);
    }
    if (f.presence && presenceComponent != null) {
      await presenceComponent!.setStatus(UserPresenceStatus.online,
          message: message.isEmpty ? null : message,
          clearMessage: message.isEmpty);
    }
    if (mounted) {
      setState(() => statusMessage = message.isEmpty ? null : message);
    }
  }

  Widget presenceRow(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(ProfileQuickCard.width - 24, -40),
      menuChildren: [
        for (var entry in modes.entries)
          MenuItemButton(
            leadingIcon: SizedBox(
              width: 20,
              child: Center(
                  child: UserPanelView.createPresenceIcon(
                      context, entry.value.$3)),
            ),
            trailingIcon: entry.key == mode
                ? const Icon(Icons.check_rounded, size: 18)
                : null,
            onPressed: () async {
              await presenceComponent!.setPresenceMode(entry.key);
              if (mounted) setState(() {});
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.value.$1),
                Text(entry.value.$2,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
      ],
      builder: (context, controller, _) => row(
        leading: SizedBox(
          width: 18,
          child: Center(
              child:
                  UserPanelView.createPresenceIcon(context, modes[mode]!.$3)),
        ),
        label: modes[mode]!.$1,
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Widget accountsRow(BuildContext context) {
    void filter(Client? client) {
      EventBus.setFilterClient.add(client);
      preferences.filterClient.set(client?.identifier);
      close();
    }

    return MenuAnchor(
      alignmentOffset: const Offset(ProfileQuickCard.width - 24, -40),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.people_rounded, size: 18),
          onPressed: () => filter(null),
          child: const Text("All accounts"),
        ),
        for (var client in clientManager!.clients.where((c) => c.self != null))
          MenuItemButton(
            leadingIcon: tiamat.Avatar(
              radius: 10,
              image: client.self!.avatar,
              placeholderColor: client.self!.defaultColor,
              placeholderText: client.self!.displayName,
            ),
            onPressed: () => filter(client),
            child: Text(client.self!.identifier),
          ),
      ],
      builder: (context, controller, _) => row(
        leading: const Icon(Icons.account_circle_outlined, size: 18),
        label: "Switch Accounts",
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Widget section(List<Widget> children) {
    if (children.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Material(
        color: ColorScheme.of(context).surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget row({
    required Widget leading,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          spacing: 10,
          children: [
            leading,
            Expanded(child: Text(label)),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}

/// Darkens the avatar and shows a pencil while hovered, as Discord does.
class _HoverEdit extends StatefulWidget {
  const _HoverEdit({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_HoverEdit> createState() => _HoverEditState();
}

class _HoverEditState extends State<_HoverEdit> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            widget.child,
            AnimatedOpacity(
              opacity: hovered ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                    color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.edit_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
