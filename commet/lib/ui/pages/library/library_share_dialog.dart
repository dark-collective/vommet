// Vommet issue 731, phase 2: how a collection (a sticker room and every pack
// in it) is shared. Private, Followers (anyone with the link follows, only
// admins edit) or Community (contributors at power level 50 edit its
// packs). Changes apply as they are picked.
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/matrix/components/emoticon/library_store.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/send_invitation.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/library_sharing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class LibraryShareDialog extends StatefulWidget {
  const LibraryShareDialog(
      {required this.client,
      required this.store,
      required this.room,
      super.key});

  final MatrixClient client;
  final LibraryStore store;
  final matrix.Room room;

  static Future<void> show(BuildContext context,
          {required MatrixClient client,
          required LibraryStore store,
          required matrix.Room room}) =>
      AdaptiveDialog.show(context,
          title: title,
          builder: (context) =>
              LibraryShareDialog(client: client, store: store, room: room));

  static String get title => Intl.message("Share",
      desc: "Title of the dialog choosing how a collection of packs is shared",
      name: "libraryShareTitle");

  static String get promptShare => Intl.message("Share…",
      desc: "Library pack pane button opening the sharing dialog",
      name: "libraryPromptShare");

  static String libraryShareAppliesTo(String room) =>
      Intl.message("Sharing applies to every pack in $room.",
          args: [room],
          name: "libraryShareAppliesTo",
          desc: "Top of the sharing dialog: the mode is for the whole room");

  static String get modePrivate => Intl.message("Private",
      desc: "Sharing mode: only you and people you invite",
      name: "libraryModePrivate");

  static String get explainPrivate =>
      Intl.message("Only you and people you invite.",
          desc: "Explains the Private sharing mode",
          name: "libraryExplainModePrivate");

  static String get modeFollowers => Intl.message("Followers",
      desc: "Sharing mode: people follow it, only you edit",
      name: "libraryModeFollowers");

  static String get explainFollowers => Intl.message(
      "Anyone with the link can follow. Followers get your edits live; only you edit.",
      desc: "Explains the Followers sharing mode",
      name: "libraryExplainModeFollowers");

  static String get modeCommunity => Intl.message("Community",
      desc: "Sharing mode: like Followers, plus contributors who edit",
      name: "libraryModeCommunity");

  static String get explainCommunity => Intl.message(
      "Like Followers, plus contributors you pick can add, change and remove items in its packs.",
      desc: "Explains the Community sharing mode",
      name: "libraryExplainModeCommunity");

  static String get labelAnyoneCanFollow => Intl.message(
      "Anyone with the link can follow",
      desc:
          "Switch in a Community collection: public (on) or invite only (off)",
      name: "libraryLabelAnyoneCanFollow");

  static String get headerContributors => Intl.message("Contributors",
      desc: "Heading of the list of people who may edit a Community collection",
      name: "libraryHeaderContributors");

  static String get labelNoContributors => Intl.message("No contributors yet",
      desc: "Sharing dialog, when a Community collection has no contributors",
      name: "libraryLabelNoContributors");

  static String get promptAddContributor => Intl.message("Add contributor",
      desc: "Button picking a person to edit a Community collection",
      name: "libraryPromptAddContributor");

  static String get promptRemoveContributor =>
      Intl.message("Remove contributor",
          desc: "Tooltip of the button taking editing away from a contributor",
          name: "libraryPromptRemoveContributor");

  static String get noteContributors => Intl.message(
      "Contributors can also remove anyone's items. The room history shows who changed what.",
      desc: "Note under the list of contributors",
      name: "libraryNoteContributors");

  static String get headerLink => Intl.message("Link",
      desc: "Heading of the link to follow a collection",
      name: "libraryHeaderLink");

  static String get promptCopyLink => Intl.message("Copy link",
      desc: "Tooltip of the button copying the link to follow a collection",
      name: "libraryPromptCopyLink");

  static String get labelLinkCopied => Intl.message("Link copied",
      desc: "Shown after copying the link to follow a collection",
      name: "libraryLabelLinkCopied");

  static String get promptInvitePeople => Intl.message("Invite people…",
      desc: "Button inviting people to a collection",
      name: "libraryPromptInvitePeople");

  static String get noticeFollowersSeen => Intl.message(
      "Followers join this room, so its members can see who follows.",
      desc: "Privacy notice in the sharing dialog for Followers and Community",
      name: "libraryNoticeFollowersSeen");

  static String get failed => Intl.message("That didn't work. Try again.",
      desc: "Sharing dialog error: a change could not be saved",
      name: "libraryShareFailed");

  @override
  State<LibraryShareDialog> createState() => _LibraryShareDialogState();
}

class _LibraryShareDialogState extends State<LibraryShareDialog> {
  bool busy = false;
  String? error;

  matrix.Room get room => widget.room;

  // What the room says, changed as soon as something is picked.
  late CollectionMode mode = LibraryStore.modeOf(room);
  late bool anyoneCanFollow = LibraryStore.joinRuleOf(room) == "public";
  late Set<String> contributors = LibraryStore.contributorsOf(room);

