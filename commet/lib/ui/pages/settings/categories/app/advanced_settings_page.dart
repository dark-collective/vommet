import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/android_renderer.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({super.key});

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  String get labelSettingsDeveloperMode => Intl.message("Developer mode",
      desc: "Header for the settings to enable developer mode",
      name: "labelSettingsDeveloperMode");

  String get labelSettingsDeveloperModeExplanation =>
      Intl.message("Shows extra information, useful for developers",
          desc: "Explains what developer mode does",
          name: "labelSettingsDeveloperModeExplanation");

  String get labelSettingsShowHiddenEvents => Intl.message("Show hidden events",
      desc: "Developer mode setting: also show events the timeline hides",
      name: "labelSettingsShowHiddenEvents");

  String get labelSettingsShowHiddenEventsExplanation => Intl.message(
      "Also show events the timeline normally hides, such as reactions and deletions, as plain rows",
      desc: "Explains the show hidden events developer setting",
      name: "labelSettingsShowHiddenEventsExplanation");

  String get labelStickerCompatibility => Intl.message("Sticker compatibility",
      desc: "Header for the settings to enable sticker compatibility mode",
      name: "labelStickerCompatibility");

  String get labelSettingsStickerCompatibilityExplanation => Intl.message(
      "In some matrix clients, sending a sticker as 'm.sticker' will cause the sticker to not load correctly. Enabling this setting will send stickers as 'm.image' which will allow them to render correctly",
      desc: "Explains what sticker compatibility mode does",
      name: "labelSettingsStickerCompatibilityExplanation");

  String get labelAndroidRenderer => Intl.message("Renderer",
      desc: "Header for the setting that picks how Vommet draws on Android",
      name: "labelAndroidRenderer");

  String get labelAndroidRendererExplanation => Intl.message(
      "If letters go missing from text, try another renderer. Takes effect after restarting Vommet",
      desc: "Explains when to change the Android renderer",
      name: "labelAndroidRendererExplanation");

  String get labelAndroidRendererDefault => Intl.message("Default",
      desc: "Android renderer option: Flutter's default renderer",
      name: "labelAndroidRendererDefault");

  String get labelAndroidRendererOpenGL => Intl.message("OpenGL",
      desc: "Android renderer option: Impeller on OpenGL ES",
      name: "labelAndroidRendererOpenGL");

  String get labelAndroidRendererSkia => Intl.message("Compatibility (Skia)",
      desc: "Android renderer option: the older Skia renderer",
      name: "labelAndroidRendererSkia");

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Panel(
          header: labelSettingsDeveloperMode,
          mode: TileType.surfaceContainerLow,
          child: Column(
            children: [
              BooleanPreferenceToggle(
                preference: preferences.developerMode,
                title: labelSettingsDeveloperMode,
                description: labelSettingsDeveloperModeExplanation,
                onChanged: (_) => setState(() {}),
              ),
              // Vommet: only offered once developer mode is on.
              if (preferences.developerMode.value)
                BooleanPreferenceToggle(
                  preference: preferences.showHiddenEvents,
                  title: labelSettingsShowHiddenEvents,
                  description: labelSettingsShowHiddenEventsExplanation,
                ),
            ],
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        Panel(
            header: labelStickerCompatibility,
            mode: TileType.surfaceContainerLow,
            child: BooleanPreferenceToggle(
              preference: preferences.stickerCompatibilityMode,
              title: labelStickerCompatibility,
              description: labelSettingsStickerCompatibilityExplanation,
            )),
        const SizedBox(
          height: 10,
        ),
        Panel(
            mode: tiamat.TileType.surfaceContainerLow,
            header: "Override Layout",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelLow(
                    "You may need to restart the app for this to take effect"),
                tiamat.DropdownSelector(
                    items: [null, "desktop", "mobile"],
                    itemBuilder: (item) =>
                        tiamat.Text.label(item ?? "No Override"),
                    onItemSelected: (item) async {
                      await preferences.layoutOverride.set(item);
                      setState(() {});
                    },
                    value: preferences.layoutOverride.value)
              ],
            )),
        // Vommet: Android only, applied natively at launch (RendererChoice.kt).
        if (PlatformUtils.isAndroid) ...[
          const SizedBox(
            height: 10,
          ),
          Panel(
              mode: tiamat.TileType.surfaceContainerLow,
              header: labelAndroidRenderer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.labelLow(labelAndroidRendererExplanation),
                  tiamat.DropdownSelector<String?>(
                      items: const [null, "opengles", "skia"],
                      itemBuilder: (item) => tiamat.Text.label(switch (item) {
                            "opengles" => labelAndroidRendererOpenGL,
                            "skia" => labelAndroidRendererSkia,
                            _ => labelAndroidRendererDefault,
                          }),
                      onItemSelected: (item) async {
                        await AndroidRenderer.choice.set(item);
                        setState(() {});
                      },
                      value: AndroidRenderer.choice.value)
                ],
              )),
        ],
      ],
    );
  }
}
