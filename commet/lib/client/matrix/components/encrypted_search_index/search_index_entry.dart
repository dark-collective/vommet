// Vommet (issues 602, 611): what the encrypted search index keeps of one
// decrypted event. Plain Dart on event JSON, so it runs in the index's
// isolate and in unit tests.
import 'package:commet/utils/mime.dart';

/// What a message shares, for the Shared counts and the Media/Files/Links
/// tabs. [image] excludes GIFs; [audio] is an audio file that isn't a voice
/// message (MSC3245).
enum SharedContentKind { text, image, video, gif, file, voice, audio, sticker }

/// One indexed message. [searchText] is lowercased (body, file name and the
/// latest edit's body); [json] is the decrypted event, so results show
/// without the network.
class IndexedEvent {
  const IndexedEvent({
    required this.eventId,
    required this.senderId,
    required this.ts,
    required this.type,
    required this.kind,
    required this.searchText,
    required this.json,
    this.msgtype,
    this.mimetype,
    this.links = const [],
  });

  final String eventId;
  final String senderId;
  final int ts;
  final String type;
  final String? msgtype;
  final String? mimetype;
  final SharedContentKind kind;
  final String searchText;
  final List<String> links;
  final Map<String, dynamic> json;
}

/// An edit (`m.replace`) of an indexed message.
class IndexedEdit {
  const IndexedEdit(
      {required this.targetId, required this.ts, required this.searchText});
  final String targetId;
  final int ts;
  final String searchText;
}

/// What [IndexExtract.of] makes of an event.
sealed class IndexExtract {
  const IndexExtract();

  static final _url = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  /// URLs in [text], without trailing punctuation.
  static List<String> linksIn(String text) => [
        for (final m in _url.allMatches(text))
          m.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]}>]+$'), ""),
      ];

  /// Reads one event as returned by /messages or sync, after decryption.
  /// Null for anything the index ignores (state, reactions, receipts,
  /// redacted or still encrypted events).
  static IndexExtract? of(Map<String, dynamic> event) {
    final type = event["type"];
    final eventId = event["event_id"];
    final sender = event["sender"];
    final ts = event["origin_server_ts"];
    if (type is! String || eventId is! String || sender is! String) {
      return null;
    }
    if (ts is! int) return null;
    if (event.containsKey("state_key")) return null;

    if (type == "m.room.redaction") {
      final target = event["redacts"] ??
          (event["content"] is Map ? event["content"]["redacts"] : null);
      return target is String ? IndexRedaction(target) : null;
    }
    if (type != "m.room.message" && type != "m.sticker") return null;

    final content = event["content"];
    if (content is! Map || content.isEmpty) return null;
    final relates = content["m.relates_to"];
    if (relates is Map && relates["rel_type"] == "m.replace") {
      final target = relates["event_id"];
      final newContent = content["m.new_content"];
      if (target is! String || newContent is! Map) return null;
      return IndexEditExtract(IndexedEdit(
          targetId: target, ts: ts, searchText: _searchText(newContent)));
    }

    final msgtype = content["msgtype"] is String ? content["msgtype"] : null;
    final info = content["info"] is Map ? content["info"] as Map : const {};
    final mimetype = info["mimetype"] is String ? info["mimetype"] : null;
    final body = content["body"] is String ? content["body"] as String : "";

    return IndexEventExtract(IndexedEvent(
      eventId: eventId,
      senderId: sender,
      ts: ts,
      type: type,
      msgtype: msgtype,
      mimetype: mimetype,
      kind: kindOf(type: type, content: content),
      searchText: _searchText(content),
      links:
          msgtype == "m.text" || msgtype == "m.notice" || msgtype == "m.emote"
              ? linksIn(body)
              : const [],
      json: _slim(event),
    ));
  }

  /// The kind of a message, from its msgtype and the attachment's mimetype
  /// (a picture sent as `m.file` still counts as a photo, like the timeline
  /// shows it).
  static SharedContentKind kindOf(
      {required String type, required Map content}) {
    if (type == "m.sticker") return SharedContentKind.sticker;
    final msgtype = content["msgtype"];
    final info = content["info"] is Map ? content["info"] as Map : const {};
    final mimetype = info["mimetype"] is String ? info["mimetype"] : null;
    final hasFile = content["url"] is String || content["file"] is Map;
    if (!hasFile) return SharedContentKind.text;
    if (mimetype == "image/gif") return SharedContentKind.gif;
    if (msgtype == "m.image" || Mime.imageTypes.contains(mimetype)) {
      return SharedContentKind.image;
    }
    if (msgtype == "m.video" || Mime.videoTypes.contains(mimetype)) {
      return SharedContentKind.video;
    }
    if (msgtype == "m.audio") {
      final voice = content.containsKey("org.matrix.msc3245.voice") ||
          content.containsKey("m.voice");
      return voice ? SharedContentKind.voice : SharedContentKind.audio;
    }
    return SharedContentKind.file;
  }

  static String _searchText(Map content) {
    final parts = <String>[
      if (content["body"] is String) content["body"] as String,
      if (content["filename"] is String &&
          content["filename"] != content["body"])
        content["filename"] as String,
    ];
    return parts.join("\n").toLowerCase();
  }

  /// The event without what results never need (unsigned's relations and
  /// the encrypted original), to keep rows small.
  static Map<String, dynamic> _slim(Map<String, dynamic> event) {
    final copy = Map<String, dynamic>.from(event);
    final unsigned = copy["unsigned"];
    if (unsigned is Map) {
      copy["unsigned"] = {
        for (final e in unsigned.entries)
          if (e.key != "m.relations" && e.key != "prev_content")
            e.key as String: e.value,
      };
    }
    return copy;
  }
}

class IndexEventExtract extends IndexExtract {
  const IndexEventExtract(this.event);
  final IndexedEvent event;
}

class IndexEditExtract extends IndexExtract {
  const IndexEditExtract(this.edit);
  final IndexedEdit edit;
}

class IndexRedaction extends IndexExtract {
  const IndexRedaction(this.targetId);
  final String targetId;
}
