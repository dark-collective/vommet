import 'package:commet/client/components/personal_pins/personal_pins.dart';
import 'package:commet/client/components/pinned_messages/pinned_messages_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/molecules/timeline_events/personal_pin_menu.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_view_single.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomPinnedMessagesWidget extends StatefulWidget {
  const RoomPinnedMessagesWidget(
      {required this.room, this.onEventClicked, super.key});
  final Room room;
  final void Function(String eventId)? onEventClicked;

  @override
  State<RoomPinnedMessagesWidget> createState() =>
      _RoomPinnedMessagesWidgetState();
}

class _RoomPinnedMessagesWidgetState extends State<RoomPinnedMessagesWidget> {
  List<TimelineEvent>? events;

  /// Vommet: messages pinned only for yourself, newest first.
  List<TimelineEvent>? personalEvents;

  String get noPinnedMessages => Intl.message("No messages have been pinned!",
      desc:
          "Placeholder label in the pinned messages menu that is shown when there are no pinned messages",
      name: "noPinnedMessages");

  String get labelPinnedOnlyYou => Intl.message("Only you",
      name: "labelPinnedOnlyYou",
      desc: "Heading in the pinned messages panel for messages you pinned "
          "only for yourself");

  String get labelPinnedOnlyYouDescription => Intl.message(
      "Pinned for yourself",
      name: "labelPinnedOnlyYouDescription",
      desc: "Note next to the Only you heading in the pinned messages panel");

  String get labelPinnedEveryone => Intl.message("Everyone",
      name: "labelPinnedEveryone",
      desc: "Heading in the pinned messages panel for messages pinned for "
          "the whole room");

  String get labelPinnedEveryoneDescription => Intl.message(
      "Pinned for the room",
      name: "labelPinnedEveryoneDescription",
      desc: "Note next to the Everyone heading in the pinned messages panel");

  @override
  void initState() {
    super.initState();

    loadPinnedMessages();
    PersonalPins.changed.addListener(loadPersonalPins);
  }

  @override
  void dispose() {
    PersonalPins.changed.removeListener(loadPersonalPins);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (events == null || personalEvents == null) {
      return const tiamat.Tile(
          child: Center(child: CircularProgressIndicator()));
    }

    if (events!.isEmpty && personalEvents!.isEmpty) {
      return tiamat.Tile(
          child: Center(child: tiamat.Text.label(noPinnedMessages)));
    }

    // Headings only when you have pins of your own; otherwise the panel
    // looks as it always did.
    final mine = personalEvents!;
    final sections = mine.isNotEmpty;

    return tiamat.Tile.low(
      child: Column(
        children: [
          Flexible(
            child: ListView(
              padding: EdgeInsets.all(0),
              children: [
                if (sections)
                  heading(Icons.push_pin_outlined, labelPinnedOnlyYou,
                      labelPinnedOnlyYouDescription),
                for (final e in mine) buildEntry(e, personal: true),
                if (sections && events!.isNotEmpty)
                  heading(Icons.push_pin, labelPinnedEveryone,
                      labelPinnedEveryoneDescription),
                for (final e in events!) buildEntry(e),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget heading(IconData icon, String title, String description) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Row(children: [
        Icon(icon, size: 16, color: dim),
        const SizedBox(width: 6),
        tiamat.Text.labelEmphasised(title),
        const SizedBox(width: 8),
        Flexible(child: tiamat.Text.labelLow(description)),
      ]),
    );
  }

  Widget buildEntry(TimelineEvent data, {bool personal = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: () => widget.onEventClicked?.call(data.eventId),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: personal
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TimelineEventViewSingle(
                                room: widget.room, event: data),
                          ),
                          IconButton(
                            key: ValueKey("personal-unpin-${data.eventId}"),
                            tooltip: PersonalPinMenu.promptUnpinForMe,
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                PersonalPins.unpin(widget.room, data.eventId),
                          ),
                        ],
                      )
                    : TimelineEventViewSingle(room: widget.room, event: data),
              ),
            )),
      ),
    );
  }

  void loadPinnedMessages() async {
    final comp = widget.room.getComponent<PinnedMessagesComponent>()!;
    var eventIds = comp.getPinnedMessages();

    var allEvents = await Future.wait<TimelineEvent?>(
        eventIds.map((id) => widget.room.getEvent(id)));

    if (!mounted) return;
    setState(() {
      events = List<TimelineEvent>.from(allEvents.where((e) => e != null));
    });
    loadPersonalPins();
  }

  void loadPersonalPins() async {
    final ids = PersonalPins.of(widget.room).reversed.toList();
    final found = await Future.wait<TimelineEvent?>(
        ids.map((id) => widget.room.getEvent(id)));

    if (!mounted) return;
    setState(() {
      personalEvents = found.whereType<TimelineEvent>().toList();
    });
  }
}
