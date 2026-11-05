// Vommet issue 1070: main-room text/reply revisions. No attachment/edit state.
import 'dart:convert';

class DraftRevision {
  static const maxWriters = 16;
  static const maxTextBytes = 16 * 1024;
  static const maxRecordBytes = 32 * 1024;
  static const maxRevision = 9007199254740991;

  DraftRevision({
    required this.account,
    required this.room,
    required this.writer,
    required this.revision,
    required Map<String, int> observed,
    required this.text,
    this.replyTo,
    this.cleared = false,
  }) : observed = Map.unmodifiable(observed) {
    if (!account.contains('\u0000@') ||
        account.length > 2048 ||
        !room.startsWith('!') ||
        room.length > 1024 ||
        writer.isEmpty ||
        writer.length > 255 ||
        revision < 1 ||
        revision > maxRevision ||
        observed.length > maxWriters ||
        observed.entries.any(
          (e) =>
              e.key.isEmpty ||
              e.key.length > 255 ||
              e.value < 1 ||
              e.value > maxRevision,
        ) ||
        (observed[writer] ?? 0) >= revision ||
        utf8.encode(text).length > maxTextBytes ||
        (replyTo != null &&
            (!replyTo!.startsWith(r'$') || replyTo!.length > 1024)) ||
        (cleared && (text.isNotEmpty || replyTo != null))) {
      throw const FormatException('Invalid draft revision');
    }
  }

  final String account, room, writer, text;
  final String? replyTo;
  final int revision;
  final Map<String, int> observed;
  final bool cleared;

  Map<String, int> get frontier => {...observed, writer: revision};

  Map<String, Object?> toJson() => {
        'version': 1,
        'account': account,
        'room': room,
        'context': 'main',
        'writer': writer,
        'revision': revision,
        'observed': observed,
        'text': text,
        'reply_to': replyTo,
        'cleared': cleared,
      };

  factory DraftRevision.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['context'] != 'main') {
      throw const FormatException('Unsupported draft schema');
    }
    return DraftRevision(
      account: json['account'] as String,
      room: json['room'] as String,
      writer: json['writer'] as String,
      revision: json['revision'] as int,
      observed: (json['observed'] as Map).cast<String, int>(),
      text: json['text'] as String,
      replyTo: json['reply_to'] as String?,
      cleared: json['cleared'] as bool,
    );
  }
}

/// A composer holds this immutable view until it explicitly accepts another.
/// A newly arrived version is never implicitly included in a clear/selection.
class DraftView {
  DraftView(this.account, this.room, Iterable<DraftRevision> records)
      : records = List.unmodifiable(records) {
    if (this.records.length > DraftRevision.maxWriters ||
        this.records.any((r) => r.account != account || r.room != room) ||
        this.records.map((r) => r.writer).toSet().length !=
            this.records.length) {
      throw const FormatException('Invalid draft view');
    }
  }
  final String account, room;
  final List<DraftRevision> records;

  Map<String, int> get frontier {
    final result = <String, int>{};
    for (final record in records) {
      for (final e in record.frontier.entries) {
        if (e.value > (result[e.key] ?? 0)) result[e.key] = e.value;
      }
    }
    return result;
  }

  List<DraftRevision> get heads => records
      .where(
        (r) => !records.any(
          (other) =>
              other != r && (other.observed[r.writer] ?? 0) >= r.revision,
        ),
      )
      .toList(growable: false);

  List<DraftRevision> get drafts =>
      heads.where((r) => !r.cleared).toList(growable: false);

  // A concurrent deletion is also a conflict, even if just one text remains.
  bool get hasConflict => heads.length > 1;
}
