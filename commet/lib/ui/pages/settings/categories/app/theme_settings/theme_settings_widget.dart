import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/config/layout_config.dart';
import 'package:commet/config/theme_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/config/theme_draft.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_editor_page.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_preview_card.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_gradient.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/config/style/theme_nordic.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:path/path.dart' as path;

class ThemeListWidget extends StatefulWidget {
  const ThemeListWidget({super.key});

  @override
  State<ThemeListWidget> createState() => _ThemeListWidgetState();
}

class _ThemeEntry {
  String name;

  /// The `theme` preference value this entry sets.
  String id;
  Function(BuildContext context) setter;

  /// Drawn by the entry's card.
  ThemeData preview;

  late Widget Function(BuildContext context, Widget child) builder;

  Widget defaultBuilder(BuildContext context, Widget child) {
    return child;
  }

  _ThemeEntry(this.name, this.id, this.preview, this.setter,
      {Widget Function(BuildContext context, Widget child)? builder}) {
    this.builder = builder ?? defaultBuilder;
  }
}

class _ThemeListWidgetState extends State<ThemeListWidget> {
  late List<_ThemeEntry> entries;
  StreamSubscription? customThemesDirSub;
  StreamSubscription? themeSub;

  String get labelThemeDark => Intl.message("Dark Theme",
      name: "labelThemeDark", desc: "Label for the dark theme");

  String get labelThemeLight => Intl.message("Light Theme",
      name: "labelThemeLight", desc: "Label for the light theme");

  String get labelThemeAmoled => Intl.message("Amoled",
      name: "labelThemeAmoled", desc: "Label for the light theme");

  String get labelThemes => Intl.message("Themes",
      name: "labelThemes",
      desc: "Heading above the cards of the built-in and custom themes");

  String get labelCreateTheme => Intl.message("Create theme",
      name: "labelCreateTheme",
      desc: "Button under the theme list that opens the theme editor");

  String get labelEditCurrentTheme => Intl.message("Edit current",
      name: "labelEditCurrentTheme",
      desc: "Button that opens the theme in use in the theme editor");

  String get labelNewThemeName => Intl.message("My theme",
      name: "labelNewThemeName",
      desc: "Default name of a theme made with Create theme");

  String labelThemeCopyName(String name) => Intl.message("$name (my copy)",
      args: [name],
      name: "labelThemeCopyName",
      desc: "Default name when a built-in theme is opened in the theme editor");

  String get labelCurrentTheme => Intl.message("Current theme",
      name: "labelCurrentTheme",
      desc: "Label beside the name of the theme in use, above the theme list");

  String get labelThemeGradientsDark => Intl.message("Dark gradients",
      name: "labelThemeGradientsDark",
      desc: "Heading above the dark full-window gradient themes");

  String get labelThemeGradientsLight => Intl.message("Light gradients",
      name: "labelThemeGradientsLight",
      desc: "Heading above the light full-window gradient themes");

  // Vommet: Nordic and Nordic Polar are names, not translated.
  static const labelThemeNordic = "Nordic";
  static const labelThemeNordicPolar = "Nordic Polar";

  _ThemeEntry builtIn(
          String name, String id, ThemeData preview, Brightness brightness) =>
      _ThemeEntry(name, id, preview, (BuildContext context) async {
        preferences.theme.set(id);
        var theme =
            await preferences.resolveTheme(overrideBrightness: brightness);
        if (context.mounted) ThemeChanger.setTheme(context, theme);
      });

  List<_ThemeEntry> get defaultThemes => [
        builtIn(labelThemeLight, "light", ThemeLight.theme, Brightness.light),
        builtIn(labelThemeDark, "dark", ThemeDark.theme, Brightness.dark),
        builtIn(labelThemeAmoled, "amoled", ThemeAmoled.theme, Brightness.dark),
        builtIn(labelThemeNordic, "nordic", ThemeNordic.theme, Brightness.dark),
        builtIn(labelThemeNordicPolar, "nordic-polar", ThemeNordic.polar,
            Brightness.light),
      ];

  @override
  void initState() {
    entries = List.from(defaultThemes);
    initCustomThemes();
    // Vommet: the "Current theme" line follows every pick.
    themeSub = preferences.theme.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    customThemesDirSub?.cancel();
    themeSub?.cancel();
    super.dispose();
  }

  void initCustomThemes() async {
    loadCustomThemes();
    var dir = await ThemeConfig.getCustomThemesDir();
    customThemesDirSub =
        dir.watch(recursive: true).listen(onCustomThemesDirUpdated);
  }

