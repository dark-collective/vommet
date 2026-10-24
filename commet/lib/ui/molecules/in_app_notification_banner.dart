import 'dart:async';

import 'package:commet/client/components/push_notification/invite_alerts.dart';
import 'package:commet/client/components/push_notification/modifiers/in_app_banner.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/invitation_view/invite_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Shows message notifications at the top of the app while it is open.
/// Tap opens the room (an invite opens Home, Vommet issue 550); swipe up or
/// wait to dismiss. Wraps [child] (the banner itself is drawn in the root
/// overlay).
class InAppNotificationBannerHost extends StatefulWidget {
  const InAppNotificationBannerHost({this.child, super.key});

  final Widget? child;

  static const visibleFor = Duration(seconds: 4);

  @override
  State<InAppNotificationBannerHost> createState() =>
      _InAppNotificationBannerHostState();
}

class _InAppNotificationBannerHostState
    extends State<InAppNotificationBannerHost> {
  StreamSubscription? subscription;
  NotificationContent? current;
  Timer? hideTimer;

  /// The banner is drawn in the root overlay, above pushed pages (settings)
  /// and dialogs; this widget itself only listens.
  OverlayEntry? entry;

  @override
  void initState() {
    subscription =
        NotificationModifierInAppBanner.banners.stream.listen(onBanner);
    super.initState();
  }

  @override
  void dispose() {
    subscription?.cancel();
    hideTimer?.cancel();
    entry?.remove();
    entry = null;
    super.dispose();
  }

  void onBanner(NotificationContent content) {
    if (!mounted) return;
    hideTimer?.cancel();
    hideTimer = Timer(InAppNotificationBannerHost.visibleFor, dismiss);
    current = content;

    if (entry == null) {
      entry = OverlayEntry(builder: buildLayer);
      Overlay.of(context, rootOverlay: true).insert(entry!);
    } else {
      entry!.markNeedsBuild();
    }
  }

  void dismiss() {
    hideTimer?.cancel();
    if (current == null) return;
    current = null;
    entry?.markNeedsBuild();

    // Let the slide-out finish, unless a new banner arrived meanwhile.
    Timer(const Duration(milliseconds: 250), () {
      if (current == null) {
        entry?.remove();
        entry = null;
      }
    });
  }

  void open(NotificationContent content) {
    dismiss();
    switch (content) {
      case MessageNotificationContent _:
        EventBus.doOpenRoom(content.roomId, clientId: content.clientId);
      case RoomInviteNotificationContent _:
        EventBus.openHomeScreen.add(null);
      default:
    }
  }

  static Object keyOf(NotificationContent content) => switch (content) {
        MessageNotificationContent c => c.eventId,
        RoomInviteNotificationContent c => "invite:${c.clientId}:${c.roomId}",
        _ => content,
      };

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();

  Widget buildLayer(BuildContext context) {
    final content = current;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween(begin: const Offset(0, -1), end: Offset.zero)
                .animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: content == null
              ? const SizedBox.shrink()
              : Dismissible(
                  key: ValueKey(keyOf(content)),
                  direction: DismissDirection.up,
                  onDismissed: (_) => dismiss(),
                  child: switch (content) {
                    MessageNotificationContent c => buildBanner(context, c),
                    RoomInviteNotificationContent c =>
                      buildInviteBanner(context, c),
                    _ => const SizedBox.shrink(),
                  },
                ),
        ),
      ),
    );
  }

  Widget buildBanner(BuildContext context, MessageNotificationContent content) {
    // Vommet: redacted mode (Vommet issue 400).
    final redaction = RedactionScope.of(context);
    final senderName = redaction.name(content.senderName, content.senderId);
    final title = content.isDirectMessage
        ? senderName
        : "$senderName · ${redaction.roomName(content.roomName, content.roomId)}";

    return buildFrame(context,
        content: content,
        title: title,
        body: redaction.text(content.content),
        image: content.senderImage ?? content.roomImage,
        placeholderText: content.senderName,
        colorKey: content.senderId);
  }

  /// Vommet issue 550: "<inviter>" over "invited you to <room>".
  Widget buildInviteBanner(
      BuildContext context, RoomInviteNotificationContent content) {
    final redaction = RedactionScope.of(context);
    final inviterKey = content.inviterId ?? content.roomId;
    final roomName = redaction.roomName(content.roomName, content.roomId);

    return buildFrame(context,
        content: content,
        title: redaction.name(content.inviterName, inviterKey),
        body: content.isDirect
            ? inviteWantsDm
            : InviteAlerts.inviteBannerInvitedYouTo(roomName),
        image: content.isDirect ? null : content.roomImage,
        placeholderText: content.inviterName,
        colorKey: inviterKey);
  }

  Widget buildFrame(BuildContext context,
      {required NotificationContent content,
      required String title,
      required String body,
      required ImageProvider? image,
      required String placeholderText,
      required String colorKey}) {
    final colors = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          elevation: 6,
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => open(content),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  tiamat.Avatar(
                    radius: 18,
                    image: image,
                    placeholderText: placeholderText,
                    placeholderColor: MatrixPeer.hashColor(colorKey),
                    redactionKey: colorKey,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tiamat.Text.labelEmphasised(title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        tiamat.Text.labelLow(body,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
