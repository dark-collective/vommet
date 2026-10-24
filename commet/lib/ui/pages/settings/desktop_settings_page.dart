import 'package:commet/client/components/donation_awards/donation_awards_component.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/donation_rewards_confirmation.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/search/settings_search_entries.dart';
import 'package:commet/ui/pages/settings/settings_button.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_quit_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as m;
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage(
      {required this.settings,
      this.buttons,
      this.onDonateButtonTapped,
      this.showDonateButton = false,
      this.initialTab,
      this.initialHighlight,
      super.key});
  final List<SettingsCategory> settings;

  /// Vommet: label of the tab to select first.
  final String? initialTab;

  /// Vommet: a setting on that tab to scroll to and flash (its
  /// SettingsSearchTarget id).
  final String? initialHighlight;
  final List<SettingsButton>? buttons;
  final bool showDonateButton;
  final Function(BuildContext context)? onDonateButtonTapped;
  @override
  State<DesktopSettingsPage> createState() => DesktopSettingsPageState();
}

class DesktopSettingsPageState extends State<DesktopSettingsPage> {
  late List<SettingsCategory> categories;
  int selectedCategoryIndex = 0;
  int selectedTabIndex = 0;

  static ValueKey backButtonKey =
      const ValueKey("DESKTOP_SETTINGS_PAGE_BACK_BUTTON");

  // Vommet: below this width the page goes single-column (Vommet issue 614):
  // the tab list fills the page, and a tab opens full-width with a back
  // arrow to the list.
  static const double singleColumnWidth = 560;
  static ValueKey tabBackButtonKey =
      const ValueKey("DESKTOP_SETTINGS_PAGE_TAB_BACK_BUTTON");
  bool singleColumn = false;

  /// Single-column only: a tab is open (otherwise the tab list shows).
  bool showingTab = false;

  // Vommet: settings search (app settings only).
  late final bool searchable = isAppSettings(widget.settings);
  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";
  List<SettingsSearchHit> searchHits = const [];
  String? highlightId;
  int highlightSerial = 0;

  bool get searching => searchQuery.trim().isNotEmpty;