  void loadCustomThemes() async {
    var themes = await ThemeConfig.getCustomThemes();

    var customEntries = <_ThemeEntry>[];
    for (var e in themes) {
      var name = path.basenameWithoutExtension(e.path);
      var preview = await previewOf(e);

      customEntries.add(_ThemeEntry(
        name,
        name,
        preview,
        (context) async {
          var file = await ThemeConfig.getFileFromThemeDir(e);
          if (file != null) {
            if (context.mounted) ThemeChanger.setThemeFromFile(context, file);
            preferences.theme.set(name);
          }
        },
        builder: (context, child) {
          if (MediaQuery.of(context).mobile)
            return GestureDetector(
              onLongPress: () => AdaptiveDialog.show(
                context,
                title: name,
                builder: (context) {
                  return Column(
                    children: [
                      tiamat.TextButton(
                        CommonStrings.promptDelete,
                        icon: Icons.delete,
                        onTap: () {
                          ThemeConfig.removeTheme(e);
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                },
              ),
              child: child,
            );

          return tiamat.ContextMenu(
            items: [
              ContextMenuItem(
                  text: CommonStrings.promptDelete,
                  onPressed: () => ThemeConfig.removeTheme(e)),
            ],
            child: child,
          );
        },
      ));
    }
    var newEntries = List<_ThemeEntry>.from(defaultThemes);
    newEntries.addAll(customEntries);

    if (!mounted) return;
    setState(() {
      entries = newEntries;
    });
  }

  // A custom theme's card draws its own colors; an unreadable file falls back
  // to Dark rather than hiding the theme.
  Future<ThemeData> previewOf(Directory dir) async {
    try {
      var file = await ThemeConfig.getFileFromThemeDir(dir);
      if (file != null) {
        var json = const JsonDecoder().convert(await file.readAsString());
        var theme = await ThemeJsonConverter.fromJson(json, file);
        if (theme != null) return theme;
      }
    } catch (e) {
      Log.w("Could not read theme preview for ${dir.path}: $e");
    }
    return ThemeDark.theme;
  }

  void onCustomThemesDirUpdated(FileSystemEvent event) {
    Log.i("Themes dir updated, reloading items!");
    loadCustomThemes();
  }

  Future<void> setGradient(BuildContext context, GradientPreset preset) async {
    await preferences.theme.set(ThemeGradient.prefix + preset.id);
    var theme = await preferences.resolveTheme();
    if (context.mounted) ThemeChanger.setTheme(context, theme);
    if (mounted) setState(() {});
  }

  Widget gradientPicker(
      BuildContext context, Brightness brightness, String label) {
    var selected = preferences.theme.value;
    var presets =
        ThemeGradient.presets.where((p) => p.brightness == brightness);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tiamat.Text.labelLow(label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var preset in presets)
                Tooltip(
                  message: preset.name,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => setGradient(context, preset),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: preset.gradient,
                        border: Border.all(
                          width: 3,
                          color: selected == ThemeGradient.prefix + preset.id
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Vommet: name the theme in use. A gradient's name was only a hover
  // tooltip, which phones never show.
  Widget currentTheme(BuildContext context) {
    var value = preferences.theme.value;
    var preset = value.startsWith(ThemeGradient.prefix)
        ? ThemeGradient.byId(value)
        : null;
    var name = switch (value) {
      "light" => labelThemeLight,
      "dark" => labelThemeDark,
      "amoled" => labelThemeAmoled,
      "nordic" => labelThemeNordic,
      "nordic-polar" => labelThemeNordicPolar,
      _ => preset?.name ?? value,
    };
    var colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(child: tiamat.Text.labelLow(labelCurrentTheme)),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: preset?.gradient,
              color: preset == null ? colors.surfaceContainerHighest : null,
              border: Border.all(color: colors.secondary.withAlpha(60)),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // Vommet: the theme editor starts from Dark (Create theme) or from the
  // theme in use (Edit current): a built-in or gradient theme opens as a
  // copy, a custom theme opens itself.
  Future<void> openEditor(BuildContext context, {required bool current}) async {
    var id = preferences.theme.value;
    ThemeDraft draft;

    var entry = current ? entries.where((e) => e.id == id).firstOrNull : null;
    var gradient = current && id.startsWith(ThemeGradient.prefix)
        ? ThemeGradient.byId(id)
        : null;
    var custom = entry == null ? null : await ThemeConfig.getThemeByName(id);
    if (custom != null) {
      Map<String, dynamic> raw = {};
      try {
        raw = (const JsonDecoder().convert(await custom.readAsString()) as Map)
            .cast<String, dynamic>();
      } catch (e) {
        Log.w("Theme editor could not read ${custom.path}: $e");
      }
      draft = ThemeDraft.fromTheme(entry!.preview, entry.name,
          raw: raw, sourceDir: custom.parent);
    } else if (gradient != null) {
      draft = ThemeDraft.fromTheme(
          ThemeGradient.theme(gradient), labelThemeCopyName(gradient.name));
    } else if (entry != null) {
      draft =
          ThemeDraft.fromTheme(entry.preview, labelThemeCopyName(entry.name));
    } else {
      draft = ThemeDraft.fromTheme(ThemeDark.theme, labelNewThemeName);
    }

    if (!context.mounted) return;
    await NavigationUtils.navigateTo(context, ThemeEditorPage(draft: draft));
    if (mounted) setState(() {});
  }

  // Vommet: each theme is a little drawing of the app in its colors, like
  // Telegram's theme list, instead of a text button.
  Widget themeCards(BuildContext context) {
    var selected = preferences.theme.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: tiamat.Text.labelLow(labelThemes),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 6,
              runSpacing: 10,
              children: [
                for (var entry in entries)
                  entry.builder(
                    context,
                    ThemePreviewCard(
                      theme: entry.preview,
                      name: entry.name,
                      selected: entry.id == selected,
                      onTap: () async {
                        await entry.setter(context);
                        // Repaint so the selection follows.
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        currentTheme(context),
        themeCards(context),
        gradientPicker(context, Brightness.dark, labelThemeGradientsDark),
        gradientPicker(context, Brightness.light, labelThemeGradientsLight),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () => openEditor(context, current: false),
                    icon: const Icon(Icons.palette_outlined, size: 18),
                    label: Text(labelCreateTheme),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => openEditor(context, current: true),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(labelEditCurrentTheme),
                  ),
                ]),
              ),
              tiamat.CircleButton(
                icon: Icons.add,
                onPressed: () async {
                  var result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ["zip"],
                      dialogTitle: "Pick theme archive file");

                  var file = result?.files.firstOrNull;
                  if (file?.path == null) {
                    return;
                  }

                  File f = File(file!.path!);
                  await ThemeConfig.installThemeFromZip(f);
                },
              ),
            ],
          ),
        )
      ],
    );
  }
}
