import 'dart:async';
import 'dart:math' as math;
import 'package:commet/main.dart' show backgroundTaskManager;
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/organisms/invitation_view/batch_invite_source.dart';
import 'package:commet/ui/organisms/invitation_view/invitation_batch_view.dart';
import 'package:commet/utils/invitations/invitation_batch.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:commet/utils/space_hierarchy/invite_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart' as t;

class BatchInviteWidget extends StatefulWidget {
  const BatchInviteWidget({required this.source, this.initialQuery, super.key});
  final BatchInviteSource source;
  final String? initialQuery;
  @override
  State<BatchInviteWidget> createState() => _BatchInviteWidgetState();
}

class _BatchInviteWidgetState extends State<BatchInviteWidget> {
  static const maxInvitations = 100;
  BatchInviteSource get source => widget.source;
  late final TextEditingController query = TextEditingController(
    text: widget.initialQuery,
  );
  final selected = <String>{};
  final rooms = <String>{};
  List<InvitePlace>? places;
  List<InvitePerson> results = [];
  Timer? debounce;
  int generation = 0;
  int step = 0;
  bool searching = false,
      busy = false,
      shareHistory = true,
      shareExisting = false;
  String? searchError, loadError, reviewError;
  @override
  void initState() {
    super.initState();
    if (query.text.isNotEmpty) {
      searching = true;
      debounce = Timer(
        const Duration(milliseconds: 500),
        () => search(query.text),
      );
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  String personName(String id) =>
      RedactionScope.of(context).name(source.person(id).name, id);
  String placeName(InvitePlace p) =>
      RedactionScope.of(context).name(p.name, p.id);
  List<InvitePlace> get chosen => [
        for (final p in places ?? <InvitePlace>[])
          if (p.id == source.rootId || rooms.contains(p.id)) p,
      ];
  int get invitationCount => [
        for (final p in chosen)
          for (final id in selected)
            if (source.access(id, p.id).invitable) (id, p.id),
      ].length;
  List<(String, InvitePlace)> get grants => [
        for (final p in chosen)
          for (final id in selected)
            if (source.access(id, p.id).canGrant) (id, p),
      ];
  bool selectable(InvitePlace p) => selected.any(
        (id) =>
            source.access(id, p.id).invitable ||
            source.access(id, p.id).canGrant,
      );
  void changedQuery(String value) {
    generation++;
    debounce?.cancel();
    setState(() {
      searching = value.isNotEmpty;
      results = [];
      searchError = null;
    });
    if (value.isNotEmpty)
      debounce = Timer(const Duration(milliseconds: 500), () => search(value));
  }

  Future<void> search(String value) async {
    final token = ++generation;
    setState(() {
      searching = true;
      searchError = null;
    });
    try {
      final found = await source.search(value);
      if (!mounted || token != generation || query.text != value) return;
      final unique = {
        for (final p in found)
          if (p.id != source.selfId && source.validId(p.id)) p.id: p,
      };
      if (source.validId(value) && value != source.selfId)
        unique.putIfAbsent(value, () => source.person(value));
      setState(() => results = unique.values.toList());
    } catch (_) {
      if (mounted && token == generation)
        setState(
          () => searchError =
              'Could not search. Check your connection and try again.',
        );
    } finally {
      if (mounted && token == generation) setState(() => searching = false);
    }
  }

  Future<void> loadRooms() async {
    setState(() {
      busy = true;
      loadError = null;
    });
    try {
      final loaded = await source.loadPlaces();
      if (!mounted) return;
      setState(() {
        places = loaded;
        rooms.addAll(
          loaded
              .where((p) => p.id != source.rootId && selectable(p))
              .map((p) => p.id),
        );
        step = source.isSpace ? 1 : 2;
      });
      if (!source.isSpace) await review();
    } catch (_) {
      if (mounted)
        setState(
          () => loadError =
              'Could not load rooms. Your selected people are still here. Retry, or explicitly choose Space only.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review() async {
    if (invitationCount + (shareExisting ? grants.length : 0) > maxInvitations)
      return;
    setState(() {
      busy = true;
      reviewError = null;
    });
    try {
      await source.refresh(
        selected.toList(),
        chosen.map((p) => p.id).toList(),
        canceled: () => !mounted,
      );
      if (mounted) setState(() => step = 2);
    } catch (_) {
      if (mounted)
        setState(
          () => reviewError =
              'Could not check current membership. Nothing has been sent. Try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void toggle(String id) {
    setState(() {
      if (!selected.remove(id)) selected.add(id);
    });
  }

  Widget profile(String id) => UserPanelView(
        displayName: source.person(id).name,
        userId: id,
        detail: id,
        avatar: source.person(id).avatar,
        avatarColor: source.person(id).color,
        avatarSize: 20,
      );
  Widget message(String text, {bool error = false}) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (error
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary)
              .withAlpha(24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text),
      );
  Widget button(String label, VoidCallback? action, {bool secondary = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: action == null
              ? ElevatedButton(
                  onPressed: null,
                  child: Padding(
                      padding: const EdgeInsets.all(8), child: Text(label)))
              : secondary
                  ? t.Button.secondary(text: label, onTap: action)
                  : t.Button(text: label, onTap: action),
        ),
      );
  Widget pickPerson(InvitePerson person) {
    final disabled = person.id == source.selfId ||
        (!source.isSpace && !source.access(person.id, source.rootId).invitable);
    return CheckboxListTile(
      key: ValueKey('invite-person-${person.id}'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
      value: selected.contains(person.id),
      onChanged: disabled ? null : (_) => toggle(person.id),
      title: profile(person.id),
      subtitle:
          disabled ? Text(source.access(person.id, source.rootId).label) : null,
    );
  }

  Widget people() {
    final recs = {
      for (final p in source.recommendations)
        if (p.id != source.selfId && source.validId(p.id)) p.id: p,
    }.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        t.TextInput(
          controller: query,
          placeholder: 'Search name or Matrix ID',
          icon: const Icon(Icons.search),
          maxLines: 1,
          onChanged: changedQuery,
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              '${selected.length} selected',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in selected)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: InputChip(
                    label: Text(personName(id)),
                    onDeleted: () => toggle(id),
                    deleteButtonTooltipMessage: 'Remove ${personName(id)}',
                  ),
                ),
            ],
          ),
        ],
        if (searching)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (searchError != null) ...[
          message(searchError!, error: true),
          button('Retry search', () => search(query.text), secondary: true),
          if (source.validId(query.text) && query.text != source.selfId) ...[
            const Text(
                'You can still select this exact Matrix ID. Check it before inviting.'),
            pickPerson(source.person(query.text)),
          ],
        ],
        if (query.text.isNotEmpty && !searching && searchError == null) ...[
          if (results.isEmpty)
            message(
              'No matching people. Enter a full Matrix ID to add someone directly.',
            ),
          for (final p in results) pickPerson(p),
        ],
        if (query.text.isEmpty && source.recommendations.isNotEmpty) ...[
          const Divider(),
          const t.Text.labelLow('Recommended'),
          for (final p in recs) pickPerson(p),
        ],
        if (loadError != null) ...[
          message(loadError!, error: true),
          button('Retry loading rooms', loadRooms),
          if (source.isSpace)
            button('Space only', () {
              setState(() {
                places = [
                  InvitePlace(source.rootId, source.rootName, isSpace: true),
                ];
                rooms.clear();
              });
              review();
            }, secondary: true),
        ],
      ],
    );
  }

