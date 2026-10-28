// Vommet (New Home cards, round 4): the Live calls card's rooms. Pure Dart,
// so it can be unit tested: which rooms have a call going on that the card
// shows with its settings, in what order, and the lines its rows show.
// Drawn by new_home_live_calls.dart.

import 'package:commet/ui/organisms/new_home/new_home_layout.dart';

/// A room with a call going on.
class LiveCall<R> {
  const LiveCall(this.room, this.participants, {this.startedAt});
  final R room;

  /// Who's in the call (user ids), each once.
  final List<String> participants;

  /// When the oldest membership in the call began, if known.
  final DateTime? startedAt;
}

/// The rooms of [rooms] with a call going on that a Live calls [card]
/// shows: in all your rooms, your favorites or one space
/// ([HomeCard.callsIn]); rooms you muted or marked low priority only with
/// [HomeCard.includeMuted]; direct messages only with [HomeCard.dms]. The
/// biggest calls first, then the longest running.
List<LiveCall<R>> liveCallsOf<R>(
  Iterable<R> rooms,
  HomeCard card, {
  required List<String> Function(R room) participants,
  required DateTime? Function(R room) startedAt,
  required bool Function(R room) isDirectMessage,
  required bool Function(R room) isMuted,
  required bool Function(R room) isLowPriority,
  required bool Function(R room) isFavourite,
  required bool Function(R room) inSpace,
}) {
  final calls = <LiveCall<R>>[];
  for (final room in rooms) {
    final people = participants(room);
    if (people.isEmpty) continue;
    switch (card.callsIn) {
      case HomeCard.callsInFavourites:
        if (!isFavourite(room)) continue;
      case HomeCard.callsInSpace:
        if (!inSpace(room)) continue;
    }
    if (!card.includeMuted && (isMuted(room) || isLowPriority(room))) {
      continue;
    }
    if (!card.dms && isDirectMessage(room)) continue;
    calls.add(LiveCall(room, people, startedAt: startedAt(room)));
  }
  final indexed = [for (var i = 0; i < calls.length; i++) (i, calls[i])];
  indexed.sort((a, b) {
    final bySize = b.$2.participants.length.compareTo(a.$2.participants.length);
    if (bySize != 0) return bySize;
    final sa = a.$2.startedAt, sb = b.$2.startedAt;
    if (sa != null && sb != null && sa != sb) return sa.compareTo(sb);
    if (sa != null && sb == null) return -1;
    if (sa == null && sb != null) return 1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Who's in a call: "Juni", "Juni and Pell", "Juni, Pell and Hazel",
/// "Juni, Pell, Hazel and 2 more".
String callPeopleLine(List<String> names) {
  if (names.isEmpty) return "";
  if (names.length == 1) return names.single;
  if (names.length <= 3) {
    return "${names.take(names.length - 1).join(", ")} and ${names.last}";
  }
  return "${names.take(3).join(", ")} and ${names.length - 3} more";
}

/// How long a call has run: "just started", "6 min", "1 h", "1 h 12 min".
String callDurationLine(Duration d) {
  if (d.inMinutes < 1) return "just started";
  if (d.inMinutes < 60) return "${d.inMinutes} min";
  final minutes = d.inMinutes % 60;
  return minutes == 0 ? "${d.inHours} h" : "${d.inHours} h $minutes min";
}

/// The Live calls card's line in the customize lists.
String liveCallsSummary(HomeCard card) => [
      switch (card.callsIn) {
        HomeCard.callsInFavourites => "Favorites",
        HomeCard.callsInSpace => "One space",
        _ => "All my rooms",
      },
      if (card.includeMuted) "muted included",
      if (!card.dms) "no DMs",
      if (card.railDot) "green dot on Home",
    ].join(" · ");
