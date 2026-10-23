// Vommet: "My GIFs", the GIFs you saved from chats. Saving uses upstream's
// favourite GIFs (kept in your account data, so every device has them); this
// adds saving from any message's menu and the strings around it.
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
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
        onActionFinished?.call();
        await setSaved(gifs, event, !saved);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(
          content: Text(saved ? removed : added),
          action: SnackBarAction(
            label: promptUndo,
            onPressed: () => setSaved(gifs, event, saved),
          ),
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
}
