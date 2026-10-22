// Vommet: rows of the Telegram-style unified chat list (Vommet issue 291).
// Presentational only: they draw the models from unified_chat_model.dart and
// report taps, so renders and tests can use them without a client.
import 'package:commet/client/room.dart';
import 'package:commet/ui/atoms/list_trust_marker.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:flutter/material.dart';

// Vommet issue 521: the classic list's unread dot.
import 'package:commet/ui/atoms/dot_indicator.dart';

const _voiceGreen = Color(0xff23a55a);

TextStyle? _nameStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 15,
        color: Theme.of(context).colorScheme.onSurface);

TextStyle? _bodyStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodyMedium
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

// Vommet: a DM's topic line, quieter than the preview (Vommet issue 564).
TextStyle? _topicStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(fontSize: 12, color: Theme.of(context).colorScheme.secondary);

TextStyle? _timeStyle(BuildContext context, {bool unread = false}) =>
    Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 12,
        color: unread
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.secondary);

/// A chat's picture: round for chats, a rounded square for spaces.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.name,
    this.image,
    this.color = Colors.grey,
    this.size = 48,
    this.square = false,
  });

  final String name;
  final ImageProvider? image;
  final Color color;
  final double size;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final letter =
        name.trim().isEmpty ? "?" : name.trim().characters.first.toUpperCase();

    Widget child = image != null
        ? Image(
            image: image!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => _placeholder(context, letter))
        : _placeholder(context, letter);

    return SizedBox(
      width: size,
      height: size,
      child: square
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size / 4.4), child: child)
          : ClipOval(child: child),
    );
  }

  Widget _placeholder(BuildContext context, String letter) => ColoredBox(
        color: color,
        child: Center(
          child: Text(letter,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
      );
}

/// An unread count; grey when the chat is muted.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key, this.muted = false});
  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Pill(
      color: muted ? scheme.outline : scheme.primary,
      text: count > 999 ? "999+" : "$count",
      textColor: muted ? Colors.white : scheme.onPrimary,
    );
  }
}

/// The "@" shown when you were mentioned.
class MentionBadge extends StatelessWidget {
  const MentionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Pill(color: scheme.error, text: "@", textColor: scheme.onError);
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.color, required this.text, required this.textColor});
  final Color color;
  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: textColor)),
    );
  }
}

/// The badges at the end of a row: "@" for mentions, then the count. With
/// neither, an unread [marked] chat gets the classic list's dot.
class ChatBadges extends StatelessWidget {
  const ChatBadges(
      {super.key,
      this.unread = 0,
      this.mentions = 0,
      this.marked = false,
      this.muted = false});
  final int unread;
  final int mentions;
  final bool marked;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (unread <= 0 && mentions <= 0) {
      return marked
          ? const Padding(padding: EdgeInsets.all(5), child: DotIndicator())
          : const SizedBox.shrink();
    }
    return Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
      if (mentions > 0) const MentionBadge(),
      if (unread > 0) UnreadBadge(unread, muted: muted),
    ]);
  }
}

/// "Sender: preview" with the sender emphasised.
class SenderPreview extends StatelessWidget {
  const SenderPreview(
      {super.key, this.sender, this.preview, this.maxLines = 1});
  final String? sender;
  final String? preview;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final body = _bodyStyle(context);
    final text = (preview ?? "").replaceAll("\n", " ");
    return Text.rich(
      TextSpan(children: [
        if (sender != null)
          TextSpan(
              text: "$sender: ",
              style: body?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500)),
        TextSpan(text: text),
      ]),
      style: body,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The small icon before a chat's name: # for rooms, a speaker for voice
/// rooms, nothing for DMs. The speaker is green only while people are in the
/// call ([voiceActive]); an empty voice room gets the muted # colour.
Widget? chatKindIcon(BuildContext context, ChatKind kind,
    {double size = 16, bool voiceActive = false}) {
  final color = Theme.of(context).colorScheme.secondary;
  return switch (kind) {
    ChatKind.direct => null,
    ChatKind.room => Icon(Icons.tag, size: size, color: color),
    ChatKind.voice => Icon(Icons.volume_up,
        size: size, color: voiceActive ? _voiceGreen : color),
  };
}

class _RowShell extends StatelessWidget {
  const _RowShell({required this.child, this.selected = false, this.onTap});
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withAlpha(150)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8), child: child),
        ),
      ),
    );
  }
}

