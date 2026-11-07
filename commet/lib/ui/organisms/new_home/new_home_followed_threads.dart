// Vommet: Followed threads in New Home (Vommet issue 1144).
import 'dart:async';

import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/matrix/components/threads/matrix_threads_component.dart';
import 'package:commet/client/matrix/components/threads/thread_follows.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/new_home/followed_threads_preview.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/room_threads_list/room_threads_list_widget.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/media_spoiler.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

String get followedThreadsTitle =>
    Intl.message("Followed threads", name: "followedThreadsTitle");
String get followedThreadsDescription =>
    Intl.message("Recent replies in threads you follow",
        name: "followedThreadsDescription");
String get followedThreadsCountLabel =>
    Intl.message("Threads to show", name: "followedThreadsCountLabel");
String get followedThreadsUnfollowError =>
    Intl.message("Couldn’t unfollow this thread.",
        name: "followedThreadsUnfollowError");
String get followedThreadsSelectAccount =>
    Intl.message("Select an account to see followed threads.",
        name: "followedThreadsSelectAccount");
String get followedThreadsAll =>
    Intl.message("All", name: "followedThreadsAll");
String get followedThreadsUnread =>
    Intl.message("Unread", name: "followedThreadsUnread");
String get followedThreadsRefresh =>
    Intl.message("Refresh followed threads", name: "followedThreadsRefresh");
String get followedThreadsNoUnread =>
    Intl.message("No unread replies in this preview.",
        name: "followedThreadsNoUnread");
String get followedThreadsEmpty =>
    Intl.message("No followed activity found in recent rooms.",
        name: "followedThreadsEmpty");
String get followedThreadsStale =>
    Intl.message("Refresh incomplete. Showing the previous preview.",
        name: "followedThreadsStale");
String get followedThreadsPartial =>
    Intl.message("Some recent activity couldn’t be checked. Try refreshing.",
        name: "followedThreadsPartial");
String get followedThreadsCoverage =>
    Intl.message("Recent rooms only. Older activity may be missing.",
        name: "followedThreadsCoverage");
String get followedThreadsMissingReply =>
    Intl.message("Reply preview unavailable.",
        name: "followedThreadsMissingReply");
String get followedThreadsActions =>
    Intl.message("Thread actions", name: "followedThreadsActions");
String get followedThreadsUnfollow =>
    Intl.message("Unfollow thread", name: "followedThreadsUnfollow");

String get followedThreadsLoading =>
    Intl.message("Checking recent rooms…", name: "followedThreadsLoading");
String get followedThreadsError =>
    Intl.message("Couldn’t check recent rooms. Try refreshing.",
        name: "followedThreadsError");

String get followedThreadsSpoiler =>
    Intl.message("Spoiler", name: "followedThreadsSpoiler");

String get followedThreadsEncrypted =>
    Intl.message("Encrypted preview unavailable.",
        name: "followedThreadsEncrypted");

String _previewText(TimelineEvent event) {
  if (event is MatrixTimelineEvent) {
    final content = event.event.content;
    final html = content['formatted_body'];
    if (MediaSpoiler.isSpoiler(content) ||
        (html is String && html.toLowerCase().contains('data-mx-spoiler'))) {
      return followedThreadsSpoiler;
    }
    if (event.event.type == matrix.EventTypes.Encrypted) {
      return followedThreadsEncrypted;
    }
  }
  return ThreadListTile.bodyOf(event);
}

int followedThreadsCount(HomeCard card) =>
    HomeLayout.followedThreadCounts.contains(card.count)
        ? card.count
        : HomeLayout.defaultCount;

Future<int?> editFollowedThreadsCount(BuildContext context, HomeCard card) =>
    showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(followedThreadsCountLabel),
        children: [
          for (final count in HomeLayout.followedThreadCounts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, count),
              child: Row(
                children: [
                  Icon(count == followedThreadsCount(card)
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  const SizedBox(width: 12),
                  Text(NumberFormat.decimalPattern().format(count)),
                ],
              ),
            ),
        ],
      ),
    );

