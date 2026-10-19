// Vommet: the search field above the Home / Direct Messages list filters it
// by person (Vommet issue 362).
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/notifying_list_filter.dart';

/// The names a room can be found by: its shown name and, for a direct
/// message, the other person's Matrix ID, the name they set themselves and
/// the nickname you gave them (the shown name is the nickname when there is
/// one, so searching their own name must still find them).
List<String> dmSearchNames(Room room) {
  final names = <String>[room.displayName];

  final partner = room.client
      .getComponent<DirectMessagesComponent>()
      ?.getDirectMessagePartnerId(room);
  if (partner == null) return names;

  names.add(partner);
  final member = room.getMemberOrFallback(partner);
  names.add(member.displayName);
  if (member is MatrixMember) {
    names.add(member.matrixUser.calcDisplayname());
  }

  return names;
}

/// Whether [names] match [query]: every word of the query, ignoring case,
/// appears in one of them. An empty query matches everything.
bool dmSearchMatches(String query, Iterable<String?> names) {
  final words = query.toLowerCase().split(RegExp(r"\s+"))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return true;

  final haystack = [
    for (final name in names)
      if (name != null) name.toLowerCase()
  ];
  return words.every((w) => haystack.any((name) => name.contains(w)));
}

/// The favourites and direct messages lists as the search leaves them. While
/// the query is blank they are the lists themselves; otherwise filtered
/// copies, made anew on each change so rows keep their order once it clears.
class DmListSearch {
  DmListSearch(this.allFavorites, this.allDirectMessages);

  final INotifyingList<Room> allFavorites;
  final INotifyingList<Room> allDirectMessages;

  String query = "";
  NotifyingListFilter<Room>? _favorites;
  NotifyingListFilter<Room>? _directMessages;

  INotifyingList<Room> get favorites => _favorites ?? allFavorites;
  INotifyingList<Room> get directMessages =>
      _directMessages ?? allDirectMessages;

  /// Whether the Direct Messages section shows its hint: "none yet", or "no
  /// match" when the search matched nothing at all (a search that matched
  /// only favourites shows no hint).
  bool get showDirectMessagesHint =>
      directMessages.isEmpty && (query.isEmpty || favorites.isEmpty);

  void setQuery(String text) {
    _unsubscribe();
    query = text.trim();
    if (query.isEmpty) return;

    bool where(Room room) => dmSearchMatches(query, dmSearchNames(room));
    _favorites = NotifyingListFilter(allFavorites, where: where);
    _directMessages = NotifyingListFilter(allDirectMessages, where: where);
  }

  void dispose() => _unsubscribe();

  void _unsubscribe() {
    _favorites?.unsubscribe();
    _directMessages?.unsubscribe();
    _favorites = null;
    _directMessages = null;
  }
}