/// Name, muted mark and time on one line.
class _TitleLine extends StatelessWidget {
  const _TitleLine(
      {required this.name,
      this.leading,
      this.afterName,
      this.muted = false,
      this.pinned = false,
      this.time,
      this.unread = false});
  final String name;
  final Widget? leading;

  /// Vommet: a DM trust marker right after the name (Vommet issue 131).
  final Widget? afterName;
  final bool muted;
  final bool pinned;
  final String? time;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.secondary;
    return Row(children: [
      if (leading != null)
        Padding(padding: const EdgeInsets.only(right: 4), child: leading),
      Expanded(
        child: Row(children: [
          Flexible(
            child: Text(name,
                style: _nameStyle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (afterName != null) afterName!,
          if (muted)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.volume_off, size: 14, color: secondary),
            ),
        ]),
      ),
      if (pinned)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(Icons.push_pin, size: 13, color: secondary),
        ),
      if (time != null)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(time!, style: _timeStyle(context, unread: unread)),
        ),
    ]);
  }
}

String? _time(BuildContext context, DateTime? time, DateTime now) =>
    time == null
        ? null
        : formatChatTime(time, now,
            use24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat);

/// A DM or room in the top-level list.
class ChatRowTile extends StatelessWidget {
  const ChatRowTile(this.chat,
      {super.key,
      required this.now,
      this.selected = false,
      this.pinned = false,
      this.onTap});

  final ChatEntry chat;
  final DateTime now;
  final bool selected;
  final bool pinned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final unread = chat.unread > 0 || chat.mentions > 0;
    return _RowShell(
      selected: selected,
      onTap: onTap,
      child: Row(children: [
        ChatAvatar(
            name: chat.name, image: chat.avatar, color: chat.color, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _TitleLine(
                    name: chat.name,
                    leading: chatKindIcon(context, chat.kind,
                        voiceActive: chat.voiceCount > 0),
                    afterName: chat.isDirect && chat.source is Room
                        ? ListTrustMarker(chat.source as Room)
                        : null,
                    muted: chat.muted,
                    pinned: pinned,
                    time: _time(context, chat.lastActivity, now),
                    unread: unread && !chat.muted),
                if (chat.topic != null)
                  Text(chat.topic!,
                      style: _topicStyle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                      child: chat.voiceCount > 0
                          ? _VoiceLine(chat)
                          : SenderPreview(
                              sender: chat.sender?.call(),
                              preview: chat.preview)),
                  ChatBadges(
                      unread: chat.unread,
                      mentions: chat.mentions,
                      marked: chat.unreadMark,
                      muted: chat.muted),
                ]),
              ]),
        ),
      ]),
    );
  }
}

/// One room as a chip on a space's row.
class RoomChip extends StatelessWidget {
  const RoomChip(this.room, {super.key, this.highlighted = false});
  final ChatEntry room;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: highlighted ? scheme.onSurface : scheme.onSurfaceVariant,
        fontWeight: highlighted ? FontWeight.w700 : FontWeight.w400);
    final icon = chatKindIcon(context, room.kind,
            size: 14, voiceActive: room.voiceCount > 0) ??
        Icon(Icons.tag, size: 14, color: scheme.secondary);

    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: highlighted
          ? BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8))
          : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        icon,
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(room.name,
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// The chip line: rooms most recently active first, clipped at the edge.
class RoomChips extends StatelessWidget {
  const RoomChips(this.chips, {super.key});
  final List<ChatEntry> chips;

  @override
  Widget build(BuildContext context) {
    // Fade the last chip out instead of cutting it off at the badges.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.85, 1],
      ).createShader(bounds),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(children: [
          for (var i = 0; i < chips.length; i++)
            RoomChip(chips[i],
                highlighted: i == 0 && chips[i].lastActivity != null),
        ]),
      ),
    );
  }
}

