import 'dart:async';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: the DM panel's header above its tabs: the other person's name
/// (unless the bar above already shows it) and their status message, on
/// every tab (Vommet issue 602).
class DmPanelHeader extends StatefulWidget {
  const DmPanelHeader(this.room, {this.showName = true, super.key});
  final Room room;
  final bool showName;

  @override
  State<DmPanelHeader> createState() => _DmPanelHeaderState();
}

class _DmPanelHeaderState extends State<DmPanelHeader> {
  String? userId;
  String? status;
  StreamSubscription? _presence;

  @override
  void initState() {
    super.initState();
    final client = widget.room.client;
    userId = client
        .getComponent<DirectMessagesComponent>()
        ?.getDirectMessagePartnerId(widget.room);
    final id = userId;
    if (id == null) return;
    final presence = client.getComponent<UserPresenceComponent>();
    status = presence?.cachedPresence(id)?.message?.message;
    _presence = presence?.onPresenceChanged
        .where((e) => e.$1 == id)
        .listen((e) => _setStatus(e.$2.message?.message));
    client.getComponent<UserProfileComponent>()?.getProfile(id).then((profile) {
      if (profile case ProfileWithPresence p) {
        final message = p.precence?.message?.message;
        if (message != null) _setStatus(message);
      }
    });
  }

  void _setStatus(String? message) {
    final text = message?.trim();
    if (!mounted) return;
    setState(() => status = text == null || text.isEmpty ? null : text);
  }

  @override
  void dispose() {
    _presence?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final id = userId;
    if (id == null || (!widget.showName && status == null)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      key: const ValueKey("dm-panel-header"),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showName)
            Text(widget.room.getMemberOrFallback(id).displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600, color: scheme.onSurface)),
          if (status != null)
            Text(status,
                key: const ValueKey("dm-panel-header-status"),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Vommet: "Shared in this chat" under the DM Profile tab's card: how many
/// photos and videos, GIFs, files, voice messages and links the chat has.
/// Each row opens its tab with the matching chip picked (Vommet issue 602).
class DmSharedCounts extends StatelessWidget {
  const DmSharedCounts(this.counts, {required this.onOpen, super.key});
  final SharedContentCounts counts;
  final ValueChanged<SharedCategory> onOpen;

  static String get dmSharedHeader => Intl.message("Shared in this chat",
      name: "dmSharedHeader",
      desc: "DM side panel, Profile tab: header above the counts of photos, "
          "files, links etc. sent in the chat");

  static String get dmSharedPhotosAndVideos => Intl.message("Photos and videos",
      name: "dmSharedPhotosAndVideos",
      desc: "DM side panel, Profile tab: row counting pictures and videos "
          "sent in the chat");

  static String get dmSharedGifs => Intl.message("GIFs",
      name: "dmSharedGifs",
      desc: "DM side panel, Profile tab: row counting GIFs sent in the chat");

  static String get dmSharedFiles => Intl.message("Files",
      name: "dmSharedFiles",
      desc: "DM side panel, Profile tab: row counting files sent in the chat");

  static String get dmSharedVoice => Intl.message("Voice messages",
      name: "dmSharedVoice",
      desc: "DM side panel, Profile tab: row counting voice messages sent in "
          "the chat");

  static String get dmSharedLinks => Intl.message("Shared links",
      name: "dmSharedLinks",
      desc: "DM side panel, Profile tab: row counting links sent in the chat");

  static String dmSharedScanning(String when) =>
      Intl.message("Looking through older messages: $when so far",
          name: "dmSharedScanning",
          args: [when],
          desc: "DM side panel, Profile tab: under the counts while older "
              "messages are still being counted; when is a month and year, "
              "e.g. 'March 2026'");

  static String get dmSharedScanningStart =>
      Intl.message("Looking through older messages…",
          name: "dmSharedScanningStart",
          desc: "DM side panel, Profile tab: under the counts while older "
              "messages are still being counted, before any are loaded");

  static String label(SharedCategory category) => switch (category) {
        SharedCategory.photosAndVideos => dmSharedPhotosAndVideos,
        SharedCategory.gifs => dmSharedGifs,
        SharedCategory.files => dmSharedFiles,
        SharedCategory.voice => dmSharedVoice,
        SharedCategory.links => dmSharedLinks,
      };

  static (IconData, Color) _icon(SharedCategory category) => switch (category) {
        SharedCategory.photosAndVideos => (Icons.photo, Color(0xff3ba55d)),
        SharedCategory.gifs => (Icons.gif_box, Color(0xfffaa61a)),
        SharedCategory.files => (Icons.insert_drive_file, Color(0xff8e9297)),
        SharedCategory.voice => (Icons.mic, Color(0xffeb459e)),
        SharedCategory.links => (Icons.link, Color(0xff00a8fc)),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: counts,
      builder: (context, _) {
        // Keep counting while this is on screen (not behind a dialog).
        final covered = ModalRoute.of(context)?.isCurrent == false;
        if (!counts.complete && !covered) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) counts.countMore();
          });
        }
        final back = counts.scannedBackTo;
        return Padding(
          key: const ValueKey("dm-shared-counts"),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Text(dmSharedHeader.toUpperCase(),
                    style: text.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: scheme.onSurfaceVariant)),
              ),
              for (final category in SharedCategory.values)
                InkWell(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  key: ValueKey("dm-shared-${category.name}"),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onOpen(category),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      spacing: 12,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                              color: _icon(category).$2,
                              borderRadius: BorderRadius.circular(7)),
                          child: Icon(_icon(category).$1,
                              size: 16, color: Colors.white),
                        ),
                        Expanded(
                          child: Text(label(category),
                              style: text.bodyMedium
                                  ?.copyWith(color: scheme.onSurface)),
                        ),
                        Text(counts.count(category).toString(),
                            style: text.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        Icon(Icons.chevron_right,
                            size: 18, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              if (!counts.complete)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Row(
                    spacing: 8,
                    children: [
                      const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5)),
                      Expanded(
                        child: Text(
                            back == null
                                ? dmSharedScanningStart
                                : dmSharedScanning(
                                    DateFormat.yMMMM().format(back)),
                            style: text.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
