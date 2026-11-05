// Vommet issue 814: the New Home Notifications card's data, apart from the
// SDK and the widgets so it can be unit tested. The card lists the
// notifications of the last [notificationsWindow]: unread first, then the
// read ones under "Earlier" (left out with the card's "Hide read").

/// How far back the card looks.
const Duration notificationsWindow = Duration(days: 7);

/// One notification: an event the user's push rules notified for.
class NotificationEntry {
  const NotificationEntry(
      {required this.clientId,
      required this.roomId,
      required this.eventId,
      required this.senderId,
      required this.time,
      required this.read,
      this.highlight = false,
      this.threadId,
      this.preview = "",
      this.count = 1});

  final String clientId;
  final String roomId;
  final String eventId;
  final String senderId;
  final DateTime time;
  final bool read;

  /// A mention or keyword (the push rule's highlight tweak).
  final bool highlight;

  /// The thread the event is in, if any, so opening it lands there.
  final String? threadId;

  /// The notifying message as the card shows it ([notificationPreview]).
  final String preview;

  /// How many unread notifications this entry stands for (a DM or a room
  /// set to every message gets one entry).
  final int count;

  /// The room, across accounts.
  String get roomKey => "$clientId/$roomId";

  NotificationEntry copyWith({bool? read, int? count}) => NotificationEntry(
      clientId: clientId,
      roomId: roomId,
      eventId: eventId,
      senderId: senderId,
      time: time,
      read: read ?? this.read,
      highlight: highlight,
      threadId: threadId,
      preview: preview,
      count: count ?? this.count);
}

/// The card's rows: [unread] newest first, then [earlier] (the read ones).
class NotificationsList {
  const NotificationsList(this.unread, this.earlier);
  static const NotificationsList empty = NotificationsList([], []);

  final List<NotificationEntry> unread;
  final List<NotificationEntry> earlier;

  bool get isEmpty => unread.isEmpty && earlier.isEmpty;
  int get length => unread.length + earlier.length;
}

/// Arranges [entries] for the card: one per event (an unread copy wins over
/// a read one), only the last [notificationsWindow] before [now], newest
/// first, unread above read. A room that [oneEntry] (DMs, rooms set to every
/// message) keeps only its newest entry; it counts the room's unread ones
/// and is unread while any of them is. [hideRead] leaves the read ones out.
NotificationsList arrangeNotifications(Iterable<NotificationEntry> entries,
    {required DateTime now,
    required bool Function(String roomKey) oneEntry,
    bool hideRead = false}) {
  final since = now.subtract(notificationsWindow);
  final byEvent = <String, NotificationEntry>{};
  for (final e in entries) {
    if (e.time.isBefore(since)) continue;
    final key = "${e.roomKey}/${e.eventId}";
    final had = byEvent[key];
    if (had == null || (had.read && !e.read)) byEvent[key] = e;
  }
  final sorted = byEvent.values.toList()
    ..sort((a, b) => b.time.compareTo(a.time));

  final kept = <NotificationEntry>[];
  final single = <String, int>{};
  for (final e in sorted) {
    if (!oneEntry(e.roomKey)) {
      kept.add(e);
      continue;
    }
    final at = single[e.roomKey];
    if (at == null) {
      single[e.roomKey] = kept.length;
      kept.add(e.copyWith(count: e.read ? 1 : e.count));
      continue;
    }
    if (e.read) continue;
    final first = kept[at];
    kept[at] = first.read
        ? first.copyWith(read: false, count: e.count)
        : first.copyWith(count: first.count + e.count);
  }

  return NotificationsList(
      [
        for (final e in kept)
          if (!e.read) e
      ],
      hideRead
          ? const []
          : [
              for (final e in kept)
                if (e.read) e
            ]);
}

/// The notifying message as the card shows it: the text (line breaks kept,
/// at most two lines show), or "📷 Photo", "🎬 Video", "🎤 Voice message",
/// "🎵 <name>" and "📎 <file name>" for media. Spoilered media and stickers
/// never show their names. Null when [type] isn't something to preview.
String? notificationPreview(String type, Map<String, dynamic> content,
    {bool spoiler = false}) {
  if (type == "m.sticker") return "Sticker";
  if (type == "m.room.encrypted") return "🔒 Encrypted message";
  if (type == "m.call.invite" || type == "org.matrix.msc3401.call") {
    return "📞 Call";
  }
  if (type == "org.matrix.msc3381.poll.start" || type == "m.poll.start") {
    return "📊 Poll";
  }
  if (type != "m.room.message") return null;

  // An edit notifies with its new text.
  final newContent = content["m.new_content"];
  final c = newContent is Map<String, dynamic> ? newContent : content;
  final body = c["body"] is String ? (c["body"] as String).trim() : "";
  final fileName = c["filename"] is String ? c["filename"] as String : body;
  // A caption is a body that differs from the file name.
  final caption = c["filename"] is String && body != c["filename"] ? body : "";
  String media(String label) =>
      caption.isEmpty || spoiler ? label : "$label · $caption";

  switch (c["msgtype"]) {
    case "m.image":
      return media(spoiler ? "📷 Photo (spoiler)" : "📷 Photo");
    case "m.video":
      return media(spoiler ? "🎬 Video (spoiler)" : "🎬 Video");
    case "m.audio":
      final voice = c["org.matrix.msc3245.voice"] != null ||
          c["org.matrix.msc2516.voice"] != null;
      if (voice) return "🎤 Voice message";
      return fileName.isEmpty ? "🎵 Audio" : "🎵 $fileName";
    case "m.file":
      if (spoiler) return "📎 File (spoiler)";
      return fileName.isEmpty ? "📎 File" : "📎 $fileName";
    case "m.location":
      return "📍 Location";
    case "m.emote":
      return "* $body";
  }
  return _withoutReplyFallback(body);
}

/// Drops the "> <@user> quoted text" lines older clients put in front of a
/// reply's body.
String _withoutReplyFallback(String body) {
  if (!body.startsWith("> ")) return body;
  final lines = body.split("\n");
  var i = 0;
  while (i < lines.length && lines[i].startsWith(">")) {
    i++;
  }
  return lines.skip(i).join("\n").trim();
}

/// [text] cut into runs, `true` for the parts that match one of [terms]
/// (your name, your user id, your keywords), case-insensitively. Overlapping
/// matches merge.
List<(String, bool)> highlightRuns(String text, Iterable<String> terms) {
  final lower = text.toLowerCase();
  final marked = List<bool>.filled(text.length, false);
  for (final term in terms) {
    final t = term.trim().toLowerCase();
    if (t.length < 2) continue;
    var at = lower.indexOf(t);
    while (at >= 0) {
      for (var i = at; i < at + t.length && i < marked.length; i++) {
        marked[i] = true;
      }
      at = lower.indexOf(t, at + t.length);
    }
  }
  final runs = <(String, bool)>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || marked[i] != marked[start]) {
      runs.add((text.substring(start, i), marked[start]));
      start = i;
    }
  }
  return runs;
}

/// The plain words of the user's keyword rules (content rules without glob
/// characters), for [highlightRuns].
List<String> keywordTerms(Iterable<String?> patterns) => [
      for (final p in patterns)
        if (p != null && p.isNotEmpty && !p.contains(RegExp(r"[*?\[\]]"))) p
    ];