/// "3 in Tabletop", green.
class _VoiceLine extends StatelessWidget {
  const _VoiceLine(this.room, {this.withRoomName = false});
  final ChatEntry room;
  final bool withRoomName;

  @override
  Widget build(BuildContext context) {
    final names = room.voiceNames?.call() ?? const <String>[];
    final who = withRoomName || names.isEmpty
        ? "${room.voiceCount} in ${room.name}"
        : "${_joinNames(names)} in voice";
    return Row(children: [
      const Icon(Icons.volume_up, size: 14, color: _voiceGreen),
      const SizedBox(width: 4),
      Flexible(
        child: Text(who,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: _voiceGreen, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

String _joinNames(List<String> names) {
  if (names.length <= 2) return names.join(", ");
  return "${names.take(2).join(", ")} +${names.length - 2}";
}

/// A top-level space, like a Telegram forum group.
class SpaceRowTile extends StatelessWidget {
  const SpaceRowTile(this.space, this.digest,
      {super.key,
      required this.now,
      this.selected = false,
      this.pinned = false,
      this.onTap});

  final SpaceEntry space;
  final SpaceDigest digest;
  final DateTime now;
  final bool selected;
  final bool pinned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final latest = digest.latest;
    final secondary = Theme.of(context).colorScheme.secondary;
    return _RowShell(
      selected: selected,
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: ChatAvatar(
              name: space.name,
              image: space.avatar,
              color: space.color,
              size: 52,
              square: true),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _TitleLine(
                    name: space.name,
                    leading: Icon(Icons.workspaces_outline,
                        size: 15, color: secondary),
                    muted: space.muted,
                    pinned: pinned,
                    time: _time(context, digest.lastActivity, now),
                    unread: digest.unread > 0 && !space.muted),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                      child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: RoomChips(digest.chips))),
                  ChatBadges(
                      unread: digest.unread,
                      mentions: digest.mentions,
                      marked: digest.unreadMark,
                      muted: space.muted),
                ]),
                const SizedBox(height: 3),
                if (latest != null)
                  SenderPreview(
                      sender: latest.sender?.call(), preview: latest.preview),
                if (digest.voice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _VoiceLine(digest.voice!, withRoomName: true),
                  ),
              ]),
        ),
      ]),
    );
  }
}

/// The Invitations row at the top of the list.
class InvitationsRowTile extends StatelessWidget {
  const InvitationsRowTile(
      {super.key, required this.count, this.subtitle, this.onTap});
  final int count;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _RowShell(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: scheme.secondaryContainer, shape: BoxShape.circle),
          child: Icon(Icons.mail_outline, color: scheme.onSecondaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Invitations", style: _nameStyle(context)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _bodyStyle(context)),
              ]),
        ),
        UnreadBadge(count),
      ]),
    );
  }
}

/// A room in an open space's pane.
class SpaceRoomTile extends StatelessWidget {
  const SpaceRoomTile(this.room,
      {super.key,
      required this.now,
      this.selected = false,
      this.onTap,
      this.onJoinVoice});

  final ChatEntry room;
  final DateTime now;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onJoinVoice;

