import 'package:commet/client/components/room_directory/room_directory_component.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/pages/room_directory/directory_account_handle.dart';
import 'package:commet/ui/pages/room_directory/directory_strings.dart';
import 'package:commet/utils/room_directory/directory_accounts.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// One directory result. Tapping it expands it in place to show the banner,
/// full topic, badges and (for spaces) the rooms inside; tapping again folds
/// it back to a single row.
class DirectoryRow extends StatefulWidget {
  const DirectoryRow({
    required this.entry,
    required this.server,
    required this.expanded,
    required this.joining,
    required this.accounts,
    required this.image,
    required this.onToggle,
    this.details,
    super.key,
  });

  final DirectoryEntry entry;

  /// Server whose directory listed this entry (used as `via` when joining)
  final String server;
  final bool expanded;
  final DirectoryAccountHandle joining;
  final List<DirectoryAccountHandle> accounts;
  final ImageProvider? Function(Uri? url, {bool banner}) image;
  final Future<DirectoryDetails>? details;
  final VoidCallback onToggle;

  @override
  State<DirectoryRow> createState() => _DirectoryRowState();
}

class _DirectoryRowState extends State<DirectoryRow> {
  bool joiningNow = false;
  bool joinFailed = false;
  DirectoryAccountHandle? suggestion;

  static const Duration _animation = Duration(milliseconds: 220);

