// Vommet: whether new rooms start with encryption switched on (Vommet issue
// 524). The create-room form's switch starts from this; it can still be
// changed per room there. Kept beside the feature, not in preferences.dart.
// Off for new installs (operator 10-22: "Only when I turn it on" is the
// default); installs that already had an account keep it on, see
// Preferences.keepOldDefaultsForExistingInstalls.
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:intl/intl.dart';

final BoolPreference encryptNewRoomsByDefault =
    BoolPreference("vommet_encrypt_new_rooms", defaultValue: false);

String get encryptNewRoomsTitle => Intl.message("Encrypt new rooms",
    name: "encryptNewRoomsTitle",
    desc:
        "Setting: whether the encryption switch starts on when making a room");

String get encryptNewRoomsDescription => Intl.message(
    "The encryption switch starts on when you make a room. You can still change it for each room before making it.",
    name: "encryptNewRoomsDescription",
    desc: "Describes the 'Encrypt new rooms' setting");

String get encryptionSettingsHeader => Intl.message("Encryption",
    name: "encryptionSettingsHeader",
    desc: "Header of the encryption section in Settings › Privacy");