  @override
  Widget build(BuildContext context) {
    final inVoice = room.kind == ChatKind.voice && room.voiceCount > 0;
    final leading = room.kind == ChatKind.direct
        ? ChatAvatar(
            name: room.name, image: room.avatar, color: room.color, size: 28)
        : chatKindIcon(context, room.kind, size: 22, voiceActive: inVoice);
    return _RowShell(
      selected: selected,
      onTap: onTap,
      child: Row(children: [
        SizedBox(width: 34, child: Center(child: leading)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _TitleLine(
                    name: room.name,
                    muted: room.muted,
                    time:
                        inVoice ? null : _time(context, room.lastActivity, now),
                    unread: room.unread > 0 && !room.muted),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                    child: inVoice
                        ? _VoiceLine(room)
                        : SenderPreview(
                            sender: room.sender?.call(), preview: room.preview),
                  ),
                  if (inVoice && onJoinVoice != null)
                    _JoinButton(onPressed: onJoinVoice!)
                  else
                    ChatBadges(
                        unread: room.unread,
                        mentions: room.mentions,
                        marked: room.unreadMark,
                        muted: room.muted),
                ]),
              ]),
        ),
      ]),
    );
  }
}

class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: _voiceGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        onPressed: onPressed,
        child: const Text("Join"),
      ),
    );
  }
}

/// A room of the space that we haven't joined.
class SpacePreviewTile extends StatelessWidget {
  const SpacePreviewTile(this.preview, {super.key, this.onTap});
  final ChatPreviewEntry preview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.secondary;
    return Opacity(
      opacity: 0.7,
      child: _RowShell(
        onTap: onTap,
        child: Row(children: [
          SizedBox(
              width: 34,
              child: Icon(preview.isVoice ? Icons.volume_up : Icons.tag,
                  size: 22, color: secondary)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(preview.name,
                style: _nameStyle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text(
              preview.memberCount == null
                  ? "Join"
                  : "${preview.memberCount} members · Join",
              style: _timeStyle(context)),
        ]),
      ),
    );
  }
}

/// A subspace in an open space's pane; tapping it drills in.
class SubspaceTile extends StatelessWidget {
  const SubspaceTile(this.space, this.digest,
      {super.key, required this.now, this.onTap});

  final SpaceEntry space;
  final SpaceDigest digest;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.secondary;
    return _RowShell(
      onTap: onTap,
      child: Row(children: [
        SizedBox(
          width: 34,
          child: Center(
            child: ChatAvatar(
                name: space.name,
                image: space.avatar,
                color: space.color,
                size: 30,
                square: true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _TitleLine(
                    name: space.name,
                    leading: Icon(Icons.workspaces_outline,
                        size: 15, color: secondary),
                    muted: space.muted,
                    time: _time(context, digest.lastActivity, now)),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                      child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: RoomChips(digest.chips))),
                  ChatBadges(
                      unread: digest.unread,
                      mentions: digest.mentions,
                      marked: digest.unreadMark,
                      muted: space.muted),
                  Icon(Icons.chevron_right, size: 20, color: secondary),
                ]),
              ]),
        ),
      ]),
    );
  }
}

/// A top-level chat or space as an avatar in the folded column, with its
/// unread count.
class FoldedAvatar extends StatelessWidget {
  const FoldedAvatar(
      {super.key,
      required this.name,
      this.image,
      this.color = Colors.grey,
      this.square = false,
      this.unread = 0,
      this.mentions = 0,
      this.marked = false,
      this.muted = false,
      this.selected = false,
      this.onTap});

  final String name;
  final ImageProvider? image;
  final Color color;
  final bool square;
  final int unread;
  final int mentions;
  final bool marked;
  final bool muted;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        height: 58,
        child: Stack(children: [
          if (selected)
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(4))),
              ),
            ),
          Center(
            child: InkWell(
              onTap: onTap,
              customBorder: square
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11))
                  : const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ChatAvatar(
                    name: name,
                    image: image,
                    color: color,
                    size: 44,
                    square: square),
              ),
            ),
          ),
          if (unread > 0 || mentions > 0)
            Positioned(
              right: 6,
              bottom: 4,
              child: mentions > 0 && unread == 0
                  ? const MentionBadge()
                  : UnreadBadge(unread > 0 ? unread : mentions, muted: muted),
            )
          else if (marked)
            const Positioned(right: 9, bottom: 7, child: DotIndicator()),
        ]),
      ),
    );
  }
}
