import 'package:commet/config/preferences/bool_preference.dart';

/// Vommet experiment (opt-out): tapping a room's title opens a Room info
/// page for everyone (header, quick actions, shared content, members, then
/// "Just for you" and "Room settings"), and direct chats follow who is in
/// them right now. Off = the old Room settings screen and title behavior.
final BoolPreference experimentRoomInfoPage =
    BoolPreference("vommet_experiment_room_info_page", defaultValue: false);

bool get roomInfoPageEnabled => experimentRoomInfoPage.value;
