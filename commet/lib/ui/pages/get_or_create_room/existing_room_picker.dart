import 'package:commet/client/client.dart';
import 'package:commet/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/matrix/components/calendar_room_component/matrix_calendar_room_component.dart';
import 'package:commet/client/space_child.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/room_search.dart';
import 'package:commet/ui/pages/get_or_create_room/room_creation_strings.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ExistingRoomPicker extends StatefulWidget {
  const ExistingRoomPicker(
      {required this.client, this.filter, this.onPicked, super.key});

  final Client client;
  final bool Function(SpaceChild room)? filter;
  final Function(SpaceChild child)? onPicked;

  @override
  State<ExistingRoomPicker> createState() => _ExistingRoomPickerState();
}

class _ExistingRoomPickerState extends State<ExistingRoomPicker> {
  List<SpaceChild> allChildren = List.empty(growable: true);
  List<SpaceChild> filteredChildren = List.empty();
  Set<RoomType> selectedTypes = {};
  String query = "";

  /// Vommet issue 732: only rooms and spaces that aren't in any of your
  /// spaces yet (off by default).
  bool notInAnySpace = false;
  Set<String> _inSomeSpace = {};

  @override
  void initState() {
    for (var room in widget.client.rooms) {
      allChildren.add(SpaceChildRoom(room));
    }

    for (var space in widget.client.spaces) {
      allChildren.add(SpaceChildSpace(space));
    }

    if (widget.filter != null) {
      allChildren.removeWhere(widget.filter!);
    }

    _inSomeSpace = idsInAnySpace(widget.client, allChildren);

    setSelectedTypes(selectedTypes);

    super.initState();
  }

  void setSelectedTypes(Set<RoomType> types) {
    List<SpaceChild> filtered = List.empty(growable: true);

    if (types.isEmpty) {
      filtered = allChildren;
    } else {
      if (types.contains(RoomType.space))
        filtered.addAll(allChildren.where((i) => i is SpaceChildSpace));

      if (types.contains(RoomType.voipRoom))
        filtered.addAll(allChildren.where((i) {
          if (i case SpaceChildRoom r) {
            return r.child.getComponent<VoipRoomComponent>() != null;
          }
          return false;
        }));

      if (types.contains(RoomType.calendar))
        filtered.addAll(allChildren.where((i) {
          if (i case SpaceChildRoom r) {
            return r.child
                    .getComponent<MatrixCalendarRoomComponent>()
                    ?.isCalendarRoom ==
                true;
          }
          return false;
        }));

      if (types.contains(RoomType.photoAlbum))
        filtered.addAll(allChildren.where((i) {
          if (i case SpaceChildRoom r) {
            return r.child.getComponent<PhotoAlbumRoom>() != null;
          }
          return false;
        }));

      if (types.contains(RoomType.defaultRoom))
        filtered.addAll(allChildren.where((i) {
          if (i case SpaceChildRoom r) {
            return r.child.isSpecialRoomType == false;
          }
          return false;
        }));
    }

    if (notInAnySpace) {
      filtered = filtered.where((c) => !_inSomeSpace.contains(c.id)).toList();
    }

    setState(() {
      selectedTypes = types;
      filteredChildren = _search(filtered, query);
    });
  }

  void setNotInAnySpace(bool value) {
    notInAnySpace = value;
    setSelectedTypes(selectedTypes);
  }

  void setQuery(String value) {
    query = value;
    setSelectedTypes(selectedTypes);
  }

  void pickOnlyResult() {
    if (filteredChildren.length == 1) {
      widget.onPicked?.call(filteredChildren.first);
    }
  }

  static List<SpaceChild> _search(List<SpaceChild> children, String query) {
    return RoomSearch.rank(children, query,
        name: (c) => switch (c) {
              SpaceChildRoom r => r.child.displayName,
              SpaceChildSpace s => s.child.displayName,
              _ => "",
            },
        id: (c) => c.id,
        lastActive: (c) => switch (c) {
              SpaceChildRoom r => r.child.lastEventTimestamp,
              _ => null,
            });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: TextField(
            decoration: InputDecoration(
                icon: const Icon(Icons.search),
                hintText: CommonStrings.promptSearch),
            maxLines: 1,
            autofocus: MediaQuery.of(context).desktop,
            onChanged: setQuery,
            onSubmitted: (_) => pickOnlyResult(),
          ),
        ),
        Padding(
          padding: EdgeInsetsGeometry.all(8),
          child: SegmentedButton(
              emptySelectionAllowed: true,
              multiSelectionEnabled: false,
              segments: [
                ButtonSegment(
                  tooltip: RoomCreationStrings.labelRoomTypeSpace,
                  value: RoomType.space,
                  icon: Icon(Icons.spoke),
                ),
                ButtonSegment(
                  tooltip: RoomCreationStrings.labelRoomTypeTextChat,
                  value: RoomType.defaultRoom,
                  icon: Icon(Icons.tag),
                ),
                ButtonSegment(
                  tooltip: RoomCreationStrings.labelRoomTypeVoiceChat,
                  value: RoomType.voipRoom,
                  icon: Icon(Icons.volume_up),
                ),
                ButtonSegment(
                  tooltip: RoomCreationStrings.labelRoomTypePhotoAlbum,
                  value: RoomType.photoAlbum,
                  icon: Icon(Icons.photo),
                ),
                ButtonSegment(
                  tooltip: RoomCreationStrings.labelRoomTypeCalendar,
                  value: RoomType.calendar,
                  icon: Icon(Icons.calendar_month),
                ),
              ],
              onSelectionChanged: setSelectedTypes,
              selected: selectedTypes),
        ),
        // Vommet issue 732.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: FilterChip(
            label: Text(RoomCreationStrings.labelNotInAnySpace),
            tooltip: RoomCreationStrings.tooltipNotInAnySpace,
            selected: notInAnySpace,
            onSelected: setNotInAnySpace,
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: filteredChildren.length,
            itemBuilder: (context, index) {
              var child = filteredChildren[index];

              String displayName = "";
              Color color = Colors.white;
              ImageProvider? avatar;

              switch (child) {
                // Vommet issue 475: names follow redacted mode.
                case SpaceChildRoom r:
                  displayName =
                      RedactionScope.of(context).roomDisplayName(r.child);
                  color = r.child.defaultColor;
                  avatar = r.child.avatar;
                  break;

                case SpaceChildSpace s:
                  displayName = RedactionScope.of(context)
                      .roomName(s.child.displayName, s.child.identifier);
                  color = s.child.color;
                  avatar = s.child.avatar;
                  break;
              }

              return Padding(
                padding: const EdgeInsets.all(4.0),
                child: Material(
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    onTap: () {
                      widget.onPicked?.call(child);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          tiamat.Avatar(
                              image: avatar,
                              placeholderText: displayName,
                              placeholderColor: color),
                          SizedBox(
                            width: 8,
                          ),
                          Column(
                            children: [tiamat.Text.label(displayName)],
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Vommet issue 732: the ids of [children] that are a room or subspace of
/// one of [client]'s spaces.
Set<String> idsInAnySpace(Client client, Iterable<SpaceChild> children) {
  return {
    for (var c in children)
      if (switch (c) {
        SpaceChildSpace s => client.spaces.any((space) =>
            space.subspaces.any((sub) => sub.identifier == s.child.identifier)),
        _ => client.spaces.any((space) => space.containsRoom(c.id)),
      })
        c.id
  };
}
