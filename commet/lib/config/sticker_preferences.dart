import 'package:commet/config/preferences/bool_preference.dart';

/// Vommet: sticker/emoji pack settings, kept out of upstream's
/// preferences.dart so other topics' edits there never conflict.
class StickerPreferences {
  /// Settings › Account › Emoticons › Advanced: "Use a personal pack". Off
  /// by default: new packs then always go to sticker rooms, and the import
  /// destinations never offer the account's one personal pack
  /// (`im.ponies.user_emotes`). An existing personal pack is shown either
  /// way.
  static final BoolPreference usePersonalPack =
      BoolPreference("vommet_use_personal_pack", defaultValue: false);
}
