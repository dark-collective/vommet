import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/pages/settings/desktop_settings_page.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/search/settings_search_entries.dart';
import 'package:commet/ui/pages/settings/settings_button.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import '../../navigation/navigation_utils.dart';
import 'package:commet/utils/scaled_app.dart';

class MobileSettingsPage extends StatefulWidget {
  const MobileSettingsPage(
      {required this.settings,
      this.buttons,
      this.onDonateButtonTapped,
      this.showDonateButton = false,
      super.key});
  final List<SettingsButton>? buttons;
  final List<SettingsCategory> settings;
  final bool showDonateButton;

  final Function(BuildContext context)? onDonateButtonTapped;
  @override
  State<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

/// Vommet issue 861: the Material minimum touch target, in dp on the device.
const double settingsRowMinTapTarget = 48;

/// Vommet issue 861: the height (in the app's logical pixels) of a mobile
/// Settings menu row, so it stays at least [settingsRowMinTapTarget] dp on
/// the device whatever the App Scale is. Below scale 1 the rows grow in
/// logical pixels; above it they keep 48 and come out bigger anyway.
double settingsRowHeightForScale(double scale) {
  if (scale <= 0 || scale >= 1) return settingsRowMinTapTarget;
  return settingsRowMinTapTarget / scale;
}

class _MobileSettingsPageState extends State<MobileSettingsPage> {
  late List<SettingsCategory> tabs;
  int selectedTabIndex = 0;
  int selectedCategoryIndex = 0;

  @override
  void initState() {
    tabs = widget.settings;
    super.initState();
  }

  // Vommet: settings search (app settings only).
  late final bool searchable = isAppSettings(widget.settings);
  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";
  List<SettingsSearchHit> searchHits = const [];
  int highlightSerial = 0;

  bool get searching => searchQuery.trim().isNotEmpty;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
      searchHits = searchAppSettings(query, tabs);
    });
  }

  void openSearchHit(SettingsSearchHit hit) {
    final tab = tabs[hit.categoryIndex].tabs[hit.tabIndex];
    highlightSerial++;
    NavigationUtils.navigateTo(
        context,
        SettingsHighlight(
            targetId: hit.isPage ? null : hit.entry.targetId,
            serial: highlightSerial,
            child: SettingsSubPage(
                makeScrollable: tab.makeScrollable, builder: tab.pageBuilder)));
  }

  @override
  Widget build(BuildContext context) {
    return m.Material(
      child: Tile.surfaceContainer(
        child: ScaledSafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: CircleButton(
                        radius: 25,
                        icon: m.Icons.arrow_back,
                        onPressed: () => Navigator.of(context).pop(),
                      )),
                ),
                if (searchable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                    child: SettingsSearchField(
                        controller: searchController,
                        onChanged: onSearchChanged),
                  ),
                if (searching)
                  Flexible(
                    child: ListView(children: [
                      SettingsSearchResults(
                          query: searchQuery,
                          hits: searchHits,
                          showHeader: false,
                          onOpen: openSearchHit),
                    ]),
                  ),
                if (!searching)
                  Flexible(
                    child: ListView(children: [
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: tabs.length,
                        itemBuilder: (context, categoryIndex) {
                          return m.Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: m.Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (categoryIndex != 0)
                                  const tiamat.Seperator(),
                                if (tabs[categoryIndex].title != null)
                                  tiamat.Text.labelLow(
                                    tabs[categoryIndex].title!,
                                  ),
                                ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: tabs[categoryIndex].tabs.length,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemBuilder: (context, tabIndex) {
                                    return button(
                                      label: tabs[categoryIndex]
                                          .tabs[tabIndex]
                                          .label,
                                      icon: tabs[categoryIndex]
                                          .tabs[tabIndex]
                                          .icon,
                                      onTap: () {
                                        setState(() {
                                          NavigationUtils.navigateTo(
                                              context,
                                              SettingsSubPage(
                                                  makeScrollable:
                                                      tabs[categoryIndex]
                                                          .tabs[tabIndex]
                                                          .makeScrollable,
                                                  builder: tabs[categoryIndex]
                                                      .tabs[tabIndex]
                                                      .pageBuilder));
                                        });
                                      },
                                    );
                                  },
                                )
                              ],
                            ),
                          );
                        },
                      ),
                      if (widget.buttons != null) const Seperator(),
                      // Vommet: same 8 px inset as the tab rows above, so
                      // the bottom entries (Quit Vommet, Leave Room) line up.
                      if (widget.buttons != null)
                        m.Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: widget.buttons!.length,
                            itemBuilder: (context, index) {
                              var b = widget.buttons![index];
                              return button(
                                  key: b.key,
                                  label: b.label,
                                  icon: b.icon,
                                  color: b.color,
                                  onTap: b.onPress);
                            },
                          ),
                        )
                    ]),
                  ),
                if (widget.showDonateButton)
                  DesktopSettingsPageState.buildDonateButton(context,
                      onTap: () => widget.onDonateButtonTapped?.call(context))
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget button(
      {Key? key,
      required String label,
      IconData? icon,
      bool highlighted = false,
      Color? color,
      Function()? onTap}) {
    return SizedBox(
        key: key,
        height: settingsRowHeightForScale(
            ScaledWidgetsFlutterBinding.maybeInstance?.scale ?? 1.0),
        child: TextButton(
          label,
          icon: icon,
          highlighted: highlighted,
          onTap: onTap,
          textColor: color,
          iconColor: color,
        ));
  }
}

class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage(
      {required this.builder, super.key, this.makeScrollable = true});
  final Widget Function(BuildContext) builder;
  final bool makeScrollable;
  @override
  Widget build(BuildContext context) {
    return m.Material(
      child: Tile(
        child: ScaledSafeArea(
          child: m.Padding(
            padding: const EdgeInsets.all(8.0),
            child: Stack(
              children: [
                if (makeScrollable)
                  ListView(
                    children: [
                      const SizedBox(
                        height: 70,
                      ),
                      builder(context)
                    ],
                  ),
                if (!makeScrollable)
                  m.Padding(
                    padding: const EdgeInsets.fromLTRB(0, 70, 0, 0),
                    child: builder(context),
                  ),
                m.Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleButton(
                    radius: 25,
                    icon: m.Icons.arrow_back,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
