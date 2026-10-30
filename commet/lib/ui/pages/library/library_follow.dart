// Vommet issue 731, phase 2: following a collection (a sticker room) from a
// sticker in chat or a pasted link: a confirm that says what following
// reveals, then join and turn on all its packs.
import 'package:commet/client/matrix/components/emoticon/library_store.dart';
import 'package:commet/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/library_sharing.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class LibraryFollow {
  static String get promptFollowPack => Intl.message("Follow pack",
      desc:
          "Button on a sticker's pack sheet: join the pack's room to get its packs and later changes",
      name: "libraryPromptFollowPack");

  static String get promptFollowAPack => Intl.message("Follow a pack…",
      desc: "Library sidebar item: follow a collection from a link",
      name: "libraryPromptFollowAPack");

  static String get promptFollow => Intl.message("Follow",
      desc: "Confirms following a collection of packs",
      name: "libraryPromptFollow");

  static String get titleFollow => Intl.message("Follow this collection?",
      desc: "Title of the confirm before following a collection of packs",
      name: "libraryTitleFollow");

  static String libraryFollowNotice(String room) => Intl.message(
      "Following joins $room. Its members and its server can see that you follow it.",
      args: [room],
      name: "libraryFollowNotice",
      desc:
          "Confirm before following a collection: what joining its room reveals");

  static String get labelFollowLink =>
      Intl.message("Link, #alias:server or !room id",
          desc: "Hint of the field taking a link to a collection to follow",
          name: "libraryLabelFollowLink");

  static String get errorBadLink => Intl.message(
      "That isn't a link to a room. Paste a matrix.to link, a #alias:server or a !room id.",
      desc: "Error when the pasted text to follow is not a room link",
      name: "libraryErrorBadLink");

  static String get errorForbidden => Intl.message(
      "You can't join this collection. It may be private: ask its owner for an invite.",
      desc: "Error when following a collection is refused",
      name: "libraryErrorFollowForbidden");

  static String get errorNotFound => Intl.message(
      "This collection wasn't found. It may have been deleted, or its server is unreachable.",
      desc: "Error when the collection to follow can't be found",
      name: "libraryErrorFollowNotFound");

  static String get errorNotPackRoom => Intl.message(
      "That room isn't a sticker room, so there's nothing to follow.",
      desc: "Error when the room to follow holds no packs",
      name: "libraryErrorNotPackRoom");

  static String get errorFollowFailed =>
      Intl.message("Following didn't work. Try again later.",
          desc: "Error when following a collection fails for another reason",
          name: "libraryErrorFollowFailed");

  static String libraryFollowing(String room) =>
      Intl.message("Following $room. Its packs are on in your picker.",
          args: [room],
          name: "libraryFollowing",
          desc: "Shown after following a collection");

  /// Asks for a link and follows it.
  static Future<matrix.Room?> followFromLink(
      BuildContext context, matrix.Client mx) async {
    final text = await AdaptiveDialog.textPrompt(context,
        title: promptFollowAPack,
        hintText: labelFollowLink,
        submitText: promptFollow);
    if (text == null || text.trim().isEmpty || !context.mounted) return null;
    final link = LibrarySharing.parseLink(text);
    if (link == null) {
      await _error(context, errorBadLink);
      return null;
    }
    return follow(context, mx, link);
  }

  /// Confirms, joins the collection [link] names and turns on its packs.
  static Future<matrix.Room?> follow(
      BuildContext context, matrix.Client mx, PackRoomLink link) async {
    final name = await _nameOf(mx, link);
    if (!context.mounted) return null;
    final yes = await AdaptiveDialog.confirmation(context,
        title: titleFollow,
        prompt: libraryFollowNotice(name),
        confirmationText: promptFollow,
        cancelText: CommonStrings.promptCancel);
    if (yes != true || !context.mounted) return null;

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final room = await LibraryStore(mx).follow(link);
      messenger?.showSnackBar(SnackBar(
          content: Text(libraryFollowing(room.getLocalizedDisplayname()))));
      return room;
    } catch (e) {
      Log.w("Library: following ${link.idOrAlias} failed: $e");
      if (context.mounted) await _error(context, _message(e));
      return null;
    }
  }

  static String _message(Object e) {
    if (e is NotAPackRoomException) return errorNotPackRoom;
    if (e is matrix.MatrixException) {
      return switch (e.error) {
        matrix.MatrixError.M_FORBIDDEN => errorForbidden,
        matrix.MatrixError.M_NOT_FOUND => errorNotFound,
        _ => errorFollowFailed,
      };
    }
    return errorFollowFailed;
  }

  /// The room's name from its summary when the server can tell, else the
  /// alias or id.
  static Future<String> _nameOf(matrix.Client mx, PackRoomLink link) async {
    try {
      final preview = await mx
          .getRoomPreview(link.idOrAlias, via: link.via)
          .timeout(const Duration(seconds: 5));
      final name = preview?.displayName;
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {
      // No summary: fall back to the id.
    }
    return link.idOrAlias;
  }

  static Future<void> _error(BuildContext context, String text) =>
      AdaptiveDialog.show(context,
          title: errorTitle,
          builder: (context) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text(text),
              ));

  static String get errorTitle => Intl.message("Couldn't follow",
      desc: "Title of the error shown when following a collection fails",
      name: "libraryErrorFollowTitle");
}
