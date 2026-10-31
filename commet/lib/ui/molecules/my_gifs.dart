// Vommet: "My GIFs", the GIFs you saved from chats. Saving uses upstream's
// favourite GIFs (kept in your account data, so every device has them); this
// adds saving from any message's menu and the strings around it.
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/library_ops.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MyGifs {
  static String get title => Intl.message("My GIFs",
      desc: "Heading of the GIFs you saved, in the GIF tab of the emoji picker",
      name: "myGifsTitle");

  static String get promptAdd => Intl.message("Add to My GIFs",
      desc: "Message menu item that saves a GIF to your own collection",
      name: "myGifsPromptAdd");

  static String get promptRemove => Intl.message("Remove from My GIFs",
      desc: "Menu item that removes a GIF from your own collection",
      name: "myGifsPromptRemove");

  static String get added => Intl.message("Added to My GIFs",
      desc: "Shown after a GIF was saved to your own collection",
      name: "myGifsAdded");

  static String get removed => Intl.message("Removed from My GIFs",
      desc: "Shown after a GIF was removed from your own collection",
      name: "myGifsRemoved");

  static String get promptUndo => Intl.message("Undo",
      desc: "Button that reverts saving or removing a GIF",
      name: "myGifsPromptUndo");

  static String get emptyTitle => Intl.message("No saved GIFs yet",
      desc: "Shown in the GIF tab when you haven't saved any GIFs",
      name: "myGifsEmptyTitle");

  static String get emptyBody => Intl.message(
      "Right-click a GIF in a chat (or press and hold on a phone) and pick \"Add to My GIFs\".",
      desc: "Explains how to save GIFs, in the empty GIF tab",
      name: "myGifsEmptyBody");

  static String get searchOff => Intl.message("GIF search is off",
      desc:
          "Shown in the GIF tab instead of the search box while GIF search is off",
      name: "myGifsSearchOff");

  static String get promptTurnOnSearch => Intl.message("Turn on",
      desc: "Button in the GIF tab that turns GIF search on",
      name: "myGifsPromptTurnOnSearch");

  static String get copyTitle => Intl.message("Save an unencrypted copy?",
      desc:
          "Title of the question asked before saving a GIF from an encrypted room to My GIFs",
      name: "myGifsCopyTitle");

  static String get copyBody => Intl.message(
      "This GIF is end-to-end encrypted. My GIFs keeps an unencrypted copy that your homeserver can see.",
      desc:
          "Explains, before saving a GIF from an encrypted room, that My GIFs keeps an unencrypted copy",
      name: "myGifsCopyBody");

  static String get copyDontAsk => Intl.message("Don't ask again",
      desc:
          "Checkbox in the question before saving a GIF from an encrypted room; when ticked, the question isn't shown again",
      name: "myGifsCopyDontAsk");

  static String get promptSaveCopy => Intl.message("Save copy",
      desc:
          "Button that saves an unencrypted copy of a GIF from an encrypted room to My GIFs",
      name: "myGifsPromptSaveCopy");

  static String get saveFailed => Intl.message("Couldn't save this GIF",
      desc: "Shown when saving a GIF to My GIFs failed",
      name: "myGifsSaveFailed");

  /// Vommet issue 750: ask before saving a GIF from an encrypted room, which
  /// makes an unencrypted copy (account data isn't encrypted, so its key
  /// can't be kept there). Off once "Don't ask again" was ticked.
  static final BoolPreference askBeforeUnencryptedCopy =
      BoolPreference("vommet_my_gifs_ask_unencrypted_copy", defaultValue: true);

  /// Whether the user agreed to save an unencrypted copy.
  static Future<bool> confirmUnencryptedCopy(BuildContext context) async {
    if (!askBeforeUnencryptedCopy.value) return true;
    var dontAsk = false;
    final save = await AdaptiveDialog.confirmation(context,
        title: copyTitle,
        prompt: copyBody,
        confirmationText: promptSaveCopy,
        cancelText: CommonStrings.promptCancel,
        customBuilder: (context) => StatefulBuilder(
              builder: (context, setState) => CheckboxListTile(
                value: dontAsk,
                title: Text(copyDontAsk),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) => setState(() => dontAsk = value ?? false),
              ),
            ));
    if (save != true) return false;
    if (dontAsk) await askBeforeUnencryptedCopy.set(false);
    return true;
  }

  /// "Add to My GIFs" / "Remove from My GIFs" for a GIF message.
  static TimelineEventMenuEntry menuEntry(
    GifComponent gifs,
    TimelineEvent event, {
    required bool saved,
    Function()? onActionFinished,
  }) {
    return TimelineEventMenuEntry(
      name: saved ? promptRemove : promptAdd,
      icon:
          saved ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined,
      action: (context) async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (!saved &&
            gifs.savesUnencryptedCopy(event) &&
            !await confirmUnencryptedCopy(context)) {
          onActionFinished?.call();
          return;
        }
        onActionFinished?.call();
        try {
          await setSaved(gifs, event, !saved);
        } catch (e) {
          Log.w("My GIFs: couldn't save the GIF: $e");
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(SnackBar(content: Text(saveFailed)));
          return;
        }
        messenger?.hideCurrentSnackBar();
        // Undoing a removal saves the GIF again; from an encrypted room that
        // makes an unencrypted copy, which only the question above may do.
        final canUndo = !saved ||
            !gifs.savesUnencryptedCopy(event) ||
            !askBeforeUnencryptedCopy.value;
        messenger?.showSnackBar(SnackBar(
          content: Text(saved ? removed : added),
          action: canUndo
              ? SnackBarAction(
                  label: promptUndo,
                  onPressed: () => setSaved(gifs, event, saved),
                )
              : null,
        ));
      },
    );
  }

  static Future<void> setSaved(
      GifComponent gifs, TimelineEvent event, bool save) {
    return save
        ? gifs.setFavoriteFromEvent(event)
        : gifs.removeFavoriteFromEvent(event);
  }

  // Vommet issue 731: folders.

  static String get promptSaveToFolder => Intl.message("Save to folder…",
      desc: "Message menu item that saves a GIF to a folder of My GIFs",
      name: "myGifsPromptSaveToFolder");

  static String get titlePickFolder => Intl.message("Choose a folder",
      desc: "Title of the list of My GIFs folders to save or move GIFs to",
      name: "myGifsTitlePickFolder");

  static String get unsorted => Intl.message("Unsorted",
      desc: "The My GIFs folder holding the GIFs that are in no folder",
      name: "myGifsUnsorted");

  static String get promptNewFolder => Intl.message("New folder",
      desc: "Button that creates a folder for My GIFs",
      name: "myGifsPromptNewFolder");

  static String get labelFolderName => Intl.message("Folder name",
      desc: "Hint of the name field when creating or renaming a GIF folder",
      name: "myGifsLabelFolderName");

  static String get promptRenameFolder => Intl.message("Rename folder",
      desc: "Title of the dialog renaming a My GIFs folder",
      name: "myGifsPromptRenameFolder");

  static String get promptCreate => Intl.message("Create",
      desc: "Confirms creating a GIF folder", name: "myGifsPromptCreate");

  static String myGifsSavedToFolder(String folder) =>
      Intl.message("Saved to $folder",
          desc: "Shown after a GIF was saved to a My GIFs folder",
          args: [folder],
          name: "myGifsSavedToFolder");

  /// Asks for a folder: Unsorted, each folder, or a new one. Null if
  /// cancelled; `(folder: null)` is Unsorted.
  static Future<({String? folder})?> pickFolder(
      BuildContext context, List<String> folders,
      {String? current, bool markCurrent = true}) async {
    final picked =
        await AdaptiveDialog.show<({String? folder, bool create})>(context,
            title: titlePickFolder,
            builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final f in <String?>[null, ...folders])
                      ListTile(
                        leading: Icon(f == null
                            ? Icons.inbox_outlined
                            : Icons.folder_outlined),
                        title: Text(f ?? unsorted),
                        trailing: markCurrent && f == current
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () =>
                            Navigator.pop(context, (folder: f, create: false)),
                      ),
                    ListTile(
                      leading: const Icon(Icons.create_new_folder_outlined),
                      title: Text(promptNewFolder),
                      onTap: () =>
                          Navigator.pop(context, (folder: null, create: true)),
                    ),
                  ],
                ));
    if (picked == null) return null;
    if (!picked.create) return (folder: picked.folder);
    if (!context.mounted) return null;
    final name = await askFolderName(context);
    return name == null ? null : (folder: name);
  }

  /// A new folder's name (or a renamed one's), trimmed; null if cancelled.
  static Future<String?> askFolderName(BuildContext context,
      {String? initial, String? submit}) async {
    final name = await AdaptiveDialog.textPrompt(context,
        title: initial == null ? promptNewFolder : promptRenameFolder,
        hintText: labelFolderName,
        initialText: initial,
        submitText: submit ?? promptCreate);
    return name == null ? null : GifFolders.cleanName(name);
  }

  /// "Save to folder…" for a GIF message.
  static TimelineEventMenuEntry folderMenuEntry(
    GifComponent gifs,
    TimelineEvent event, {
    Function()? onActionFinished,
  }) {
    return TimelineEventMenuEntry(
      name: promptSaveToFolder,
      icon: Icons.folder_outlined,
      action: (context) async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        onActionFinished?.call();
        final picked = await pickFolder(context, gifs.folders,
            current: gifs.folderOfEvent(event),
            markCurrent: gifs.isFavoriteGif(event));
        if (picked == null) return;
        await gifs.saveToFolder(event, picked.folder);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(
            content: Text(myGifsSavedToFolder(picked.folder ?? unsorted))));
      },
    );
  }
}
