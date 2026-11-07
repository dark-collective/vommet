import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/room_encryption_default.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

abstract class RoomField {
  Widget build(CreateRoomArgs args, Function() onArgsChanged);

  void setDefaults(CreateRoomArgs args);

  bool isValid(CreateRoomArgs args);
}

class RoomFieldType implements RoomField {
  final RoomType type;

  RoomFieldType(this.type);

  @override
  Widget build(CreateRoomArgs args, Function() onArgsChanged) {
    return Container();
  }

  @override
  void setDefaults(CreateRoomArgs args) {
    args.roomType = type;
  }

  @override
  bool isValid(CreateRoomArgs args) {
    return args.roomType == type;
  }
}

class RoomFieldName implements RoomField {
  String get promptRoomName => Intl.message(
        "Room Name",
        name: "promptRoomName",
        desc: "Prompt to enter a room name, placeholder text for text input",
      );

  @override
  Widget build(CreateRoomArgs args, Function() onArgsChanged) {
    return TextField(
      onChanged: (value) {
        args.name = value;
        onArgsChanged();
      },
      decoration: InputDecoration(hint: tiamat.Text.labelLow(promptRoomName)),
    );
  }

  @override
  void setDefaults(CreateRoomArgs args) {}

  @override
  bool isValid(CreateRoomArgs args) {
    return args.name?.isNotEmpty == true;
  }
}

class RoomFieldTopic implements RoomField {
  String get promptTopic => Intl.message(
        "Topic (Optional)",
        name: "promptTopic",
        desc:
            "Prompt to enter a topic for room or space, specifying that doing so is optional",
      );

  @override
  Widget build(CreateRoomArgs args, Function() onArgsChanged) {
    return TextField(
      onChanged: (value) {
        args.topic = value;
        onArgsChanged();
      },
      // Vommet: maxLines alone fixes the field at 3 lines tall, so a one-line
      // topic floated well above the underline; start at one line and grow.
      minLines: 1,
      maxLines: 3,
      decoration: InputDecoration(hint: tiamat.Text.labelLow(promptTopic)),
    );
  }

  @override
  void setDefaults(CreateRoomArgs args) {}

  @override
  bool isValid(CreateRoomArgs args) {
    return true;
  }
}

class RoomFieldEncryption implements RoomField {
  final bool canEnableEncryption;
  final bool defaultEnabled;

  String get promptEnableEncryption => Intl.message(
        "Enable Encryption",
        name: "promptEnableEncryption",
        desc: "Short prompt to enable encryption for a room",
      );

  String get encryptionCannotBeDisabledExplanation => Intl.message(
        "If enabled, encryption cannot be disabled later",
        name: "encryptionCannotBeDisabledExplanation",
        desc: "Explains that encryption cannot be disabled once enabled",
      );

  RoomFieldEncryption(
      {required this.defaultEnabled, this.canEnableEncryption = true});

  @override
  Widget build(CreateRoomArgs args, Function() onArgsChanged) {
    Widget result = IgnorePointer(
      ignoring: canEnableEncryption == false,
      child: Opacity(
        opacity: canEnableEncryption ? 1 : 0.5,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.label(promptEnableEncryption),
                tiamat.Text.labelLow(encryptionCannotBeDisabledExplanation)
              ],
            ),
            tiamat.Switch(
              state: args.enableE2EE == true,
              onChanged: (value) {
                args.enableE2EE = value;
                onArgsChanged();
              },
            )
          ],
        ),
      ),
    );

    if (!canEnableEncryption) {
      result = tiamat.Tooltip(
          child: result,
          text: "Sorry, Encryption is not yet supported on this type of room");
    }

    return result;
  }

  @override
  void setDefaults(CreateRoomArgs args) {
    // Vommet: a room type that starts encrypted starts from Settings ›
    // Privacy › Encrypt new rooms instead (Vommet issue 524).
    args.enableE2EE =
        defaultEnabled && canEnableEncryption && encryptNewRoomsByDefault.value;
  }

  @override
  bool isValid(CreateRoomArgs args) {
    return args.enableE2EE != null;
  }
}

class RoomFieldVisibility implements RoomField {
  Space? currentSpace;
  Client client;

  RoomFieldVisibility({required this.client, this.currentSpace});

  static String get roomVisibilityPrivateExplanation => Intl.message(
        "This room will only be accessible by invitation",
        name: "roomVisibilityPrivateExplanation",
        desc: "Explains what 'private' room visibility means",
      );

  static String get roomVisibilityPublicExplanation => Intl.message(
        "This room will be publically accessible by anyone on the internet",
        name: "roomVisibilityPublicExplanation",
        desc: "Explains what 'public' visibility means",
      );

  static String get labelVisibilityPrivate => Intl.message(
        "Private",
        name: "labelVisibilityPrivate",
        desc: "Short label for room visibility private",
      );

  static String get labelVisibilityPublic => Intl.message(
        "Public",
        name: "labelVisibilityPublic",
        desc: "Short label for room visibility public",
      );

