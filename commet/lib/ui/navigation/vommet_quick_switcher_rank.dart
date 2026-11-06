import 'package:commet/ui/navigation/quick_switcher.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';

/// Vommet: Ctrl+K ranks with New Home's search ([rankByName]): a name (or
/// a DM's user id) starting with the text, then one with a word starting
/// with it, then one containing it, newest first within each; accents and
/// case don't matter. Replaces Commet's fuzzy match, which put loose
/// matches above exact ones.
List<QuickSwitcherSearchItem> rankQuickSwitcher(
        List<QuickSwitcherSearchItem> items, String text, {int limit = 5}) =>
    rankByName<QuickSwitcherSearchItem>(items, text,
        name: (item) => item.searchEntry,
        alias: (item) => item.id,
        last: (item) => item is QuickSwitcherSearchItemRoom
            ? item.room.lastEventTimestamp
            : null).take(limit).toList();