  Widget roomRow(InvitePlace place) {
    final descendants = [
      place,
      ...places!.where((p) => p.ancestors.contains(place.id)),
    ].where(selectable).map((p) => p.id).toSet();
    final all = descendants.isNotEmpty && rooms.containsAll(descendants);
    final some = descendants.any(rooms.contains);
    final histories = {
      for (final id in selected)
        if (source.access(id, place.id).invitable)
          InviteAccess.historyLabel(source.access(id, place.id).history),
    };
    final count =
        selected.where((id) => source.access(id, place.id).invitable).length;
    return Padding(
      padding: EdgeInsets.only(
        left: math.min(place.ancestors.length - 1, 2).clamp(0, 2).toDouble() *
            12.0,
      ),
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        tristate: place.isSpace,
        value: all
            ? true
            : some && place.isSpace
                ? null
                : false,
        onChanged: descendants.isEmpty
            ? null
            : (_) => setState(() {
                  if (all) {
                    rooms.removeAll(descendants);
                  } else {
                    rooms.addAll(descendants);
                  }
                }),
        title: Text(placeName(place)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (place.path.isNotEmpty)
              Text(
                RedactionScope.of(context).redactsNames
                    ? 'Subspace'
                    : place.path,
              ),
            Text(
              histories.isEmpty
                  ? selected
                      .map((id) => source.access(id, place.id).label)
                      .toSet()
                      .join(' · ')
                  : histories.join(' · '),
            ),
            Text(
                '$count ${count == 1 ? 'invitation' : 'invitations'} · ${selected.length - count} skipped'),
          ],
        ),
      ),
    );
  }

  Widget roomPicker() {
    final children = places!.where((p) => p.id != source.rootId).toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              message(
                'Choose rooms once for everyone. Existing memberships and pending invitations are skipped per person.',
              ),
              Text(
                RedactionScope.of(context).name(source.rootName, source.rootId),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${selected.where((id) => source.access(id, source.rootId).invitable).length} new space ${selected.where((id) => source.access(id, source.rootId).invitable).length == 1 ? 'invitation' : 'invitations'}',
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => setState(() => rooms.clear()),
                    child: const Text('Space only'),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => rooms.addAll(
                        children.where(selectable).map((p) => p.id),
                      ),
                    ),
                    child: const Text('All available'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => roomRow(children[index]),
            childCount: children.length,
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (source.truncated)
                message(
                  'Only the first 5,000 destinations are shown. Other rooms are not included.',
                  error: true,
                ),
              const Text(
                'Space membership does not automatically join people to its rooms.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget reviewBody() {
    final policy = RedactionScope.of(context);
    final newContacts = selected.where(source.firstContact).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${selected.length} ${selected.length == 1 ? 'person' : 'people'} · $invitationCount ${invitationCount == 1 ? 'invitation' : 'invitations'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final id in selected)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: profile(id),
          ),
        const SizedBox(height: 12),
        const Text(
          'What they will receive',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final p in chosen)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(placeName(p)),
                for (final history in {
                  for (final id in selected)
                    if (source.access(id, p.id).invitable)
                      source.access(id, p.id).history,
                })
                  Text(InviteAccess.historyLabel(history)),
              ],
            ),
          ),
        if (chosen.any(
          (p) => selected.any(
            (id) =>
                source.access(id, p.id).invitable &&
                source.access(id, p.id).history == InviteHistory.included,
          ),
        )) ...[
          if (!source.isSpace)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: shareHistory,
              onChanged: (v) => setState(() => shareHistory = v ?? true),
              title: const Text('Share earlier messages'),
              subtitle: const Text(
                'Applies to everyone selected. Turn off to share only new messages.',
              ),
            )
          else
            message(
              'Rooms marked History included share earlier messages permitted by their history-sharing policy. New messages only rooms do not share earlier messages. Unencrypted rooms follow their server history setting.',
            ),
        ],
        if (chosen.any((place) => selected.any((id) =>
            source.access(id, place.id).invitable &&
            source.access(id, place.id).history == InviteHistory.notEncrypted)))
          message(
              'In unencrypted rooms, the server shows earlier messages as each room’s history setting allows.'),
        if (newContacts.isNotEmpty)
          message(
            'First contact: ${newContacts.map(personName).join(', ')}. Check the ${policy.redactsNames ? 'selected identities' : 'Matrix IDs'} before inviting.',
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Details by person'),
          subtitle: const Text('Destinations and skipped invitations'),
          children: [
            for (final id in selected)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  profile(id),
                  for (final p in chosen)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(placeName(p)),
                      subtitle: Text(source.access(id, p.id).label),
                    ),
                  const Divider(),
                ],
              ),
          ],
        ),
        if (source.isSpace && grants.isNotEmpty)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: shareExisting,
            onChanged: (v) => setState(() => shareExisting = v ?? false),
            title: const Text(
              'Also share earlier messages with existing members',
            ),
            subtitle: Text(
              'Optional: ${grants.map((g) => '${placeName(g.$2)} with ${personName(g.$1)}').join('; ')}. No new invitations for these memberships. Only shareable messages are included. Stopping later cannot take back history already shared.',
            ),
          ),
        if (shareExisting)
          Text(
            '${grants.length} separate history ${grants.length == 1 ? 'share' : 'shares'}. Delivery may finish later; check Encrypted history settings if needed.',
          ),
        if (source.truncated)
          message(
            'Other rooms beyond the loaded 5,000 destinations are not included.',
            error: true,
          ),
      ],
    );
  }

  void send() {
    if (busy || selected.isEmpty) return;
    setState(() => busy = true);
    final entries = <BatchInviteItem>[];
    final chosenIds = chosen.map((p) => p.id).toSet();
    for (final id in selected) {
      for (final p in chosen) {
        final a = source.access(id, p.id);
        final parent = p.ancestors.where(chosenIds.contains).lastOrNull;
        final entry = BatchInviteItem(
          userId: id,
          roomId: p.id,
          roomName: p.name,
          parentRoomId: parent,
          shareHistory: source.isSpace || shareHistory,
        );
        if (a.existing) {
          entry.outcome = InviteOutcome.skipped;
          entry.reason = a.label;
        } else if (!a.invitable) {
          entry.outcome = InviteOutcome.blocked;
          entry.reason = a.label;
        }
        entries.add(entry);
      }
    }
    if (shareExisting) {
      for (final g in grants)
        entries.add(
          BatchInviteItem(
            userId: g.$1,
            roomId: g.$2.id,
            roomName: g.$2.name,
            operation: InviteOperation.history,
          ),
        );
    }
    final task = source.task(entries);
    final navigator = Navigator.of(context, rootNavigator: true);
    final people = {for (final id in selected) id: source.person(id)};
    task.action = () => showInvitationBatch(navigator, task, people);
    backgroundTaskManager.addTask(task);
    unawaited(task.start());
    Navigator.of(context).pop();
    unawaited(showInvitationBatch(navigator, task, people));
  }

  void nextPeople() {
    if (places == null) {
      unawaited(loadRooms());
    } else if (source.isSpace) {
      setState(() => step = 1);
    } else {
      unawaited(review());
    }
  }

  void back() {
    if (step == 2 && source.isSpace)
      setState(() => step = 1);
    else
      setState(() => step = 0);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).scale();
    final available = media.size.height - media.viewInsets.bottom - 220;
    final over =
        invitationCount + (shareExisting ? grants.length : 0) > maxInvitations;
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            !busy) {
          if (step == 0 && query.text.isNotEmpty) {
            query.clear();
            changedQuery('');
          } else if (step > 0) {
            back();
          } else {
            Navigator.of(context).pop();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: 560,
        height: math.max(180.0, math.min(700.0, available)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              step == 0
                  ? 'Choose people'
                  : step == 1
                      ? 'Choose rooms'
                      : 'Review invitations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${RedactionScope.of(context).name(source.rootName, source.rootId)} · ${step == 0 ? 1 : step == 1 ? 2 : source.isSpace ? 3 : 2} of ${source.isSpace ? 3 : 2}',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: busy
                  ? const Center(child: CircularProgressIndicator())
                  : step == 1
                      ? roomPicker()
                      : SingleChildScrollView(
                          child: step == 0 ? people() : reviewBody(),
                        ),
            ),
            if (reviewError != null)
              Text(
                reviewError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (over)
              Text(
                'Choose fewer rooms or people. A batch can send up to $maxInvitations invitations and history shares.',
              ),
            const Divider(),
            button(
              step == 0
                  ? (source.isSpace
                      ? 'Next: choose rooms'
                      : 'Review invitations')
                  : step == 1
                      ? invitationCount == 0
                          ? 'Review history sharing'
                          : 'Review $invitationCount ${invitationCount == 1 ? 'invitation' : 'invitations'}'
                      : invitationCount == 0
                          ? 'Share history'
                          : 'Send $invitationCount ${invitationCount == 1 ? 'invitation' : 'invitations'}',
              busy ||
                      selected.isEmpty ||
                      step > 0 &&
                          (over ||
                              invitationCount == 0 &&
                                  (step == 1
                                      ? grants.isEmpty
                                      : (!shareExisting || grants.isEmpty)))
                  ? null
                  : step == 0
                      ? nextPeople
                      : step == 1
                          ? review
                          : send,
            ),
            button(
              busy || step == 0 ? 'Cancel' : 'Back',
              busy
                  ? () => Navigator.of(context).pop()
                  : step == 0
                      ? () => Navigator.of(context).pop()
                      : back,
              secondary: true,
            ),
          ],
        ),
      ),
    );
  }
}