typedef _Row = ({MatrixRoom room, ThreadSummary thread});

class NewHomeFollowedThreads extends StatefulWidget {
  const NewHomeFollowedThreads({
    required this.account,
    required this.card,
    required this.active,
    super.key,
  });

  final MatrixClient? account;
  final HomeCard card;
  final bool active;

  @override
  State<NewHomeFollowedThreads> createState() => _NewHomeFollowedThreadsState();
}

class _NewHomeFollowedThreadsState extends State<NewHomeFollowedThreads> {
  final _subscriptions = <StreamSubscription>[];
  final _unread = <(String, String), bool>{};
  final _followed = <(String, String), bool>{};
  final _removed = <String>{};
  final _loadingRooms = <String>{};
  final _followData = <String, matrix.BasicEvent?>{};
  final _unfollowing = <(String, String)>{};
  List<_Row> _rows = [];
  Completer<void>? _load;
  bool _unreadOnly = false;
  bool _partial = false;
  bool _stale = false;
  bool _failed = false;

  MatrixThreadsComponent? get _component {
    final component = widget.account?.getComponent<ThreadsComponent>();
    return component is MatrixThreadsComponent ? component : null;
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(NewHomeFollowedThreads oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.account, oldWidget.account) ||
        widget.active != oldWidget.active) {
      _unbind();
      _clearPreview();
      _bind();
    }
  }

  void _clearPreview() {
    _load?.complete();
    _load = null;
    _rows = [];
    _unread.clear();
    _followed.clear();
    _removed.clear();
    _loadingRooms.clear();
    _followData.clear();
    _unfollowing.clear();
    _unreadOnly = false;
    _partial = false;
    _stale = false;
    _failed = false;
  }

  void _bind() {
    final account = widget.account;
    if (account == null || !widget.active || _component == null) return;
    final mx = account.matrixClient;
    _subscriptions.addAll([
      mx.onLoginStateChanged.stream.listen((state) {
        if (state == matrix.LoginState.loggedIn) {
          unawaited(_refresh());
        } else {
          setState(_clearPreview);
        }
      }),
      mx.onSync.stream.listen((sync) {
        final joined = sync.rooms?.join;
        final left = sync.rooms?.leave;
        for (final roomId in _rows.map((row) => row.room.identifier).toSet()) {
          if (left?.containsKey(roomId) == true) {
            _invalidateRoom(roomId);
            continue;
          }
          final update = joined?[roomId];
          if (update?.ephemeral?.any((event) => event.type == 'm.receipt') ==
                  true ||
              update?.accountData
                      ?.any((event) => event.type == ThreadFollows.type) ==
                  true) {
            _updateFlags(roomId: roomId);
          }
        }
      }),
      mx.onTimelineEvent.stream.listen((event) {
        if (event.type != matrix.EventTypes.Redaction) return;
        final roomId = event.roomId;
        if (roomId == null) return;
        final target = event.redacts ?? event.content['redacts'];
        if (_rows.any((row) =>
            row.room.identifier == roomId &&
            (target == null ||
                row.thread.rootId == target ||
                row.thread.latestReply?.eventId == target))) {
          _invalidateRoom(roomId);
        } else if (_loadingRooms.contains(roomId)) {
          _removed.add(roomId);
        }
      }),
    ]);
    _component!.threadFollowsChanged.addListener(_followsChanged);
    _boundComponent = _component;
    unawaited(_refresh());
  }

  MatrixThreadsComponent? _boundComponent;

  void _unbind() {
    _load?.complete();
    _load = null;
    _boundComponent?.threadFollowsChanged.removeListener(_followsChanged);
    _boundComponent = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  (String, String) _key(_Row row) => (row.room.identifier, row.thread.rootId);

  bool _joined(MatrixRoom room) =>
      room.matrixRoom.membership == matrix.Membership.join;

  void _invalidateRoom(String roomId) {
    if (_loadingRooms.contains(roomId)) _removed.add(roomId);
    if (!_rows.any((row) => row.room.identifier == roomId)) return;
    setState(() {
      _rows.removeWhere((row) => row.room.identifier == roomId);
      _partial = true;
    });
  }

  void _followsChanged() {
    for (final room in _rows.map((row) => row.room).toSet()) {
      final data = room.matrixRoom.roomAccountData[ThreadFollows.type];
      if (!identical(data, _followData[room.identifier])) {
        _followData[room.identifier] = data;
        _updateFlags(roomId: room.identifier);
      }
    }
  }

  void _updateFlags({String? roomId, bool notify = true}) {
    final component = _component;
    if (component == null) return;
    var changed = false;
    for (final row in _rows) {
      if (roomId != null && row.room.identifier != roomId) continue;
      final key = _key(row);
      _followData[row.room.identifier] =
          row.room.matrixRoom.roomAccountData[ThreadFollows.type];
      final unread = component.isThreadUnread(row.room, row.thread);
      final followed = _joined(row.room) &&
          component.isThreadFollowed(row.room, row.thread.rootId,
              root: row.thread.root, participated: row.thread.participated);
      changed |= _unread[key] != unread || _followed[key] != followed;
      _unread[key] = unread;
      _followed[key] = followed;
    }
    if (notify && changed) setState(() {});
  }

  Future<void> _refresh() async {
    final account = widget.account;
    final component = _component;
    if (account == null ||
        !account.isLoggedIn() ||
        component == null ||
        _load != null) return;
    final load = Completer<void>();
    setState(() {
      _load = load;
      _removed.clear();
    });
    final rooms = account.rooms.whereType<MatrixRoom>().where(_joined).toList()
      ..sort((a, b) {
        final order = b.lastEventTimestamp.compareTo(a.lastEventTimestamp);
        return order != 0 ? order : a.identifier.compareTo(b.identifier);
      });
    final recent = rooms.take(FollowedThreadPreview.roomLimit).toList();
    _loadingRooms.addAll(recent.map((room) => room.identifier));
    final result = await FollowedThreadPreview.load<MatrixRoom, _Row>(
      rooms: recent,
      canceled: load.future,
      page: (room) async => [
        for (final thread in await component.previewParticipated(room))
          (room: room, thread: thread),
      ],
      extra: (rows) {
        final known = rows.map(_key).toSet();
        final candidates = [
          for (final room in recent)
            for (final root in component.previewExtraRoots(room))
              if (!known.contains((room.identifier, root.rootId)))
                (room: room, id: root.rootId, timestamp: root.timestamp),
        ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return candidates.map((candidate) => () async {
              final thread =
                  await component.previewRoot(candidate.room, candidate.id);
              return thread == null
                  ? null
                  : (room: candidate.room, thread: thread);
            });
      },
    );
    if (!mounted || !identical(load, _load)) return;
    final unique = <(String, String), _Row>{
      for (final row in result.rows)
        if (_joined(row.room) && !_removed.contains(row.room.identifier))
          _key(row): row,
    };
    setState(() {
      _load = null;
      _loadingRooms.clear();
      _partial = result.failures > 0 || _removed.isNotEmpty;
      _failed = result.failures > 0 && result.completed == 0;
      _stale = _partial && unique.isEmpty && _rows.isNotEmpty;
      if (!_stale) {
        _rows = unique.values.toList()
          ..sort((a, b) {
            final order =
                b.thread.lastActivity.compareTo(a.thread.lastActivity);
            return order != 0
                ? order
                : a.thread.rootId.compareTo(b.thread.rootId);
          });
        _unread.clear();
        _followed.clear();
        _followData.clear();
      }
      _updateFlags(notify: false);
    });
  }

  Future<void> _unfollow(_Row row) async {
    final component = _component;
    final account = widget.account;
    if (component == null ||
        account?.isLoggedIn() != true ||
        !identical(row.room.client, account) ||
        !_joined(row.room)) {
      return;
    }
    final key = _key(row);
    if (!_unfollowing.add(key)) return;
    try {
      await component.setThreadFollowed(row.room, row.thread.rootId, false);
    } catch (_) {
      if (mounted && identical(widget.account, account)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(followedThreadsUnfollowError)),
        );
      }
    } finally {
      if (mounted && identical(widget.account, account)) {
        _unfollowing.remove(key);
        _updateFlags(roomId: row.room.identifier);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return Text(followedThreadsDescription);
    if (_component == null || widget.account?.isLoggedIn() != true) {
      return Text(followedThreadsSelectAccount);
    }
    final visible = _rows.where((row) {
      final key = _key(row);
      return _followed[key] == true && (!_unreadOnly || _unread[key] == true);
    }).take(followedThreadsCount(widget.card));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runAlignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: Text(followedThreadsAll),
              selected: !_unreadOnly,
              onSelected: (_) => setState(() => _unreadOnly = false),
            ),
            ChoiceChip(
              label: Text(followedThreadsUnread),
              selected: _unreadOnly,
              onSelected: (_) => setState(() => _unreadOnly = true),
            ),
            IconButton(
              tooltip: followedThreadsRefresh,
              icon: const Icon(Icons.refresh),
              onPressed: _load == null ? _refresh : null,
            ),
          ],
        ),
        if (_load != null) ...[
          const LinearProgressIndicator(),
          if (_rows.isEmpty) Text(followedThreadsLoading),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            followedThreadsCoverage,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        for (final row in visible)
          _ThreadRow(
            key: ValueKey(_key(row)),
            row: row,
            unread: _unread[_key(row)] == true,
            onUnfollow: () => _unfollow(row),
          ),
        if (visible.isEmpty && _load == null && !_partial)
          Text(_unreadOnly ? followedThreadsNoUnread : followedThreadsEmpty),
        if (_partial)
          Text(_stale
              ? followedThreadsStale
              : _failed
                  ? followedThreadsError
                  : followedThreadsPartial),
      ],
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.row,
    required this.unread,
    required this.onUnfollow,
    super.key,
  });

  final _Row row;
  final bool unread;
  final VoidCallback onUnfollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = row.thread.latestReply;
    final redaction = RedactionScope.of(context);
    // The room's normal member fallback can start a network lookup.
    final senderName = latest == null
        ? null
        : row.room.matrixRoom
            .getState(matrix.EventTypes.RoomMember, latest.senderId)
            ?.content['displayname'];
    return Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                if (!row.room.client.isLoggedIn() ||
                    row.room.matrixRoom.membership != matrix.Membership.join) {
                  return;
                }
                EventBus.doOpenRoom(row.room.identifier,
                    clientId: row.room.client.identifier,
                    threadId: row.thread.rootId);
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        redaction.name(
                            row.room.displayName, row.room.identifier),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall),
                    RedactedText(_previewText(row.thread.root),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (latest != null)
                      RedactedText(
                        threadsListLatestReply(
                            redaction.name(
                                senderName is String && senderName.isNotEmpty
                                    ? senderName
                                    : latest.senderId,
                                latest.senderId),
                            _previewText(latest)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(followedThreadsMissingReply),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (latest != null)
                          Text(
                              TextUtils.timestampToLocalizedTime(
                                  latest.originServerTs, context),
                              style: theme.textTheme.labelSmall),
                        if (latest != null || row.thread.replyCount > 0)
                          Text(threadsListReplyCount(row.thread.replyCount),
                              style: theme.textTheme.labelSmall),
                        if (unread)
                          Text(followedThreadsUnread,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.primary)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<bool>(
            tooltip: followedThreadsActions,
            onSelected: (_) => onUnfollow(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: true,
                child: Text(followedThreadsUnfollow),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