  static String get roomVisibilityRestrictedExplanation => Intl.message(
        "This room will be available to anyone who is a member of it's parent spaces",
        name: "roomVisibilityRestrictedExplanation",
        desc: "Explains what 'restricted' visibility means",
      );

  static String get labelVisibilityRestricted => Intl.message(
        "Restricted",
        name: "labelVisibilityRestricted",
        desc: "Short label for room visibility restricted",
      );

  static String get labelVisibilityKnock => Intl.message(
        "Ask to join",
        name: "labelVisibilityKnock",
        desc: "Short label for room visibility 'knock': people ask to join",
      );

  static String get roomVisibilityKnockExplanation => Intl.message(
        "Anyone can ask to join; a member with permission lets them in",
        name: "roomVisibilityKnockExplanation",
        desc: "Explains what 'ask to join' (knock) visibility means",
      );

  static String get labelVisibilityKnockRestricted => Intl.message(
        "Ask to join, or join from a space",
        name: "labelVisibilityKnockRestricted",
        desc:
            "Short label for room visibility 'knock_restricted': space members join directly, anyone else asks",
      );

  static String get roomVisibilityKnockRestrictedExplanation => Intl.message(
        "Members of its parent spaces can join directly; anyone else can ask to join",
        name: "roomVisibilityKnockRestrictedExplanation",
        desc: "Explains what 'knock_restricted' visibility means",
      );

  @override
  void setDefaults(CreateRoomArgs args) {
    if (currentSpace != null) {
      args.visibility = RoomVisibilityRestricted([currentSpace!.identifier]);
    } else {
      args.visibility = RoomVisibilityPrivate();
    }
  }

  @override
  bool isValid(CreateRoomArgs args) {
    return args.visibility != null;
  }

  @override
  Widget build(CreateRoomArgs args, Function() onArgsChanged) {
    return SizedBox(
      height: 90,
      child: tiamat.DropdownSelector<RoomVisibility?>(
        itemHeight: 80,
        value: args.visibility,
        items: [
          RoomVisibilityPrivate(),
          RoomVisibilityPublic(),
          if (currentSpace != null)
            RoomVisibilityRestricted([currentSpace!.identifier])
        ],
        onItemSelected: (item) {
          args.visibility = item;
          onArgsChanged();
        },
        itemBuilder: (item) {
          return buildRoomVisibility(client, item);
        },
      ),
    );
  }

  static Widget buildRoomVisibility(Client client, RoomVisibility? item) {
    String? title;
    Widget icon = Icon(RoomVisibility.icon(item));
    String? subtitle;
    switch (item) {
      case final RoomVisibilityPublic _:
        title = labelVisibilityPublic;
        subtitle = roomVisibilityPublicExplanation;
        break;
      case final RoomVisibilityPrivate _:
        title = labelVisibilityPrivate;
        subtitle = roomVisibilityPrivateExplanation;
        break;
      case final RoomVisibilityRestricted restricted:
        title = labelVisibilityRestricted;
        subtitle = roomVisibilityRestrictedExplanation;

        icon = Row(
            spacing: 4,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i in restricted.spaces) buildSpaceIcon(client, i),
            ]);
        break;
      case final RoomVisibilityKnock knock when knock.spaces.isEmpty:
        title = labelVisibilityKnock;
        subtitle = roomVisibilityKnockExplanation;
        break;
      case final RoomVisibilityKnock knock:
        title = labelVisibilityKnockRestricted;
        subtitle = roomVisibilityKnockRestrictedExplanation;
        icon = Row(
            spacing: 4,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              icon,
              for (var i in knock.spaces) buildSpaceIcon(client, i),
            ]);
        break;
      case null:
        break;
    }

    return Padding(
      padding: const EdgeInsets.all(0.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 8, 0),
                  child: icon,
                ),
                tiamat.Text.label(title!),
              ],
            ),
          ),
          tiamat.Text.labelLow(
            subtitle!,
            overflow: TextOverflow.fade,
          ),
        ],
      ),
    );
  }

  static Widget buildSpaceIcon(Client client, String i) {
    Space? space = client.getSpace(i);

    return tiamat.Tooltip(
      text: space?.displayName ?? i,
      child: tiamat.Avatar(
          radius: 13,
          image: space?.avatar,
          placeholderText: space?.displayName ?? i,
          placeholderColor: space?.color ?? MatrixPeer.hashColor(i)),
    );
  }
}

class RoomCreatorWidget extends StatefulWidget {
  const RoomCreatorWidget({required this.fields, super.key});

  final List<RoomField> fields;

  @override
  State<RoomCreatorWidget> createState() => _RoomCreatorWidgetState();
}

class _RoomCreatorWidgetState extends State<RoomCreatorWidget> {
  CreateRoomArgs args = CreateRoomArgs();
  bool valid = false;

  String get promptConfirmRoomCreation => Intl.message(
        "Create Room!",
        name: "promptConfirmRoomCreation",
        desc: "Label for a button which confirms the creation of a room",
      );

