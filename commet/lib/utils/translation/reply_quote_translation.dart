import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/foundation.dart';

/// The message a reply quotes, translated like the message itself in a room
/// with "Translate this room" on (Vommet issue 680 follow-up).
///
/// Uses the same key as [MessageTranslationFold] ("eventId\0text hash"), so
/// a quoted message already translated on screen shows that translation at
/// once; otherwise it's queued through [RoomTranslation.autoTranslate]. A
/// quote never asks to download models: when they're missing, the original
/// stays. [translated] goes back to null as soon as the room mode is off.
class ReplyQuoteTranslation extends ChangeNotifier {
  ReplyQuoteTranslation(
      {MessageTranslation? translation, RoomTranslation? rooms})
      : translation = translation ?? MessageTranslation.instance,
        rooms = rooms ?? RoomTranslation.instance {
    this.rooms.addListener(_update);
    this.translation.modelsChanged.addListener(_update);
  }

  final MessageTranslation translation;
  final RoomTranslation rooms;

  String? _roomId;
  String? _key;
  String? _text;
  ValueNotifier<TranslationState>? _state;
  bool _queued = false;
  bool _disposed = false;

  /// [MessageTranslationFold]'s key for a message: edits change the text, so
  /// the key covers it too.
  static String keyFor(String eventId, String text) =>
      "$eventId\u0000${text.hashCode}";

  /// Follows the quoted message [eventId] with [text], in [roomId].
  void show(
      {required String roomId, required String eventId, required String text}) {
    final key = keyFor(eventId, text);
    if (key == _key && roomId == _roomId) return;
    _detach();
    _roomId = roomId;
    _key = key;
    _text = text;
    _queued = false;
    if (translation.supported && text.trim().isNotEmpty) {
      _state = translation.stateFor(key)..addListener(_onState);
    }
    _update();
  }

  /// Nothing to translate (own message, media, code, no room).
  void clear() {
    if (_key == null) return;
    _detach();
    _roomId = _key = _text = null;
    notifyListeners();
  }

  /// The language the quoted message is in, when it can be translated into
  /// yours.
  String? get _from => _key == null || _state == null
      ? null
      : translation.translatableLanguage(_key!, _text!);

  /// The translation to show instead of the quoted text, or null for the
  /// original.
  String? get translated {
    final roomId = _roomId;
    if (roomId == null || _from == null || !rooms.isOn(roomId)) return null;
    final value = _state?.value;
    return value is TranslationDone ? value.text : null;
  }

  void _detach() {
    _state?.removeListener(_onState);
    _state = null;
  }

  void _onState() {
    // Reset (the target language changed): translate again.
    if (_state?.value is TranslationIdle) _queued = false;
    _update();
  }

  void _update() {
    if (_disposed) return;
    _queue();
    notifyListeners();
  }

  Future<void> _queue() async {
    final roomId = _roomId, key = _key, text = _text, from = _from;
    if (_queued || roomId == null || key == null || from == null) return;
    if (!rooms.isOn(roomId) || _state?.value is! TranslationIdle) return;
    final route = translation.route(from, translation.targetLanguage);
    if (route == null) return;
    _queued = true;
    // Only the message itself asks to download; a quote waits for that.
    if ((await translation.missingModels(route)).isNotEmpty) {
      if (_key == key) _queued = false;
      return;
    }
    if (_disposed || _key != key) return;
    await rooms.autoTranslate(roomId, key, text!, from,
        wanted: () => !_disposed && _key == key,
        confirm: (_, __, ___) async => null);
  }

  @override
  void dispose() {
    _disposed = true;
    _detach();
    rooms.removeListener(_update);
    translation.modelsChanged.removeListener(_update);
    super.dispose();
  }
}
