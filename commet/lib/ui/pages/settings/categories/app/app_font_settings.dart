// Vommet: Settings › Appearance › Text: a preview message and the app font
// list (config/app_font.dart). A change applies at once.
import 'dart:io';

import 'package:commet/config/app_font.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AppFontSettings extends StatefulWidget {
  const AppFontSettings({super.key});

  /// Header for the panel this sits in.
  static String get header => _AppFontSettingsState.labelTextAndScaling;

  @override
  State<AppFontSettings> createState() => _AppFontSettingsState();
}

class _AppFontSettingsState extends State<AppFontSettings> {
  static String get labelTextAndScaling => Intl.message("Text and scaling",
      desc:
          "Header of the appearance settings panel with the app font and scale",
      name: "labelTextAndScaling");

  static String get labelAppFontPreview => Intl.message("Preview",
      desc: "Label above the sample message in the app font settings",
      name: "labelAppFontPreview");

  static String get labelAppFontSampleSender => Intl.message("Marigold",
      desc:
          "Made-up name of the sender of the sample message in the app font settings",
      name: "labelAppFontSampleSender");

  static String get labelAppFontSample => Intl.message(
      "Il1 O0 rn m: see you in the voice room at 9!",
      desc:
          "Sample message in the app font settings. Keep the look-alike letters 'Il1 O0 rn m' at the start, they show how clearly a font tells them apart",
      name: "labelAppFontSample");

  static String get labelAppFont => Intl.message("Font",
      desc: "Header of the app font list in appearance settings",
      name: "labelAppFont");

  static String get labelAppFontDefault => Intl.message("Default",
      desc: "App font option that keeps the app's own fonts",
      name: "labelAppFontDefault");

  static String get labelAppFontDefaultDescription =>
      Intl.message("Roboto and Nunito Sans",
          desc: "Description of the default app font option: the fonts it uses",
          name: "labelAppFontDefaultDescription");

  static String get labelAppFontAtkinsonDescription =>
      Intl.message("Made for low vision: every letter looks different",
          desc: "Description of the Atkinson Hyperlegible font option",
          name: "labelAppFontAtkinsonDescription");

  static String get labelAppFontLexendDescription =>
      Intl.message("Wide letters and spacing, easy to scan",
          desc: "Description of the Lexend font option",
          name: "labelAppFontLexendDescription");

  static String get labelAppFontOpenDyslexicDescription =>
      Intl.message("Heavier letter bottoms, made for dyslexia",
          desc: "Description of the OpenDyslexic font option",
          name: "labelAppFontOpenDyslexicDescription");

  static String get labelAppFontInterDescription =>
      Intl.message("Clean and compact",
          desc: "Description of the Inter font option",
          name: "labelAppFontInterDescription");

  static String get labelAppFontSystem => Intl.message("System font",
      desc: "App font option that uses the device's own font",
      name: "labelAppFontSystem");

  static String get labelAppFontSystemDescription =>
      Intl.message("Your device's own font",
          desc: "Description of the system font option",
          name: "labelAppFontSystemDescription");

  static String get labelAppFontUseFile =>
      Intl.message("Use a font file… (.ttf / .otf)",
          desc: "Button in the app font settings that picks a font file",
          name: "labelAppFontUseFile");

  static String get labelAppFontPickFileTitle =>
      Intl.message("Pick a font file",
          desc: "Title of the file picker for the app font",
          name: "labelAppFontPickFileTitle");

  static String get labelAppFontNotAFont =>
      Intl.message("That file isn't a font. Pick a .ttf or .otf file.",
          desc: "Error shown when the picked app font file is not a font",
          name: "labelAppFontNotAFont");

  String? error;

  String? descriptionFor(String id) => switch (id) {
        "atkinson" => labelAppFontAtkinsonDescription,
        "lexend" => labelAppFontLexendDescription,
        "opendyslexic" => labelAppFontOpenDyslexicDescription,
        "inter" => labelAppFontInterDescription,
        _ => null,
      };

  Future<void> select(String id) async {
    await preferences.appFont.set(id);
    if (!mounted) return;
    setState(() => error = null);
    // Rebuild the MaterialApp so its theme picks up the new font.
    ThemeChanger.setTheme(context, ThemeChanger.currentTheme(context));
  }

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["ttf", "otf", "ttc"],
        dialogTitle: labelAppFontPickFileTitle);
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;

    final copy = await AppFont.importFile(path);
    if (copy == null) {
      if (mounted) setState(() => error = labelAppFontNotAFont);
      return;
    }
    await preferences.appFontFile.set(copy);
    await select(AppFont.file);
  }

  @override
  Widget build(BuildContext context) {
    final current = preferences.appFont.value;
    final filePath = preferences.appFontFile.value;
    final hasFile = filePath.isNotEmpty && File(filePath).existsSync();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.labelLow(labelAppFontPreview),
        const SizedBox(height: 6),
        _preview(context),
        const SizedBox(height: 12),
        tiamat.Text.labelEmphasised(labelAppFont),
        const SizedBox(height: 4),
        _FontRow(
          title: labelAppFontDefault,
          subtitle: labelAppFontDefaultDescription,
          family: "RobotoCustom",
          selected: AppFont.familyFor(current, filePath: filePath) == null,
          onTap: () => select(AppFont.defaultId),
        ),
        for (final f in AppFont.bundled)
          _FontRow(
            title: f.name,
            subtitle: descriptionFor(f.id) ?? "",
            family: f.family,
            selected: current == f.id,
            onTap: () => select(f.id),
          ),
        _FontRow(
          title: labelAppFontSystem,
          subtitle: labelAppFontSystemDescription,
          family: AppFont.systemFamily,
          selected: current == AppFont.system,
          onTap: () => select(AppFont.system),
        ),
        if (hasFile)
          _FontRow(
            title: p.basenameWithoutExtension(filePath),
            subtitle: p.extension(filePath).replaceFirst(".", "").toUpperCase(),
            family: AppFont.familyFor(AppFont.file, filePath: filePath),
            selected: current == AppFont.file,
            onTap: () => select(AppFont.file),
          ),
        if (!PlatformUtils.isWeb)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: pickFile,
              icon: const Icon(Icons.upload_file, size: 20),
              label: Text(labelAppFontUseFile),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(error!, style: TextStyle(color: scheme.error)),
          ),
      ],
    );
  }

  Widget _preview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xffffb74d),
            child: Text(labelAppFontSampleSender.characters.first,
                style: text.bodyMedium?.copyWith(
                    color: Colors.black, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(labelAppFontSampleSender,
                    style: text.bodyMedium?.copyWith(
                        color: const Color(0xffffb74d),
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(labelAppFontSample,
                    style: text.bodyLarge?.copyWith(color: scheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FontRow extends StatelessWidget {
  const _FontRow({
    required this.title,
    required this.subtitle,
    required this.family,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;

  /// Family the title is drawn in.
  final String? family;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.bodyMedium!;
    final dim = scheme.secondary;

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? scheme.primary.withAlpha(35) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? scheme.primary : dim),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: (family == null
                                ? text
                                : text.copyWith(fontFamily: family))
                            .copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          style: text.copyWith(fontSize: 12.5, color: dim)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