  @override
  void initState() {
    for (var entry in widget.fields) entry.setDefaults(args);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).desktop ? 500 : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          for (var entry in widget.fields) entry.build(args, onArgsChanged),
          IgnorePointer(
            ignoring: !valid,
            child: Opacity(
              opacity: valid ? 1 : 0.4,
              child: tiamat.Button(
                text: promptConfirmRoomCreation,
                onTap: () {
                  Navigator.of(context).pop(args);
                },
              ),
            ),
          )
        ],
      ),
    );
  }

  void onArgsChanged() {
    bool isValid = true;

    for (var entry in widget.fields) {
      isValid = isValid && entry.isValid(args);
    }

    setState(() {
      valid = isValid;
    });

    print(args);
  }
}

/// Room v12 co-owners (`additional_creators`), in a collapsed "Advanced"
/// section. Setting any creates the room as v12.
class RoomFieldCoOwners implements RoomField {
  static String get labelRoomCreationAdvanced => Intl.message(
        "Advanced",
        name: "labelRoomCreationAdvanced",
        desc: "Header of the collapsed advanced options when creating a room",
      );

  static String get labelRoomCoOwners => Intl.message(
        "Co-owners (optional)",
        name: "labelRoomCoOwners",
        desc:
            "Label of the field for extra users who own a room with its creator",
      );

  static String get promptAddRoomCoOwner => Intl.message(
        "Add a user ID, e.g. @name:server",
        name: "promptAddRoomCoOwner",
        desc: "Placeholder of the text input that adds a room co-owner",
      );

  static String get roomCoOwnersWarning => Intl.message(
        "Co-owners have the same full power as you. You can't demote or remove them later.",
        name: "roomCoOwnersWarning",
        desc: "Warning shown under the room co-owners field",
      );

  static String roomCoOwnersRoomVersionNote(String version) => Intl.message(
        "This room will be created as room version $version.",
        args: [version],
        name: "roomCoOwnersRoomVersionNote",
        desc:
            "Shown when co-owners are set, because they need a newer room version",
      );

  static bool isUserId(String value) =>
      RegExp(r"^@[^:\s]+:[^\s]+$").hasMatch(value);

  /// Adds [value] to [coOwners] if it is a user ID not already listed.
  static bool addCoOwner(List<String> coOwners, String value) {
    final id = value.trim();
    if (!isUserId(id) || coOwners.contains(id)) return false;
    coOwners.add(id);
    return true;
  }

  @override
  Widget build(CreateRoomArgs args, Function() onArgsChanged) {
    return _CoOwnersField(args: args, onArgsChanged: onArgsChanged);
  }

  @override
  void setDefaults(CreateRoomArgs args) {}

  @override
  bool isValid(CreateRoomArgs args) {
    return true;
  }
}

class _CoOwnersField extends StatelessWidget {
  const _CoOwnersField({required this.args, required this.onArgsChanged});

  final CreateRoomArgs args;
  final Function() onArgsChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: tiamat.Text.label(RoomFieldCoOwners.labelRoomCreationAdvanced),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        CoOwnersEditor(
          coOwners: args.additionalCreators,
          onChanged: onArgsChanged,
          footer: args.additionalCreators.isEmpty
              ? null
              : tiamat.Text.labelLow(
                  RoomFieldCoOwners.roomCoOwnersRoomVersionNote(
                      CreateRoomArgs.coOwnerRoomVersion)),
        ),
      ],
    );
  }
}

/// Edits a list of room v12 co-owners in place: chips, a user ID input and
/// the warning. Shared by room creation and the Replace room dialog.
class CoOwnersEditor extends StatefulWidget {
  const CoOwnersEditor(
      {required this.coOwners,
      required this.onChanged,
      this.footer,
      super.key});

  final List<String> coOwners;
  final Function() onChanged;
  final Widget? footer;

  @override
  State<CoOwnersEditor> createState() => _CoOwnersEditorState();
}

class _CoOwnersEditorState extends State<CoOwnersEditor> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void add() {
    if (RoomFieldCoOwners.addCoOwner(widget.coOwners, controller.text)) {
      controller.clear();
      setState(() {});
      widget.onChanged();
    }
  }

  void remove(String id) {
    widget.coOwners.remove(id);
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final coOwners = widget.coOwners;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.label(RoomFieldCoOwners.labelRoomCoOwners),
        const SizedBox(height: 8),
        if (coOwners.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in coOwners)
                  InputChip(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      label: Text(id),
                      onDeleted: () => remove(id)),
              ],
            ),
          ),
        TextField(
          controller: controller,
          onSubmitted: (_) => add(),
          decoration: InputDecoration(
            hint: tiamat.Text.labelLow(RoomFieldCoOwners.promptAddRoomCoOwner),
            suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: add),
          ),
        ),
        const SizedBox(height: 8),
        tiamat.Text.labelLow(RoomFieldCoOwners.roomCoOwnersWarning),
        if (widget.footer case final footer?) footer,
      ],
    );
  }
}
