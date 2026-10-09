import 'dart:async';

import 'package:commet/client/components/room_directory/room_directory_component.dart';
import 'package:commet/ui/pages/room_directory/directory_account_handle.dart';
import 'package:commet/ui/pages/room_directory/directory_row.dart';
import 'package:commet/ui/pages/room_directory/directory_server_chooser.dart';
import 'package:commet/ui/pages/room_directory/directory_strings.dart';
import 'package:commet/utils/room_directory/directory_accounts.dart';
import 'package:commet/utils/room_directory/directory_pager.dart';
import 'package:commet/utils/room_directory/directory_servers.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Public room directory ("Explore rooms"): search one server's directory,
/// filter by rooms / spaces, expand a row for details, join.
class RoomDirectoryPage extends StatefulWidget {
  const RoomDirectoryPage({
    required this.accounts,
    required this.store,
    this.initialAccountId,
    this.searchDebounce = const Duration(milliseconds: 400),
    this.pageSize = 30,
    super.key,
  });

  final List<DirectoryAccountHandle> accounts;
  final DirectoryServerStore store;
  final String? initialAccountId;
  final Duration searchDebounce;
  final int pageSize;

  @override
  State<RoomDirectoryPage> createState() => RoomDirectoryPageState();
}

class RoomDirectoryPageState extends State<RoomDirectoryPage> {
  late DirectoryAccountHandle joining;
  late String server;
  DirectoryTypeFilter type = DirectoryTypeFilter.all;
  String search = "";

  final DirectoryPager pager = DirectoryPager();
  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  Timer? _debounce;

  /// Account that fetched the current results (details go through it too)
  late DirectoryAccountHandle fetching;
  String? expandedRoomId;
  final Map<String, Future<DirectoryDetails>> _details = {};

  List<DirectoryAccount> get _all =>
      widget.accounts.map((a) => a.account).toList();

  @override
  void initState() {
    joining = widget.accounts.firstWhere(
        (a) => a.account.id == widget.initialAccountId,
        orElse: () => widget.accounts.first);
    server = joining.account.homeserver;
    scrollController.addListener(_onScroll);
    _restart();
    super.initState();
    Future.microtask(_loadMore);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  DirectoryAccountHandle _handle(DirectoryAccount account) =>
      widget.accounts.firstWhere((a) => a.account == account);

  void _restart() {
    var plan = DirectoryAccounts.plan(server, joining.account, _all);
    var handle = _handle(plan.account);
    var query = search, filter = type, size = widget.pageSize;

    fetching = handle;
    expandedRoomId = null;
    _details.clear();
    pager.reset((since) => handle.directory.query(
          server: plan.serverParam,
          search: query,
          type: filter,
          since: since,
          limit: size,
        ));
  }

  void _requery() {
    _restart();
    _loadMore();
  }

  Future<void> _loadMore() async {
    var future = pager.loadMore();
    if (mounted) setState(() {});
    await future;
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    var position = scrollController.position;
    if (position.pixels > position.maxScrollExtent - 400 &&
        pager.hasMore &&
        !pager.loading &&
        pager.error == null) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.searchDebounce, () {
      if (value.trim() == search) return;
      setState(() => search = value.trim());
      _requery();
    });
  }

  void selectServer(String value) {
    setState(() => server = value);
    _requery();
  }

  void selectType(DirectoryTypeFilter value) {
    if (value == type) return;
    setState(() => type = value);
    _requery();
  }

  void selectJoining(DirectoryAccountHandle account) {
    setState(() {
      var wasOwnServer = server == joining.account.homeserver;
      joining = account;
      // stay on "my server" when switching accounts
      if (wasOwnServer) server = account.account.homeserver;
    });
    _requery();
  }

  Future<void> _chooseServer() async {
    var result = await DirectoryServerChooser.show(
      context,
      accounts: widget.accounts,
      current: joining,
      store: widget.store,
    );
    if (result == null || !mounted) return;
    if (result.save) {
      await widget.store
          .setSaved(DirectoryServers.touch(widget.store.saved, result.server));
    } else if (widget.store.saved.contains(result.server)) {
      // keep most recently used first
      await widget.store
          .setSaved(DirectoryServers.touch(widget.store.saved, result.server));
    }
    selectServer(result.server);
  }

  Future<void> _toggleSaved() async {
    var saved = widget.store.saved;
    await widget.store.setSaved(saved.contains(server)
        ? DirectoryServers.remove(saved, server)
        : DirectoryServers.touch(saved, server));
    if (mounted) setState(() {});
  }

  Future<DirectoryDetails> detailsFor(DirectoryEntry entry) =>
      _details.putIfAbsent(
          entry.roomId, () => fetching.directory.details(entry, via: server));

