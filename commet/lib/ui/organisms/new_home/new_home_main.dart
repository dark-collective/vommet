import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/organisms/home_screen/home_screen.dart';
import 'package:commet/ui/organisms/invitation_view/invite_preview_page.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_people.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/update_checker.dart';
import 'package:flutter/material.dart';

/// Vommet: Home's main area with the New Home experiment on: the page the
/// column's rows picked (Overview, People or Rooms). On phones the rows open
/// their page full screen ([NewHomePageScreen]); this area shows Overview.
/// [home] is the old Home ([HomeScreen]); only its burger callback is used.
class NewHomeMain extends StatefulWidget {
  const NewHomeMain({super.key, required this.home, required this.phone});

  final Widget home;
  final bool phone;

  @override
  State<NewHomeMain> createState() => _NewHomeMainState();
}

class _NewHomeMainState extends State<NewHomeMain> {
  static bool _reportedRoomListOnScreen = false;

  @override
  void initState() {
    super.initState();
    newHomePage.addListener(leaveCustomizing);
    // The old Home checked for updates when it opened; it isn't built now.
    if (preferences.checkForUpdates.value == true) {
      UpdateChecker.checkForUpdates();
    }
    // The old Home's startup timer, same name, so app_ready reports it
    // either way: the room list on screen (from the local cache).
    if (!_reportedRoomListOnScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_reportedRoomListOnScreen) return;
        final manager = clientManager;
        if (manager == null || manager.rooms.isEmpty) return;
        _reportedRoomListOnScreen = true;
        Diagnostics.general.addResult(
            "Startup: room list on screen (since launch)",
            startupClock.elapsed);
      });
    }
  }

  @override
  void dispose() {
    newHomePage.removeListener(leaveCustomizing);
    // Customize mode ends with the page that showed it (not while the
    // tree is locked).
    Future.microtask(() => newHomeCustomizing.value = false);
    super.dispose();
  }

  /// Leaving Overview ends customize mode.
  void leaveCustomizing() {
    if (newHomePage.value == NewHomePage.overview) return;
    Future.microtask(() => newHomeCustomizing.value = false);
  }

  @override
  Widget build(BuildContext context) {
    final main = context.findAncestorStateOfType<MainPageState>();
    final manager = main?.clientManager ?? clientManager;
    if (manager == null) return const SizedBox.shrink();
    HomeLayoutStore.instance.attach(manager);
    final filter = main?.filterClient;

    if (widget.phone) {
      final home = widget.home;
      final burger = home is HomeScreen ? home.onBurgerMenuTap : null;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ScaledSafeArea(
          bottom: false,
          child: NewHomeHeader(
            page: NewHomePage.overview,
            phone: true,
            leading: burger == null
                ? null
                : IconButton(icon: const Icon(Icons.menu), onPressed: burger),
          ),
        ),
        // Like the old Home: "Your messages aren't backed up".
        const SecureSetupBanner(),
        Expanded(
          child: NewHomeOverview(
              clientManager: manager, filterClient: filter, phone: true),
        ),
      ]);
    }

    // Like the old Home: an invite opened from Home fills this pane, under
    // the backup banner.
    return ScaledSafeArea(
      child: InvitePreviewHost(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SecureSetupBanner(),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: newHomePage,
              builder: (context, page, _) => ValueListenableBuilder(
                valueListenable: newHomeCustomizing,
                builder: (context, customizing, _) {
                  final body = pageBody(page, manager, filter, phone: false);
                  if (!customizing || page != NewHomePage.overview) {
                    return body;
                  }
                  // Customize mode: the Card library beside Overview.
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: body),
                        NewHomeCardLibraryPanel(clientManager: manager),
                      ]);
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A page's content under its header.
Widget pageBody(NewHomePage page, ClientManager manager, Client? filter,
    {required bool phone, Widget? leading}) {
  final Widget body = switch (page) {
    NewHomePage.overview => NewHomeOverview(
        clientManager: manager, filterClient: filter, phone: phone),
    NewHomePage.people =>
      PeopleView(clientManager: manager, filterClient: filter, phone: phone),
    NewHomePage.rooms =>
      NewHomeRooms(clientManager: manager, filterClient: filter, phone: phone),
  };
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    NewHomeHeader(
        key: ValueKey("NewHomeHeader-${page.name}"),
        page: page,
        phone: phone,
        leading: leading),
    Expanded(child: body),
  ]);
}

/// The page title bar: icon and name (and a back or menu button on phones).
class NewHomeHeader extends StatelessWidget {
  const NewHomeHeader(
      {super.key, required this.page, required this.phone, this.leading});

  final NewHomePage page;
  final bool phone;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      padding: EdgeInsets.symmetric(horizontal: phone ? 8 : 20),
      decoration: BoxDecoration(
          color: phone ? scheme.surfaceContainerLow : null,
          border: phone
              ? null
              : Border(
                  bottom: BorderSide(color: scheme.surfaceContainerHighest))),
      child: Row(spacing: 10, children: [
        if (leading != null) leading!,
        Icon(page.icon, size: phone ? 18 : 20, color: scheme.onSurfaceVariant),
        Text(page.label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface)),
        if (page == NewHomePage.overview)
          Expanded(child: _OverviewHeaderActions(phone: phone)),
      ]),
    );
  }
}

/// Overview's header: a "Customize" button (customize mode on desktop, the
/// customize screen on phones), or, in customize mode, a "Customizing" tag
/// and how it works.
class _OverviewHeaderActions extends StatelessWidget {
  const _OverviewHeaderActions({required this.phone});
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: newHomeCustomizing,
      builder: (context, customizing, _) {
        if (customizing && !phone) {
          return Row(spacing: 10, children: [
            Container(
              key: const ValueKey("NewHomeCustomizingTag"),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(40),
                  borderRadius: BorderRadius.circular(6)),
              child: Text("Customizing",
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary)),
            ),
            Expanded(
              child: Text(
                  "Drag to reorder · drag back to the library to remove",
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            ),
          ]);
        }
        return Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const ValueKey("NewHomeCustomizeButton"),
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outlineVariant),
                padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () {
              final manager = clientManager;
              if (manager == null) return;
              customizeOverview(context, phone: phone, clientManager: manager);
            },
            icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
            label: const Text("Customize",
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        );
      },
    );
  }
}

/// Phones: a Home row's page, full screen, with a back button. Closes when
/// a room opens, so the room shows.
class NewHomePageScreen extends StatefulWidget {
  const NewHomePageScreen(
      {super.key,
      required this.page,
      required this.clientManager,
      this.filterClient});

  final NewHomePage page;
  final ClientManager clientManager;
  final Client? filterClient;

  static void push(
      BuildContext context, NewHomePage page, ClientManager clientManager,
      {Client? filterClient}) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NewHomePageScreen(
            page: page,
            clientManager: clientManager,
            filterClient: filterClient)));
  }

  @override
  State<NewHomePageScreen> createState() => _NewHomePageScreenState();
}

class _NewHomePageScreenState extends State<NewHomePageScreen> {
  late final StreamSubscription sub;

  @override
  void initState() {
    super.initState();
    sub = EventBus.openRoom.stream.listen((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
    // For the rail's People highlight; not during this build.
    Future.microtask(() => newHomeScreenOpen.value = widget.page);
  }

  @override
  void dispose() {
    sub.cancel();
    final page = widget.page;
    Future.microtask(() {
      if (newHomeScreenOpen.value == page) newHomeScreenOpen.value = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: ScaledSafeArea(
        child: pageBody(widget.page, widget.clientManager, widget.filterClient,
            phone: true,
            leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop())),
      ),
    );
  }
}
