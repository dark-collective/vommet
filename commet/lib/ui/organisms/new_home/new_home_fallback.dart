// Vommet (New Home): when something needs People or the Rooms browser (the
// rail's buttons, Add contact on a profile, Browse rooms) and no Home tab
// holds that page any more, it opens on its own page, with an offer to put
// it back on a tab: "Add it to a tab" / "Not now" (Vommet issue 607).
import 'dart:async';

import 'package:commet/client/client_manager.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';

/// Opens whole page [type] on its own page. [onAdded] runs after it was
/// added to a tab (and the page closed), to open Home on that tab.
void showBlockFallback(ClientManager manager, String type,
    {VoidCallback? onAdded}) {
  navigator.currentState?.push(MaterialPageRoute(
      builder: (_) => NewHomeBlockFallbackPage(
          clientManager: manager, type: type, onAdded: onAdded)));
}

/// The tab a block goes on: an existing tab, or a new one ("People" or
/// "Rooms": the removed default tab that held it when there is one).
/// Returns the tabs with the block added and the tab's id.
(HomeTabs, String) addBlockToTab(HomeTabs tabs, String type, {String? tabId}) {
  final tab = tabId == null ? null : tabs.tab(tabId);
  if (tab != null) {
    final main = tab.main.canAdd(type) ? tab.main.add(type) : tab.main;
    return (tabs.replaceTab(tab.copyWith(main: main)), tab.id);
  }
  final restore = tabs.removedDefaults
      .where((id) => HomeTabs.defaultTab(id)!.holds(type))
      .firstOrNull;
  if (restore != null) {
    final restored = HomeTabs.defaultTab(restore)!;
    return tabs.createTab(
        name: restored.name, icon: restored.icon, restore: restore);
  }
  final (created, id) = tabs.createTab(
      name: CardInfo.of(type).label,
      icon: type == HomeLayout.peoplePage ? "people" : "tag");
  return addBlockToTab(created, type, tabId: id);
}

class NewHomeBlockFallbackPage extends StatefulWidget {
  const NewHomeBlockFallbackPage(
      {super.key,
      required this.clientManager,
      required this.type,
      this.onAdded});

  final ClientManager clientManager;

  /// [HomeLayout.peoplePage] or [HomeLayout.roomsPage].
  final String type;
  final VoidCallback? onAdded;

  @override
  State<NewHomeBlockFallbackPage> createState() =>
      _NewHomeBlockFallbackPageState();
}

class _NewHomeBlockFallbackPageState extends State<NewHomeBlockFallbackPage> {
  bool offer = true;
  late final List<StreamSubscription> subs;

  @override
  void initState() {
    super.initState();
    // Opening a room or a space from the page goes to the main page.
    subs = [
      EventBus.openRoom.stream.listen((_) => close()),
      EventBus.openSpace.stream.listen((_) => close()),
    ];
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    super.dispose();
  }

  void close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> addToTab() async {
    final store = HomeLayoutStore.instance;
    final tabs = store.tabs.value.tabs;
    // "" = a new tab.
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text("Add ${CardInfo.of(widget.type).label} to a tab"),
        children: [
          for (final tab in tabs)
            SimpleDialogOption(
              key: ValueKey("NewHomeFallbackTab-${tab.id}"),
              onPressed: () => Navigator.of(context).pop(tab.id),
              child: Row(spacing: 12, children: [
                Icon(homeTabIcon(tab.icon), size: 20),
                Expanded(child: Text(tab.name)),
              ]),
            ),
          SimpleDialogOption(
            key: const ValueKey("NewHomeFallbackNewTab"),
            onPressed: () => Navigator.of(context).pop(""),
            child: const Row(spacing: 12, children: [
              Icon(Icons.add_rounded, size: 20),
              Expanded(child: Text("A new tab")),
            ]),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final (next, id) = addBlockToTab(store.tabs.value, widget.type,
        tabId: picked.isEmpty ? null : picked);
    await store.saveTabs(next);
    newHomeTab.value = id;
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onAdded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = CardInfo.of(widget.type).label;
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: SafeArea(
        top: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (offer)
            Container(
              key: const ValueKey("NewHomeFallbackOffer"),
              color: scheme.surfaceContainerHigh,
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text("$label isn't on any of your Home tabs.",
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                    Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                      TextButton(
                        key: const ValueKey("NewHomeFallbackNotNow"),
                        onPressed: () => setState(() => offer = false),
                        child: const Text("Not now"),
                      ),
                      FilledButton.tonal(
                        key: const ValueKey("NewHomeFallbackAdd"),
                        onPressed: addToTab,
                        child: const Text("Add it to a tab"),
                      ),
                    ]),
                  ]),
            ),
          Expanded(
            child: wholePageBlock(widget.type, widget.clientManager, null,
                phone: MediaQuery.of(context).mobile),
          ),
        ]),
      ),
    );
  }
}