  @override
  Widget build(BuildContext context) {
    var scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(directoryTitle),
        backgroundColor: scheme.surfaceContainerLow,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _controls(context),
                const Divider(height: 1),
                Expanded(child: _results(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    var ownServer =
        DirectoryAccounts.ownServers(joining.account, _all).contains(server);
    var saved = widget.store.saved.contains(server);
    var via = fetching != joining ? fetching.userId : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                key: const ValueKey("directory_server_button"),
                avatar: const Icon(Icons.dns_outlined, size: 18),
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(server),
                  if (via != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(directoryServerVia(via),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ]),
                onPressed: _chooseServer,
              ),
              if (!ownServer)
                IconButton(
                  key: const ValueKey("directory_save_server"),
                  tooltip: saved ? directoryServerUnsave : directoryServerSave,
                  icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: _toggleSaved,
                ),
              if (widget.accounts.length > 1) _accountPicker(context),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey("directory_search"),
            controller: searchController,
            onChanged: _onSearchChanged,
            onSubmitted: (value) {
              _debounce?.cancel();
              setState(() => search = value.trim());
              _requery();
            },
            decoration: InputDecoration(
              hintText: directorySearchPlaceholder,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<DirectoryTypeFilter>(
            key: const ValueKey("directory_type_filter"),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: DirectoryTypeFilter.all,
                  label: Text(directoryFilterAll)),
              ButtonSegment(
                  value: DirectoryTypeFilter.rooms,
                  label: Text(directoryFilterRooms),
                  icon: const Icon(Icons.tag, size: 16)),
              ButtonSegment(
                  value: DirectoryTypeFilter.spaces,
                  label: Text(directoryFilterSpaces),
                  icon: const Icon(Icons.workspaces_outline, size: 16)),
            ],
            selected: {type},
            onSelectionChanged: (s) => selectType(s.first),
          ),
        ],
      ),
    );
  }

  Widget _accountPicker(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(directoryJoinAs, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(width: 6),
      DropdownButton<DirectoryAccountHandle>(
        key: const ValueKey("directory_account_picker"),
        value: joining,
        underline: const SizedBox(),
        isDense: true,
        items: widget.accounts
            .map((a) => DropdownMenuItem(
                  value: a,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    tiamat.Avatar.small(
                        image: a.avatar, placeholderText: a.displayName),
                    const SizedBox(width: 6),
                    Text(a.userId),
                  ]),
                ))
            .toList(),
        onChanged: (a) {
          if (a != null) selectJoining(a);
        },
      ),
    ]);
  }

  Widget _results(BuildContext context) {
    var entries = pager.entries;

    if (entries.isEmpty) {
      if (pager.error != null) return _problem(context, pager.error!);
      if (pager.isEmpty) {
        final empty = switch (type) {
          DirectoryTypeFilter.all => directoryEmpty,
          DirectoryTypeFilter.rooms => directoryEmptyRooms,
          DirectoryTypeFilter.spaces => directoryEmptySpaces,
        };
        return _message(context, Icons.travel_explore,
            search.isEmpty ? empty : directoryNoMatches(search), null);
      }
      return const Center(child: CircularProgressIndicator());
    }

    var footer = pager.error != null || pager.hasMore;
    return ListView.builder(
      key: const ValueKey("directory_results"),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length + (footer ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == entries.length) return _footer(context);
        var entry = entries[i];
        var expanded = entry.roomId == expandedRoomId;
        return DirectoryRow(
          key: ValueKey("directory_row_${entry.roomId}"),
          entry: entry,
          server: server,
          expanded: expanded,
          joining: joining,
          accounts: widget.accounts,
          image: fetching.directory.image,
          details: expanded ? detailsFor(entry) : null,
          onToggle: () => setState(() {
            expandedRoomId = expanded ? null : entry.roomId;
          }),
        );
      },
    );
  }

  Widget _footer(BuildContext context) {
    if (pager.error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: TextButton.icon(
            onPressed: _loadMore,
            icon: const Icon(Icons.refresh),
            label: Text(directoryRetry),
          ),
        ),
      );
    }
    // the list may be too short to scroll: keep loading until it fills
    if (!pager.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || pager.loading || !pager.hasMore) return;
        if (!scrollController.hasClients ||
            scrollController.position.maxScrollExtent < 400) {
          _loadMore();
        }
      });
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _problem(BuildContext context, Object error) {
    var kind =
        error is DirectoryException ? error.kind : DirectoryProblemKind.failed;
    var (icon, title, hint) = switch (kind) {
      DirectoryProblemKind.remoteNotShared => (
          Icons.visibility_off_outlined,
          directoryRemoteNotShared(server),
          directoryRemoteNotSharedHint(server)
        ),
      DirectoryProblemKind.ownServerRestricted => (
          Icons.lock_outline,
          directoryOwnServerRestricted(server),
          directoryOwnServerRestrictedHint
        ),
      DirectoryProblemKind.unreachable => (
          Icons.cloud_off_outlined,
          directoryUnreachable(server),
          directoryUnreachableHint
        ),
      DirectoryProblemKind.failed => (
          Icons.error_outline,
          directoryFailed,
          null
        ),
    };
    return _message(context, icon, title, hint,
        key: ValueKey("directory_problem_${kind.name}"), retry: true);
  }

  Widget _message(
      BuildContext context, IconData icon, String title, String? hint,
      {Key? key, bool retry = false}) {
    var theme = Theme.of(context);
    return Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: theme.colorScheme.secondary),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint,
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
          if (retry) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loadMore,
              icon: const Icon(Icons.refresh),
              label: Text(directoryRetry),
            ),
          ],
        ]),
      ),
    );
  }
}
