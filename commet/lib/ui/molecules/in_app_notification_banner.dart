import 'dart:async';

import 'package:commet/client/components/push_notification/modifiers/in_app_banner.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Shows message notifications at the top of the app while it is open.
/// Tap opens the room; swipe up or wait to dismiss. Wraps [child] (the
/// banner itself is drawn in the root overlay).
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
  MessageNotificationContent? current;
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

  void onBanner(MessageNotificationContent content) {
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

  void open(MessageNotificationContent content) {
    dismiss();
    EventBus.doOpenRoom(content.roomId, clientId: content.clientId);
  }

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
                  key: ValueKey(content.eventId),
                  direction: DismissDirection.up,
                  onDismissed: (_) => dismiss(),
                  child: buildBanner(context, content),
                ),
        ),
      ),
    );
  }

  Widget buildBanner(BuildContext context, MessageNotificationContent content) {
    final colors = Theme.of(context).colorScheme;
    final title = content.isDirectMessage
        ? content.senderName
        : "${content.senderName} · ${content.roomName}";
    final image = content.senderImage ?? content.roomImage;

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
                    placeholderText: content.senderName,
                    placeholderColor: MatrixPeer.hashColor(content.senderId),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tiamat.Text.labelEmphasised(title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        tiamat.Text.labelLow(content.content,
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