  @override
  void didUpdateWidget(covariant DirectoryRow oldWidget) {
    if (oldWidget.joining != widget.joining) {
      joinFailed = false;
      suggestion = null;
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> _join(DirectoryAccountHandle account) async {
    setState(() {
      joiningNow = true;
      joinFailed = false;
      suggestion = null;
    });
    try {
      await account.join(widget.entry, widget.server);
      if (mounted) setState(() => joiningNow = false);
    } catch (e, t) {
      Log.onError(e, t, content: "Joining ${widget.entry.roomId} failed");
      if (!mounted) return;
      var other = DirectoryAccounts.suggestAfterJoinFailure(widget.server,
          account.account, widget.accounts.map((a) => a.account).toList());
      setState(() {
        joiningNow = false;
        joinFailed = true;
        suggestion = other == null
            ? null
            : widget.accounts.firstWhere((a) => a.account == other);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var entry = widget.entry;

    return AnimatedContainer(
      duration: _animation,
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.symmetric(
          horizontal: 8, vertical: widget.expanded ? 6 : 1),
      decoration: BoxDecoration(
        color: widget.expanded
            ? theme.colorScheme.surfaceContainerLow
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey("directory_row_header_${entry.roomId}"),
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: _header(context),
            ),
          ),
          AnimatedSize(
            duration: _animation,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: widget.expanded
                ? _expanded(context)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    var theme = Theme.of(context);
    var entry = widget.entry;
    var joined = widget.joining.isJoined(entry.roomId);

    return Row(children: [
      tiamat.Avatar.medium(
        image: widget.image(entry.avatarUrl),
        placeholderText: entry.displayName,
        placeholderColor: MatrixPeer.hashColor(entry.roomId),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (entry.isSpace)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.workspaces_outline,
                      size: 16, color: theme.colorScheme.secondary),
                ),
              Flexible(
                child: Text(entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall),
              ),
            ]),
            Text(
              [
                if (entry.canonicalAlias != null &&
                    entry.canonicalAlias != entry.displayName)
                  entry.canonicalAlias!,
                directoryMembers(entry.memberCount),
              ].join(" · "),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (!widget.expanded && entry.topic != null)
              Text(entry.topic!.replaceAll("\n", " "),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      const SizedBox(width: 8),
      if (!widget.expanded) _joinButton(context, joined, compact: true),
      AnimatedRotation(
        turns: widget.expanded ? 0.5 : 0,
        duration: _animation,
        child: const Icon(Icons.expand_more),
      ),
    ]);
  }

  Widget _joinButton(BuildContext context, bool joined,
      {bool compact = false}) {
    var key = ValueKey(
        "directory_${joined ? "open" : "join"}_${widget.entry.roomId}");
    if (joiningNow) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child:
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator()),
      );
    }
    var label = Text(joined ? directoryOpen : directoryJoin);
    void onPressed() =>
        joined ? widget.joining.open(widget.entry) : _join(widget.joining);
    return compact
        ? TextButton(key: key, onPressed: onPressed, child: label)
        : FilledButton(key: key, onPressed: onPressed, child: label);
  }

  Widget _expanded(BuildContext context) {
    return FutureBuilder<DirectoryDetails>(
      future: widget.details,
      builder: (context, snapshot) {
        var details = snapshot.data;
        var loading = snapshot.connectionState != ConnectionState.done;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _banner(context, details),
              _topic(context, details, loading),
              const SizedBox(height: 8),
              _badges(context, details),
              if (widget.entry.isSpace) _children(context, details, loading),
              const SizedBox(height: 12),
              _actions(context),
            ],
          ),
        );
      },
    );
  }

  Widget _banner(BuildContext context, DirectoryDetails? details) {
    var image = widget.image(details?.bannerUrl, banner: true);
    return AnimatedSize(
      duration: _animation,
      child: image == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                // full width, 3:1, but never taller than 180
                child: LayoutBuilder(
                  builder: (context, constraints) => SizedBox(
                    width: double.infinity,
                    height: (constraints.maxWidth / 3).clamp(60.0, 180.0),
                    child: Image(
                      key: ValueKey("directory_banner_${widget.entry.roomId}"),
                      image: image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _topic(BuildContext context, DirectoryDetails? details, bool loading) {
    var theme = Theme.of(context);
    var topic = details?.topic ?? widget.entry.topic;
    if (topic == null || topic.trim().isEmpty) {
      return Text(loading ? directoryLoadingDetails : directoryNoTopic,
          style:
              theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic));
    }
    return SelectableText(topic, style: theme.textTheme.bodyMedium);
  }

  Widget _badges(BuildContext context, DirectoryDetails? details) {
    var entry = widget.entry;
    var aliases = details?.aliases ?? const <String>[];
    Widget chip(IconData icon, String label) => Chip(
          avatar: Icon(icon, size: 14),
          label: Text(label),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );

    return Wrap(spacing: 6, runSpacing: 6, children: [
      chip(Icons.people_outline, directoryMembers(entry.memberCount)),
      if (entry.isSpace) chip(Icons.workspaces_outline, directoryBadgeSpace),
      if (details?.encrypted == true)
        chip(Icons.lock_outline, directoryBadgeEncrypted),
      if (entry.joinRule == "knock" || entry.joinRule == "knock_restricted")
        chip(Icons.front_hand_outlined, directoryBadgeKnock),
      if (entry.guestCanJoin) chip(Icons.person_outline, directoryBadgeGuests),
      if (entry.worldReadable)
        chip(Icons.visibility_outlined, directoryBadgeReadable),
      for (var alias in aliases)
        if (alias != entry.canonicalAlias) chip(Icons.alternate_email, alias),
    ]);
  }

  Widget _children(
      BuildContext context, DirectoryDetails? details, bool loading) {
    var theme = Theme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: LinearProgressIndicator(),
      );
    }
    var children = details?.children ?? const <DirectoryChild>[];
    if (children.isEmpty) return const SizedBox();

    const shown = 8;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(directoryRoomCount(children.length),
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          for (var child in children.take(shown))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                tiamat.Avatar.small(
                  image: widget.image(child.avatarUrl),
                  placeholderText: child.name ?? child.roomId,
                  placeholderColor: MatrixPeer.hashColor(child.roomId),
                ),
                const SizedBox(width: 8),
                if (child.isSpace)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.workspaces_outline, size: 14),
                  ),
                Expanded(
                  child: Text(child.name ?? child.roomId,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text(directoryMembers(child.memberCount),
                    style: theme.textTheme.bodySmall),
              ]),
            ),
          if (children.length > shown)
            Text(directoryMoreRooms(children.length - shown),
                style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    var theme = Theme.of(context);
    var joined = widget.joining.isJoined(widget.entry.roomId);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        if (joinFailed)
          Text(directoryJoinFailed,
              key: ValueKey("directory_join_failed_${widget.entry.roomId}"),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        if (suggestion != null && !joiningNow)
          OutlinedButton(
            key: ValueKey("directory_join_as_${widget.entry.roomId}"),
            onPressed: () => _join(suggestion!),
            child: Text(directoryJoinAsAccount(suggestion!.userId)),
          ),
        _joinButton(context, joined),
      ],
    );
  }
}
