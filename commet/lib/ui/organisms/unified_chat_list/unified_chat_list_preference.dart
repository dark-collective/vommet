// Vommet: the switch for the Telegram-style unified chat list (Vommet issue
// 291). Kept beside the feature, not in preferences.dart, so this topic
// doesn't touch a file most topics edit.
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/utils/event_bus.dart';

final BoolPreference experimentUnifiedChatList =
    BoolPreference("experiment_unified_chat_list", defaultValue: false);

/// Whether the main page shows the unified chat list instead of the space
/// rail and Home.
bool get unifiedChatListEnabled => experimentUnifiedChatList.value;

/// Rebuilds the main page in the other layout straight away: opening Home
/// clears the selection, and the main page's setState picks the layout.
void onUnifiedChatListToggled(bool _) => EventBus.openHomeScreen.add(null);