  Future<void> change(Future<void> Function() op,
      {void Function()? optimistic}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      optimistic?.call();
    });
    try {
      await op();
    } catch (e) {
      Log.w("Library: sharing change failed: $e");
      if (mounted) {
        setState(() {
          error = LibraryShareDialog.failed;
          // Back to what the room says.
          mode = LibraryStore.modeOf(room);
          anyoneCanFollow = LibraryStore.joinRuleOf(room) == "public";
          contributors = LibraryStore.contributorsOf(room);
        });
      }
    }
    if (!mounted) return;
    setState(() => busy = false);
  }

  Future<void> setMode(CollectionMode next) {
    // A community starts open, like Followers; its switch can close it.
    final open = next != CollectionMode.private;
    return change(() => widget.store.setMode(room, next, anyoneCanFollow: open),
        optimistic: () {
      mode = next;
      anyoneCanFollow = open;
      if (next != CollectionMode.community) contributors = {};
    });
  }

  Future<void> setAnyoneCanFollow(bool value) =>
      change(() => widget.store.setMode(room, mode, anyoneCanFollow: value),
          optimistic: () => anyoneCanFollow = value);

  InvitationComponent? get invitation =>
      widget.client.getComponent<InvitationComponent>();

  Future<void> addContributor() async {
    final component = invitation;
    if (component == null) return;
    await AdaptiveDialog.show(context,
        title: LibraryShareDialog.promptAddContributor,
        builder: (context) => SendInvitationWidget(widget.client, component,
            showSuggestions: true,
            existingMembers: contributors,
            onUserPicked: (userId) => change(
                () => widget.store.addContributor(room, userId),
                optimistic: () => contributors = {...contributors, userId})));
  }

  Future<void> removeContributor(String userId) =>
      change(() => widget.store.removeContributor(room, userId),
          optimistic: () => contributors = {...contributors}..remove(userId));

  void invitePeople() {
    final component = invitation;
    if (component == null) return;
    AdaptiveDialog.show(context,
        builder: (context) => SendInvitationWidget(widget.client, component,
            roomId: room.id, displayName: room.getLocalizedDisplayname()));
  }

  void copyLink(String link) {
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(LibraryShareDialog.labelLinkCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final shared = mode != CollectionMode.private;
    final link = widget.store.linkTo(room);

    Widget option(CollectionMode m, String title, String explain) =>
        RadioListTile<CollectionMode>(
          value: m,
          title: Text(title),
          subtitle: Text(explain),
          contentPadding: EdgeInsets.zero,
        );

    return SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(LibraryShareDialog.libraryShareAppliesTo(
              room.getLocalizedDisplayname())),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 8),
          RadioGroup<CollectionMode>(
            groupValue: mode,
            onChanged: (v) {
              if (v != null && v != mode) setMode(v);
            },
            child: Column(children: [
              option(CollectionMode.private, LibraryShareDialog.modePrivate,
                  LibraryShareDialog.explainPrivate),
              option(CollectionMode.followers, LibraryShareDialog.modeFollowers,
                  LibraryShareDialog.explainFollowers),
              option(CollectionMode.community, LibraryShareDialog.modeCommunity,
                  LibraryShareDialog.explainCommunity),
            ]),
          ),
          if (mode == CollectionMode.community) ...[
            SwitchListTile(
              value: anyoneCanFollow,
              onChanged: busy ? null : setAnyoneCanFollow,
              title: Text(LibraryShareDialog.labelAnyoneCanFollow),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Text(LibraryShareDialog.headerContributors,
                style: theme.textTheme.titleSmall),
            if (contributors.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child:
                    Text(LibraryShareDialog.labelNoContributors, style: muted),
              ),
            for (final userId in contributors.toList()..sort())
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(
                    room
                        .unsafeGetUserFromMemoryOrFallback(userId)
                        .calcDisplayname(),
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(userId, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: LibraryShareDialog.promptRemoveContributor,
                  icon: const Icon(Icons.close),
                  onPressed: busy ? null : () => removeContributor(userId),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.person_add_alt),
                label: Text(LibraryShareDialog.promptAddContributor),
                onPressed: busy ? null : addContributor,
              ),
            ),
            Text(LibraryShareDialog.noteContributors, style: muted),
          ],
          if (shared) ...[
            const SizedBox(height: 16),
            Text(LibraryShareDialog.headerLink,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: SelectableText(link,
                    maxLines: 2, style: theme.textTheme.bodyMedium),
              ),
              IconButton(
                tooltip: LibraryShareDialog.promptCopyLink,
                icon: const Icon(Icons.copy),
                onPressed: () => copyLink(link),
              ),
            ]),
            const SizedBox(height: 8),
            Text(LibraryShareDialog.noticeFollowersSeen, style: muted),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.group_add_outlined),
              label: Text(LibraryShareDialog.promptInvitePeople),
              onPressed: invitePeople,
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(CommonStrings.promptDone),
            ),
          ),
        ],
      ),
    );
  }
}