  void onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
      searchHits = searchAppSettings(query, categories);
    });
  }

  void openSearchHit(SettingsSearchHit hit) {
    setState(() {
      selectedCategoryIndex = hit.categoryIndex;
      selectedTabIndex = hit.tabIndex;
      highlightId = hit.isPage ? null : hit.entry.targetId;
      highlightSerial++;
      showingTab = true;
      searchController.clear();
      searchQuery = "";
      searchHits = const [];
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    categories = widget.settings;
    for (var c = 0; c < categories.length; c++) {
      final t =
          categories[c].tabs.indexWhere((t) => t.label == widget.initialTab);
      if (t >= 0) {
        selectedCategoryIndex = c;
        selectedTabIndex = t;
        showingTab = true;
        break;
      }
    }
    if (widget.initialHighlight != null) {
      highlightId = widget.initialHighlight;
      highlightSerial++;
    }
    super.initState();
  }

  // Vommet: Esc clears an active search first, then (single-column) goes
  // back from a tab to the tab list, otherwise closes the page.
  void onEscape() {
    if (searchController.text.isNotEmpty) {
      searchController.clear();
      onSearchChanged("");
      return;
    }
    if (singleColumn && showingTab) {
      setState(() => showingTab = false);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onEscape,
      },
      child: Focus(autofocus: true, child: buildPage(context)),
    );
  }

  Widget buildPage(BuildContext context) {
    return m.Material(
      color: m.Theme.of(context).colorScheme.surface,
      child: Foundation(
        child: LayoutBuilder(builder: (context, constraints) {
          singleColumn = constraints.maxWidth < singleColumnWidth;
          if (!singleColumn) return buildColumns(context);
          if (showingTab && !searching) return buildSingleTab(context);
          return tabSelector(context);
        }),
      ),
    );
  }

  // Vommet: single-column tab view, a back arrow to the tab list above it.
  Widget buildSingleTab(BuildContext context) {
    final tab = categories[selectedCategoryIndex].tabs[selectedTabIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tile.surfaceContainer(
          child: ScaledSafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                CircleButton(
                  key: tabBackButtonKey,
                  radius: 25,
                  icon: m.Icons.arrow_back,
                  onPressed: () => setState(() => showingTab = false),
                ),
                const SizedBox(width: 8),
                Flexible(child: tiamat.Text.labelEmphasised(tab.label)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: SettingsHighlight(
            targetId: highlightId,
            serial: highlightSerial,
            child: buildContent(scrollable: tab.makeScrollable),
          ),
        ),
      ],
    );
  }

  Widget buildColumns(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tabSelector(context),
        Expanded(
          child: searching
              ? buildSearchResults()
              : SettingsHighlight(
                  targetId: highlightId,
                  serial: highlightSerial,
                  child: buildContent(
                      scrollable: categories[selectedCategoryIndex]
                          .tabs[selectedTabIndex]
                          .makeScrollable),
                ),
        )
      ],
    );
  }

  Widget buildSearchResults() {
    return fullHeight(Tile(
      caulkPadTop: true,
      caulkPadBottom: true,
      caulkClipTopLeft: true,
      caulkClipBottomLeft: true,
      child: ScaledSafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SettingsSearchResults(
                query: searchQuery, hits: searchHits, onOpen: openSearchHit),
          ),
        ),
      ),
    ));
  }

  // Vommet: the panel always fills the full height, and the scroll view sits
  // inside it. Before, the Row's loose height (crossAxisAlignment.start) and
  // the scroll view around the Tile shrank the panel to its content, so the
  // theme's foundation (e.g. a background image) showed below short tabs.
  Widget fullHeight(Widget panel) =>
      SizedBox(height: double.infinity, child: panel);

  Widget buildContent({bool scrollable = false}) {
    Widget content = selectedCategoryIndex < categories.length &&
            selectedTabIndex < categories[selectedCategoryIndex].tabs.length
        ? settingsTab(categories[selectedCategoryIndex]
            .tabs[selectedTabIndex]
            .pageBuilder)
        : Container();
    return fullHeight(Tile(
      caulkPadTop: true,
      caulkPadBottom: true,
      caulkClipTopLeft: true,
      caulkClipBottomLeft: true,
      key: ValueKey(selectedTabIndex),
      child: ScaledSafeArea(
          child: scrollable ? SingleChildScrollView(child: content) : content),
    ));
  }

  Widget tabSelector(BuildContext context) {
    return Tile.surfaceContainer(
      caulkPadRight: true,
      caulkPadTop: true,
      caulkPadBottom: true,
      caulkClipTopRight: true,
      caulkClipBottomRight: true,
      caulkBorderRight: true,
      child: ScaledSafeArea(
        child: SizedBox(
          width: singleColumn ? double.infinity : 240,
          child: Column(
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(children: [
                          CircleButton(
                            key: backButtonKey,
                            radius: 25,
                            icon: m.Icons.arrow_back,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          const SettingsQuitButton(),
                        ]),
                      ),
                      if (searchable)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          child: SettingsSearchField(
                              controller: searchController,
                              onChanged: onSearchChanged),
                        ),
                      if (singleColumn && searching)
                        Flexible(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: SettingsSearchResults(
                                  query: searchQuery,
                                  hits: searchHits,
                                  onOpen: openSearchHit),
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                            child: ListView(children: [
                              ListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                shrinkWrap: true,
                                itemCount: categories.length,
                                itemBuilder: (context, categoryIndex) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (categoryIndex != 0)
                                        const tiamat.Seperator(),
                                      if (categories[categoryIndex].title !=
                                          null)
                                        tiamat.Text.labelLow(
                                            categories[categoryIndex].title!),
                                      tabListBuilder(categoryIndex)
                                    ],
                                  );
                                },
                              ),
                              if (widget.buttons != null) const Seperator(),
                              if (widget.buttons != null)
                                ListView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  itemCount: widget.buttons!.length,
                                  itemBuilder: (context, index) {
                                    return button(
                                        label: widget.buttons![index].label,
                                        icon: widget.buttons![index].icon,
                                        onTap: widget.buttons![index].onPress,
                                        color: widget.buttons![index].color);
                                  },
                                ),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.showDonateButton)
                buildDonateButton(context,
                    onTap: () => widget.onDonateButtonTapped?.call(context))
            ],
          ),
        ),
      ),
    );
  }

  static String get promptDonate => Intl.message("Donate",
      name: "promptDonate", desc: "Prompt the user to donate to the project");

  static String get promptDonationsRefreshAwards => Intl.message(
      "Refresh Awards",
      name: "promptDonationsRefreshAwards",
      desc:
          "Prompt the user to refresh any awards they may have received for donating to the project");

  static Widget buildDonateButton(BuildContext context, {Function()? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      child: AdaptiveContextMenu(
        items: [
          ContextMenuItem(
              text: promptDonationsRefreshAwards,
              icon: m.Icons.refresh,
              onPressed: () async {
                var client = await AdaptiveDialog.pickClient(context);

                if (client != null) {
                  var identifier = await client
                      .getComponent<DonationAwardsComponent>()
                      ?.getClientSecret();
                  if (identifier != null) {
                    AdaptiveDialog.show(
                      context,
                      builder: (context) {
                        return DonationRewardsConfirmation(
                          client: client,
                          identifier: identifier,
                          didOpenDonationWindow: false,
                          since: null,
                        );
                      },
                    );
                  }
                }
              }),
        ],
        child: m.Material(
          clipBehavior: Clip.antiAlias,
          color: m.ColorScheme.of(context).surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          child: m.InkWell(
            mouseCursor: m.WidgetStateMouseCursor.clickable,
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: m.Icon(
                          m.Icons.favorite,
                          color: m.ColorScheme.of(context).onSurfaceVariant,
                        ),
                      ),
                      tiamat.Text(
                        promptDonate,
                        color: m.ColorScheme.of(context).onSurface,
                      ),
                    ],
                  )),
            ),
          ),
        ),
      ),
    );
  }

  ListView tabListBuilder(int categoryIndex) {
    return ListView.builder(
      // Vommet: scroll with the whole sidebar, not as its own list.
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (context, tabIndex) {
        return button(
            label: categories[categoryIndex].tabs[tabIndex].label,
            icon: categories[categoryIndex].tabs[tabIndex].icon,
            highlighted: !searching &&
                categoryIndex == selectedCategoryIndex &&
                tabIndex == selectedTabIndex,
            // Vommet: while searching, grey out pages with no match.
            color: searching &&
                    !SettingsSearch.tabHasHit(
                        searchHits, categoryIndex, tabIndex)
                ? m.ColorScheme.of(context).onSurface.withValues(alpha: 0.38)
                : null,
            onTap: () {
              setState(() {
                selectedCategoryIndex = categoryIndex;
                selectedTabIndex = tabIndex;
                showingTab = true;
                highlightId = null;
                searchController.clear();
                searchQuery = "";
                searchHits = const [];
              });
            });
      },
      itemCount: categories[categoryIndex].tabs.length,
    );
  }

  Widget button(
      {required String label,
      IconData? icon,
      bool highlighted = false,
      Color? color,
      Function()? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: SizedBox(
          height: 40,
          width: singleColumn ? double.infinity : 200,
          child: TextButton(
            label,
            icon: icon,
            highlighted: highlighted,
            onTap: onTap,
            textColor: color,
            iconColor: color,
          )),
    );
  }

  Widget settingsTab(Widget Function(BuildContext context) builder) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: builder(context),
    );
  }
}
