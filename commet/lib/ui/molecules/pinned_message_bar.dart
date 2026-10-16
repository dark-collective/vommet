// Vommet: a Telegram-style bar above the chat showing the room's pinned
// messages. Tapping it jumps to the pin shown and moves on to the next older
// one; the list button opens the pinned messages panel.

import 'dart:async';

import 'package:commet/client/components/personal_pins/personal_pins.dart';
import 'package:commet/client/components/pinned_messages/pinned_messages_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// One pin as the bar orders it.
class PinnedBarEntry {
  const PinnedBarEntry(this.eventId, this.time, {this.personal = false});
  final String eventId;
  final DateTime time;

  /// Pinned only for yourself.
  final bool personal;

  /// Room and personal pins together, newest message first. A message
  /// pinned both ways counts once, as a room pin.
  static List<PinnedBarEntry> merge(
      List<PinnedBarEntry> room, List<PinnedBarEntry> personal) {
    final ids = room.map((e) => e.eventId).toSet();
    final all = [
      ...room,
      ...personal.where((e) => ids.add(e.eventId)),
    ];
    all.sort((a, b) => b.time.compareTo(a.time));
    return all;
  }

  /// The track shows at most [max] segments; returns how many to draw and
  /// which one (counted from the bottom, newest) is lit for [index].
  static ({int segments, int lit}) track(int index, int count, {int max = 4}) {
    if (count <= max) return (segments: count, lit: index);
    final start = (index ~/ max * max).clamp(0, count - max);
    return (segments: max, lit: index - start);
  }
}

class PinnedMessageBar extends StatefulWidget {
  const PinnedMessageBar({required this.room, super.key});

  final Room room;

  static final BoolPreference showBar =
      BoolPreference("vommet_pinned_bar", defaultValue: true);

  static final BoolPreference includePersonal =
      BoolPreference("vommet_pinned_bar_personal", defaultValue: true);

  /// Pins further back than this aren't loaded for the bar.
  static const int maxPins = 50;

  @override
  State<PinnedMessageBar> createState() => _PinnedMessageBarState();
}

class _PinnedMessageBarState extends State<PinnedMessageBar> {
  List<PinnedBarEntry> entries = const [];
  final Map<String, TimelineEvent> events = {};
  int index = 0;
  int _load = 0;
  final List<StreamSubscription> subs = [];

  String get pinnedBarTitle => Intl.message("Pinned message",
      name: "pinnedBarTitle",
      desc: "Title of the pinned message bar above the chat");

  String pinnedBarTitleNumber(int number) =>
      Intl.message("Pinned message #$number",
          args: [number],
          name: "pinnedBarTitleNumber",
          desc: "Title of the pinned message bar when it shows an older pin; "
              "number counts the pins from the oldest");

  String get pinnedBarTitlePersonal => Intl.message("Pinned for you",
      name: "pinnedBarTitlePersonal",
      desc: "Title of the pinned message bar when it shows a message you "
          "pinned only for yourself");

  String get pinnedBarAllPins => Intl.message("All pinned messages",
      name: "pinnedBarAllPins",
      desc: "Tooltip of the button on the pinned message bar that opens "
          "the list of pinned messages");

  PinnedMessagesComponent? get component =>
      widget.room.getComponent<PinnedMessagesComponent>();

  @override
  void initState() {
    super.initState();
    final comp = component;
    if (comp != null) subs.add(comp.onPinsChanged.listen((_) => load()));
    subs.add(PinnedMessageBar.showBar.onChanged.listen((_) => load()));
    subs.add(PinnedMessageBar.includePersonal.onChanged.listen((_) => load()));
    PersonalPins.changed.addListener(load);
    load();
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    PersonalPins.changed.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    final ticket = ++_load;
    final comp = component;
    if (!PinnedMessageBar.showBar.value || comp == null) {
      if (mounted) setState(() => entries = const []);
      return;
    }

    final roomIds =
        comp.getPinnedMessages().take(PinnedMessageBar.maxPins).toList();
    final personalIds = PinnedMessageBar.includePersonal.value &&
            PersonalPins.supported(widget.room)
        ? PersonalPins.of(widget.room)
            .reversed
            .take(PinnedMessageBar.maxPins)
            .toList()
        : const <String>[];

    final wanted = {...roomIds, ...personalIds};
    await Future.wait(
        wanted.where((id) => !events.containsKey(id)).map((id) async {
      final event = await widget.room.getEvent(id);
      if (event != null) events[id] = event;
    }));
    if (!mounted || ticket != _load) return;

    List<PinnedBarEntry> found(List<String> ids, bool personal) => [
          for (final id in ids)
            if (events[id] case final e?)
              PinnedBarEntry(id, e.originServerTs, personal: personal)
        ];

    final shown = entries.elementAtOrNull(index)?.eventId;
    final next =
        PinnedBarEntry.merge(found(roomIds, false), found(personalIds, true));
    setState(() {
      entries = next;
      final keep = next.indexWhere((e) => e.eventId == shown);
      index = keep >= 0 ? keep : 0;
    });
  }

  void onTap() {
    final entry = entries.elementAtOrNull(index);
    if (entry == null) return;
    EventBus.jumpToEvent.add(entry.eventId);
    EventBus.focusTimeline.add(null);
    setState(() => index = (index + 1) % entries.length);
  }

  @override
  Widget build(BuildContext context) {
    final entry = entries.elementAtOrNull(index);
    final event = entry == null ? null : events[entry.eventId];
    if (entry == null || event == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final title = entry.personal
        ? pinnedBarTitlePersonal
        : index == 0
            ? pinnedBarTitle
            : pinnedBarTitleNumber(entries.length - index);
    final sender = widget.room.getMemberOrFallback(event.senderId).displayName;
    final body = event.plainTextBody.replaceAll("\n", " ");
    final canList =
        MediaQuery.of(context).mobile || !preferences.hideRoomSidePanel.value;

    return Material(
      key: const ValueKey("pinned-message-bar"),
      color: scheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(children: [
            _track(scheme, entries.length),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    if (entry.personal) ...[
                      Icon(Icons.push_pin_outlined,
                          size: 13, color: scheme.primary),
                      const SizedBox(width: 3),
                    ],
                    Text(title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary)),
                  ]),
                  const SizedBox(height: 1),
                  Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: "$sender: ",
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface)),
                        TextSpan(
                            text: body,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ]),
                      style: const TextStyle(fontSize: 13.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (canList)
              IconButton(
                tooltip: pinnedBarAllPins,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: Icon(Icons.format_list_bulleted,
                    color: scheme.onSurfaceVariant),
                onPressed: () => EventBus.showPinnedMessages.add(null),
              ),
          ]),
        ),
      ),
    );
  }

  /// Thin vertical track, one segment per pin, newest at the bottom.
  Widget _track(ColorScheme scheme, int count) {
    const height = 36.0;
    final t = PinnedBarEntry.track(index, count);
    final seg = (height - (t.segments - 1) * 2) / t.segments;
    return SizedBox(
      width: 3,
      height: height,
      child: Column(children: [
        for (var i = 0; i < t.segments; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          Container(
              width: 3,
              height: seg,
              decoration: BoxDecoration(
                  color: i == t.segments - 1 - t.lit
                      ? scheme.primary
                      : scheme.primary.withAlpha(110),
                  borderRadius: BorderRadius.circular(2))),
        ]
      ]),
    );
  }
}
