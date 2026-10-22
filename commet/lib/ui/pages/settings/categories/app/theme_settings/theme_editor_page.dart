import 'package:commet/config/layout_config.dart';
import 'package:commet/config/theme_draft.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_bubble.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_color_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/config/style/theme_nordic.dart';

/// Vommet: make or change a theme, Telegram style. Pick a theme to start
/// from, tap any color to change it, watch the preview, save it as your own
/// theme or share it as a .zip.
class ThemeEditorPage extends StatefulWidget {
  const ThemeEditorPage({required this.draft, super.key});

  final ThemeDraft draft;

  @override
  State<ThemeEditorPage> createState() => _ThemeEditorPageState();
}

class _ThemeEditorPageState extends State<ThemeEditorPage> {
  late ThemeDraft draft;
  late TextEditingController nameController;
  final history = <ThemeDraft>[];
  int tab = 0;
  ThemeData? preview;
  int buildGeneration = 0;
  String search = "";
  String? selected;
  bool dirty = false;
  bool saving = false;

  String get labelThemeEditorTitle => Intl.message("Theme editor",
      name: "labelThemeEditorTitle", desc: "Title of the theme editor page");

  String get labelThemeEditorName => Intl.message("Theme name",
      name: "labelThemeEditorName",
      desc: "Hint in the theme editor's name field");

  String get labelThemeEditorStartFrom => Intl.message("Start from",
      name: "labelThemeEditorStartFrom",
      desc:
          "Label before the built-in themes a new theme can copy its colors from");

  String get labelThemeEditorFind => Intl.message("Find a color",
      name: "labelThemeEditorFind",
      desc: "Hint in the search field above the theme editor's color list");

  String get labelThemeEditorPreview => Intl.message("Preview",
      name: "labelThemeEditorPreview",
      desc: "Label above the live preview in the theme editor");

  String get labelThemeEditorSave => Intl.message("Save",
      name: "labelThemeEditorSave", desc: "Saves the theme");

  String get labelThemeEditorUndo => Intl.message("Undo",
      name: "labelThemeEditorUndo", desc: "Undoes the last color change");

  String get labelThemeEditorShare => Intl.message("Share as file",
      name: "labelThemeEditorShare",
      desc: "Saves the theme and exports it as a .zip file others can import");

  String get labelThemeEditorDone => Intl.message("Done",
      name: "labelThemeEditorDone", desc: "Closes the color picker");

  String get labelThemeEditorDiscardPrompt => Intl.message(
      "Leave without saving? Your changes to this theme will be lost.",
      name: "labelThemeEditorDiscardPrompt",
      desc: "Asked when leaving the theme editor with unsaved changes");

  String get labelThemeEditorDiscard => Intl.message("Leave",
      name: "labelThemeEditorDiscard",
      desc: "Confirms leaving the theme editor without saving");

  String get labelThemeEditorKeepEditing => Intl.message("Keep editing",
      name: "labelThemeEditorKeepEditing",
      desc: "Cancels leaving the theme editor");

  String labelThemeEditorExported(String file) =>
      Intl.message("Theme saved to $file",
          args: [file],
          name: "labelThemeEditorExported",
          desc: "Shown after the theme was exported as a .zip file");

  String get labelThemeEditorLowContrast => Intl.message(
      "Hard to read on the chat background",
      name: "labelThemeEditorLowContrast",
      desc:
          "Warning under a text color in the theme editor when it has too little contrast with the chat background");

  String get labelThemeGroupAccent => Intl.message("Accent",
      name: "labelThemeGroupAccent",
      desc: "Theme editor group: accent and link colors");
  String get labelThemeGroupBackgrounds => Intl.message("Backgrounds",
      name: "labelThemeGroupBackgrounds",
      desc: "Theme editor group: background colors");
  String get labelThemeGroupText => Intl.message("Text",
      name: "labelThemeGroupText", desc: "Theme editor group: text colors");
  String get labelThemeGroupDetails => Intl.message("Details",
      name: "labelThemeGroupDetails",
      desc: "Theme editor group: mentions, errors, borders and code colors");
  String get labelThemeSlotAccent => Intl.message("Accent",
      name: "labelThemeSlotAccent",
      desc: "Theme editor color: the accent color");
  String get labelThemeSlotAccentHint =>
      Intl.message("Buttons, switches, selected things",
          name: "labelThemeSlotAccentHint",
          desc: "What the accent color paints");
  String get labelThemeSlotOnAccent => Intl.message("Text on accent",
      name: "labelThemeSlotOnAccent",
      desc: "Theme editor color: text drawn on the accent color");
  String get labelThemeSlotOnAccentHint =>
      Intl.message("Labels on accent buttons",
          name: "labelThemeSlotOnAccentHint",
          desc: "What the text-on-accent color paints");
  String get labelThemeSlotLinks => Intl.message("Links",
      name: "labelThemeSlotLinks",
      desc: "Theme editor color: links in messages");
  String get labelThemeSlotLinksHint => Intl.message("Links in messages",
      name: "labelThemeSlotLinksHint", desc: "What the link color paints");
  String get labelThemeSlotChat => Intl.message("Chat",
      name: "labelThemeSlotChat", desc: "Theme editor color: chat background");
  String get labelThemeSlotChatHint => Intl.message("Behind messages",
      name: "labelThemeSlotChatHint",
      desc: "What the chat background color paints");
  String get labelThemeSlotRoomList => Intl.message("Room list",
      name: "labelThemeSlotRoomList",
      desc: "Theme editor color: room list / sidebar background");
  String get labelThemeSlotRoomListHint =>
      Intl.message("Sidebar, member list, message box",
          name: "labelThemeSlotRoomListHint",
          desc: "What the room list color paints");
  String get labelThemeSlotPopups => Intl.message("Popups",
      name: "labelThemeSlotPopups",
      desc: "Theme editor color: tooltips, menus and other popups");
  String get labelThemeSlotPopupsHint =>
      Intl.message("Tooltips, menus, link previews",
          name: "labelThemeSlotPopupsHint",
          desc: "What the popups color paints");
  String get labelThemeSlotWindow => Intl.message("Window",
      name: "labelThemeSlotWindow",
      desc: "Theme editor color: the window behind all panels");
  String get labelThemeSlotWindowHint =>
      Intl.message("Space rail, gaps between panels",
          name: "labelThemeSlotWindowHint",
          desc: "What the window color paints");
  String get labelThemeSlotPanels => Intl.message("Panels",
      name: "labelThemeSlotPanels",
      desc: "Theme editor color: settings panels and cards");
  String get labelThemeSlotPanelsHint =>
      Intl.message("Settings panels and cards",
          name: "labelThemeSlotPanelsHint",
          desc: "What the panel color paints");
  String get labelThemeSlotRaised => Intl.message("Raised",
      name: "labelThemeSlotRaised",
      desc: "Theme editor color: selected rows, dividers");
  String get labelThemeSlotRaisedHint => Intl.message("Selected rows, dividers",
      name: "labelThemeSlotRaisedHint", desc: "What the raised color paints");
  String get labelThemeSlotHighest => Intl.message("Highest",
      name: "labelThemeSlotHighest",
      desc: "Theme editor color: chips and loading placeholders");
  String get labelThemeSlotHighestHint =>
      Intl.message("Chips, loading placeholders",
          name: "labelThemeSlotHighestHint",
          desc: "What the highest color paints");
  String get labelThemeSlotText => Intl.message("Text",
      name: "labelThemeSlotText", desc: "Theme editor color: main text");
  String get labelThemeSlotTextHint => Intl.message("Messages and names",
      name: "labelThemeSlotTextHint", desc: "What the text color paints");
  String get labelThemeSlotMuted => Intl.message("Muted text",
      name: "labelThemeSlotMuted", desc: "Theme editor color: secondary text");
  String get labelThemeSlotMutedHint => Intl.message("Timestamps, hints, icons",
      name: "labelThemeSlotMutedHint",
      desc: "What the muted text color paints");
  String get labelThemeSlotMentions => Intl.message("Mentions",
      name: "labelThemeSlotMentions",
      desc: "Theme editor color: mentions and highlights");
  String get labelThemeSlotMentionsHint =>
      Intl.message("Mentions and highlights",
          name: "labelThemeSlotMentionsHint",
          desc: "What the mention color paints");
  String get labelThemeSlotErrors => Intl.message("Errors",
      name: "labelThemeSlotErrors",
      desc: "Theme editor color: errors and leave buttons");
  String get labelThemeSlotErrorsHint =>
      Intl.message("Errors and dangerous buttons",
          name: "labelThemeSlotErrorsHint",
          desc: "What the error color paints");
  String get labelThemeSlotBorders => Intl.message("Borders",
      name: "labelThemeSlotBorders", desc: "Theme editor color: panel borders");
  String get labelThemeSlotBordersHint => Intl.message("Panel borders",
      name: "labelThemeSlotBordersHint", desc: "What the border color paints");
  String get labelThemeSlotCode => Intl.message("Code",
      name: "labelThemeSlotCode", desc: "Theme editor color: inline code");
  String get labelThemeSlotCodeHint => Intl.message("Inline code in messages",
      name: "labelThemeSlotCodeHint", desc: "What the code color paints");
  String get labelThemeGroupBubbles => Intl.message("Message bubbles",
      name: "labelThemeGroupBubbles",
      desc: "Theme editor group: chat bubble background colors");
  String get labelThemeSlotOwnBubble => Intl.message("Your messages",
      name: "labelThemeSlotOwnBubble",
      desc: "Theme editor color: background of your own chat bubbles");
  String get labelThemeSlotOwnBubbleHint => Intl.message("Bubbles you send",
      name: "labelThemeSlotOwnBubbleHint",
      desc: "What the own bubble color paints");
  String get labelThemeSlotOtherBubble => Intl.message(
      "Other people's messages",
      name: "labelThemeSlotOtherBubble",
      desc: "Theme editor color: background of other people's chat bubbles");
  String get labelThemeSlotOtherBubbleHint =>
      Intl.message("Bubbles others send",
          name: "labelThemeSlotOtherBubbleHint",
          desc: "What the other people's bubble color paints");
  String get labelThemeBubblesNote =>
      Intl.message("Only in the Chat bubbles layout.",
          name: "labelThemeBubblesNote",
          desc: "Theme editor: under the bubble colors, where they apply");
  String get labelThemeColorAutomatic => Intl.message("Automatic",
      name: "labelThemeColorAutomatic",
      desc: "Theme editor: an optional color the theme leaves unset");
  String get labelThemeUseAutomatic => Intl.message("Use automatic",
      name: "labelThemeUseAutomatic",
      desc: "Theme editor color picker: unset an optional color");

  String groupName(ThemeSlotGroup group) => switch (group) {
        ThemeSlotGroup.accent => labelThemeGroupAccent,
        ThemeSlotGroup.backgrounds => labelThemeGroupBackgrounds,
        ThemeSlotGroup.bubbles => labelThemeGroupBubbles,
        ThemeSlotGroup.text => labelThemeGroupText,
        ThemeSlotGroup.status => labelThemeGroupDetails,
      };

  (String, String) slotText(String key) => switch (key) {
        "primary" => (labelThemeSlotAccent, labelThemeSlotAccentHint),
        "onPrimary" => (labelThemeSlotOnAccent, labelThemeSlotOnAccentHint),
        "links" => (labelThemeSlotLinks, labelThemeSlotLinksHint),
        "surface" => (labelThemeSlotChat, labelThemeSlotChatHint),
        "surfaceContainerLow" => (
            labelThemeSlotRoomList,
            labelThemeSlotRoomListHint
          ),
        "surfaceContainerLowest" => (
            labelThemeSlotPopups,
            labelThemeSlotPopupsHint
          ),
        ThemeSlot.foundationKey => (
            labelThemeSlotWindow,
            labelThemeSlotWindowHint
          ),
        "surfaceContainer" => (labelThemeSlotPanels, labelThemeSlotPanelsHint),
        "surfaceContainerHigh" => (
            labelThemeSlotRaised,
            labelThemeSlotRaisedHint
          ),
        "surfaceContainerHighest" => (
            labelThemeSlotHighest,
            labelThemeSlotHighestHint
          ),
        "onSurface" => (labelThemeSlotText, labelThemeSlotTextHint),
        "secondary" => (labelThemeSlotMuted, labelThemeSlotMutedHint),
        "tertiary" => (labelThemeSlotMentions, labelThemeSlotMentionsHint),
        "error" => (labelThemeSlotErrors, labelThemeSlotErrorsHint),
        "outline" => (labelThemeSlotBorders, labelThemeSlotBordersHint),
        "codeHighlight" => (labelThemeSlotCode, labelThemeSlotCodeHint),
        ThemeSlot.ownBubbleKey => (
            labelThemeSlotOwnBubble,
            labelThemeSlotOwnBubbleHint
          ),
        ThemeSlot.otherBubbleKey => (
            labelThemeSlotOtherBubble,
            labelThemeSlotOtherBubbleHint
          ),
        _ => (key, ""),
      };

  List<(String, ThemeData)> get startingPoints => [
        ("Light", ThemeLight.theme),
        ("Dark", ThemeDark.theme),
        ("Amoled", ThemeAmoled.theme),
        ("Nordic", ThemeNordic.theme),
        ("Nordic Polar", ThemeNordic.polar),
      ];

  @override
  void initState() {
    super.initState();
    draft = widget.draft.copy();
    nameController = TextEditingController(text: draft.name);
    rebuildPreview();
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> rebuildPreview() async {
    var generation = ++buildGeneration;
    try {
      var theme = await draft.build();
      if (!mounted || generation != buildGeneration) return;
      setState(() => preview = theme);
    } catch (e, s) {
      Log.e("Theme editor preview failed: $e\n$s");
    }
  }

  void remember() {
    history.add(draft.copy());
    if (history.length > 100) history.removeAt(0);
  }

  /// Background and Shape changes: one undo step per change.
  void change(void Function() apply) {
    remember();
    setState(() {
      apply();
      dirty = true;
    });
    rebuildPreview();
  }

  void setColor(String key, Color color) {
    if (draft.colors[key] == color) return;
    setState(() {
      draft.colors[key] = color;
      dirty = true;
    });
    rebuildPreview();
  }

  /// Unsets an optional color, back to what the app picks by itself.
  void useAutomatic(String key) {
    if (!draft.colors.containsKey(key)) return;
    setState(() {
      draft.colors.remove(key);
      dirty = true;
    });
    rebuildPreview();
  }

  /// What an unset optional color shows as: today's bubble colors.
  Color automaticColor(String key) {
    var theme = preview;
    if (theme == null) return Colors.transparent;
    var (color, _) = TimelineEventLayoutBubble.bubbleColors(theme.colorScheme,
        isOwnMessage: key == ThemeSlot.ownBubbleKey);
    return color;
  }

  void startFrom(ThemeData theme) {
    change(() => draft = ThemeDraft.fromTheme(theme, draft.name,
        raw: draft.raw, sourceDir: draft.sourceDir));
  }

  void undo() {
    if (history.isEmpty) return;
    var last = history.removeLast();
    setState(() {
      draft = last;
      dirty = true;
    });
    rebuildPreview();
  }

  List<Color> get palette {
    var seen = <int>{};
    return [
      for (var c in [
        ...draft.colors.values,
        NordColors.nord7,
        NordColors.nord8,
        NordColors.nord10,
        NordColors.nord11,
        NordColors.nord12,
        NordColors.nord13,
        NordColors.nord14,
        NordColors.nord15,
        ThemeDarkColors.primary,
      ])
        if (seen.add(c.toARGB32())) c
    ];
  }

  Future<void> editColor(String key) async {
    var (title, _) = slotText(key);
    var before = draft.colors[key];
    remember();
    setState(() => selected = key);

    await AdaptiveDialog.show(
      context,
      title: title,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 320,
            child: ThemeColorPicker(
              initial: before ?? automaticColor(key),
              palette: palette,
              onChanged: (c) => setColor(key, c),
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (ThemeSlot.optionalKeys.contains(key))
              TextButton(
                onPressed: () {
                  useAutomatic(key);
                  Navigator.of(context).pop();
                },
                child: Text(labelThemeUseAutomatic),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(labelThemeEditorDone),
            ),
          ]),
        ],
      ),
    );

    if (!mounted) return;
    // Opening and closing without a change leaves nothing to undo.
    if (draft.colors[key] == before) history.removeLast();
    setState(() => selected = null);
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      draft.name = ThemeDraft.safeName(nameController.text);
      var file = await draft.save();
      // Vommet: while following the system, into the slot being edited.
      await preferences.pickTheme(draft.name);
      if (!mounted) return;
      ThemeChanger.setThemeFromFile(context, file);
      dirty = false;
      Navigator.of(context).pop();
    } catch (e, s) {
      Log.e("Saving theme failed: $e\n$s");
      if (mounted) AdaptiveDialog.showError(context, e, s);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> share() async {
    try {
      draft.name = ThemeDraft.safeName(nameController.text);
      var file = await draft.save();
      nameController.text = draft.name;
      var bytes = await ThemeDraft.zip(file.parent);
      var result = await FilePicker.platform.saveFile(
        dialogTitle: labelThemeEditorShare,
        fileName: "${draft.name}.zip",
        type: FileType.custom,
        allowedExtensions: ["zip"],
        bytes: bytes,
      );
      // The picker writes the bytes itself, on desktop and mobile.
      if (result == null) return;
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(labelThemeEditorExported(result))));
      }
    } catch (e, s) {
      Log.e("Exporting theme failed: $e\n$s");
      if (mounted) AdaptiveDialog.showError(context, e, s);
    }
  }

  Future<bool> confirmLeave() async {
    if (!dirty) return true;
    var leave = await AdaptiveDialog.confirmation(context,
        prompt: labelThemeEditorDiscardPrompt,
        title: labelThemeEditorTitle,
        confirmationText: labelThemeEditorDiscard,
        cancelText: labelThemeEditorKeepEditing,
        dangerous: true);
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    var mobile = MediaQuery.of(context).mobile;
    var colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmLeave() && context.mounted) {
          dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        body: ScaledSafeArea(
          child: Column(children: [
            topBar(context),
            Expanded(
              child: mobile ? mobileBody(context) : desktopBody(context),
            ),
          ]),
        ),
      ),
    );
  }

  Widget topBar(BuildContext context) {
    var colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outline))),
      child: Row(children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: TextField(
            controller: nameController,
            onChanged: (_) => dirty = true,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              hintText: labelThemeEditorName,
              suffixIcon: const Icon(Icons.edit, size: 16),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: labelThemeEditorUndo,
          icon: const Icon(Icons.undo),
          onPressed: history.isEmpty ? null : undo,
        ),
        IconButton(
          tooltip: labelThemeEditorShare,
          icon: const Icon(Icons.ios_share),
          onPressed: share,
        ),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(labelThemeEditorSave),
        ),
      ]),
    );
  }

  Widget desktopBody(BuildContext context) {
    var colors = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 400,
        color: colors.surfaceContainerLow,
        child: ListView(
          padding: const EdgeInsets.all(8),
          children: tabContent(context),
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(labelThemeEditorPreview,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: colors.secondary)),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 16 / 10,
                child: livePreview(),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget mobileBody(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: SizedBox(height: 220, child: livePreview(compact: true)),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          children: tabContent(context),
        ),
      ),
    ]);
  }

  Widget livePreview({bool compact = false}) {
    var theme = preview;
    if (theme == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Theme(
      data: theme,
      child: ThemeLivePreview(theme: theme, compact: compact),
    );
  }

  String get labelThemeTabColors => Intl.message("Colors",
      name: "labelThemeTabColors", desc: "Theme editor tab: colors");

  String get labelThemeTabBackground => Intl.message("Background",
      name: "labelThemeTabBackground",
      desc: "Theme editor tab: what is behind the panels");

  String get labelThemeTabShape => Intl.message("Shape",
      name: "labelThemeTabShape",
      desc: "Theme editor tab: corners, spacing and borders");

  String get labelThemeBackgroundSolid => Intl.message("Solid",
      name: "labelThemeBackgroundSolid",
      desc: "Theme background choice: the plain Window color");

  String get labelThemeBackgroundGradient => Intl.message("Gradient",
      name: "labelThemeBackgroundGradient",
      desc: "Theme background choice: a color gradient");

  String get labelThemeBackgroundImage => Intl.message("Image",
      name: "labelThemeBackgroundImage",
      desc: "Theme background choice: a picture");

  String get labelThemeGradientColors => Intl.message("Gradient colors",
      name: "labelThemeGradientColors",
      desc: "Heading above the colors of a theme's background gradient");

  String get labelThemeGradientAngle => Intl.message("Angle",
      name: "labelThemeGradientAngle",
      desc: "Slider for the direction of the background gradient");

  String get labelThemeChooseImage => Intl.message("Choose image",
      name: "labelThemeChooseImage",
      desc: "Button that picks a picture for the theme background");

  String get labelThemePanelsOverBackground => Intl.message(
      "Panels over the background",
      name: "labelThemePanelsOverBackground",
      desc:
          "Heading above the sliders for how see-through the panels are over a gradient or image");

  String get labelThemeOpacityRoomList => Intl.message("Room list",
      name: "labelThemeOpacityRoomList",
      desc: "Slider: how solid the room list is over the background");

  String get labelThemeOpacityChat => Intl.message("Chat",
      name: "labelThemeOpacityChat",
      desc: "Slider: how solid the chat is over the background");

  String get labelThemeBlur => Intl.message("Blur",
      name: "labelThemeBlur",
      desc: "Slider: how much the background is blurred behind panels");

  String get labelThemeCorners => Intl.message("Corner roundness",
      name: "labelThemeCorners",
      desc: "Slider: how round the corners of panels are");

  String get labelThemeSpacing => Intl.message("Space between panels",
      name: "labelThemeSpacing", desc: "Slider: the gap between panels");

  String get labelThemeBorders => Intl.message("Panel borders",
      name: "labelThemeBorders",
      desc: "Switch: draw a thin border around panels");

  String get labelThemeRemoveColor => Intl.message("Remove color",
      name: "labelThemeRemoveColor",
      desc: "Removes a color from the background gradient");

  String get labelThemeAddColor => Intl.message("Add color",
      name: "labelThemeAddColor",
      desc: "Adds a color to the background gradient");

  List<Widget> tabContent(BuildContext context) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 0, label: Text(labelThemeTabColors)),
            ButtonSegment(value: 1, label: Text(labelThemeTabBackground)),
            ButtonSegment(value: 2, label: Text(labelThemeTabShape)),
          ],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
      ),
      if (tab == 0) ...[
        startFromRow(context),
        searchField(context),
        ...slotList(context),
      ],
      if (tab == 1) ...backgroundTab(context),
      if (tab == 2) ...shapeTab(context),
    ];
  }

  Widget heading(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      );

  Widget slider(BuildContext context, String label, double value,
      {required double min,
      required double max,
      required String Function(double) format,
      required ValueChanged<double> onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        SizedBox(
            width: 130,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChangeStart: (_) => remember(),
            onChanged: (v) {
              setState(() {
                onChanged(v);
                dirty = true;
              });
              rebuildPreview();
            },
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(format(value),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }

  Future<void> editGradientColor(int index) async {
    var before = draft.gradientColors[index];
    remember();
    await AdaptiveDialog.show(
      context,
      title: labelThemeGradientColors,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 320,
            child: ThemeColorPicker(
              initial: before,
              palette: palette,
              onChanged: (c) {
                setState(() {
                  draft.gradientColors = List.of(draft.gradientColors)
                    ..[index] = c;
                  dirty = true;
                });
                rebuildPreview();
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (draft.gradientColors.length > 2)
              TextButton(
                onPressed: () {
                  setState(() {
                    draft.gradientColors = List.of(draft.gradientColors)
                      ..removeAt(index);
                    draft.gradientStops = null;
                    dirty = true;
                  });
                  rebuildPreview();
                  Navigator.of(context).pop();
                },
                child: Text(labelThemeRemoveColor),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(labelThemeEditorDone),
            ),
          ]),
        ],
      ),
    );
    if (!mounted) return;
    if (draft.gradientColors.length > index &&
        draft.gradientColors[index] == before) {
      history.removeLast();
      setState(() {});
    }
  }

  Future<void> chooseImage() async {
    var result = await FilePicker.platform
        .pickFiles(type: FileType.image, dialogTitle: labelThemeChooseImage);
    var picked = result?.files.firstOrNull?.path;
    if (picked == null) return;
    change(() {
      draft.background = ThemeBackground.image;
      draft.imageFile = picked;
    });
  }

  List<Widget> backgroundTab(BuildContext context) {
    var colors = Theme.of(context).colorScheme;
    var see = draft.background != ThemeBackground.solid;
    String percent(double v) => "${(v * 100).round()}%";

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
        child: SegmentedButton<ThemeBackground>(
          segments: [
            ButtonSegment(
                value: ThemeBackground.solid,
                icon: const Icon(Icons.square_rounded, size: 16),
                label: Text(labelThemeBackgroundSolid)),
            ButtonSegment(
                value: ThemeBackground.gradient,
                icon: const Icon(Icons.gradient, size: 16),
                label: Text(labelThemeBackgroundGradient)),
            ButtonSegment(
                value: ThemeBackground.image,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(labelThemeBackgroundImage)),
          ],
          selected: {draft.background},
          onSelectionChanged: (v) {
            if (v.first == ThemeBackground.image && draft.imageFile == null) {
              chooseImage();
              return;
            }
            change(() => draft.background = v.first);
          },
        ),
      ),
      if (draft.background == ThemeBackground.gradient) ...[
        heading(context, labelThemeGradientColors),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < draft.gradientColors.length; i++)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => editGradientColor(i),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: draft.gradientColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.onSurface.withAlpha(60)),
                  ),
                ),
              ),
            if (draft.gradientColors.length < 5)
              IconButton.outlined(
                tooltip: labelThemeAddColor,
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => change(() {
                  draft.gradientColors = [
                    ...draft.gradientColors,
                    draft.gradientColors.last
                  ];
                  draft.gradientStops = null;
                }),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        slider(context, labelThemeGradientAngle, draft.gradientAngle,
            min: 0,
            max: 360,
            format: (v) => "${v.round()}°",
            onChanged: (v) => draft.gradientAngle = v),
      ],
      if (draft.background == ThemeBackground.image)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
          child: OutlinedButton.icon(
            onPressed: chooseImage,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(labelThemeChooseImage),
          ),
        ),
      if (see) ...[
        heading(context, labelThemePanelsOverBackground),
        slider(context, labelThemeOpacityRoomList, draft.roomListOpacity,
            min: 0.2,
            max: 1,
            format: percent,
            onChanged: (v) => draft.roomListOpacity = v),
        slider(context, labelThemeOpacityChat, draft.chatOpacity,
            min: 0.2,
            max: 1,
            format: percent,
            onChanged: (v) => draft.chatOpacity = v),
        slider(context, labelThemeBlur, draft.blur,
            min: 0,
            max: 30,
            format: (v) => v.round().toString(),
            onChanged: (v) => draft.blur = v),
      ],
    ];
  }

  List<Widget> shapeTab(BuildContext context) {
    return [
      const SizedBox(height: 8),
      slider(context, labelThemeCorners, draft.cornerRadius,
          min: 0,
          max: 16,
          format: (v) => v.round().toString(),
          onChanged: (v) => draft.cornerRadius = v.roundToDouble()),
      slider(context, labelThemeSpacing, draft.spacing,
          min: 0,
          max: 12,
          format: (v) => v.round().toString(),
          onChanged: (v) => draft.spacing = v.roundToDouble()),
      SwitchListTile(
        title: Text(labelThemeBorders),
        value: draft.borders,
        onChanged: (v) => change(() => draft.borders = v),
      ),
    ];
  }

  Widget startFromRow(BuildContext context) {
    var colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(labelThemeEditorStartFrom,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: colors.secondary)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var (name, theme) in startingPoints)
              ActionChip(
                avatar: CircleAvatar(
                    backgroundColor: theme.colorScheme.surface,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle),
                    )),
                label: Text(name),
                onPressed: () => startFrom(theme),
              ),
          ]),
        ],
      ),
    );
  }

  Widget searchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: TextField(
        onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: labelThemeEditorFind,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  List<Widget> slotList(BuildContext context) {
    var colors = Theme.of(context).colorScheme;
    var widgets = <Widget>[];
    ThemeSlotGroup? group;

    for (var slot in ThemeSlot.all) {
      var (name, hint) = slotText(slot.key);
      if (search.isNotEmpty &&
          !name.toLowerCase().contains(search) &&
          !hint.toLowerCase().contains(search) &&
          !colorToHex(draft.colors[slot.key] ?? Colors.transparent)
              .contains(search)) {
        continue;
      }

      if (slot.group != group) {
        group = slot.group;
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
          child: Text(groupName(slot.group).toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.secondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
        ));
      }

      var picked = draft.colors[slot.key];
      var value = picked ?? automaticColor(slot.key);
      var warn = lowContrast(slot.key);
      widgets.add(Material(
        color: selected == slot.key
            ? colors.surfaceContainerHigh
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => editColor(slot.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: value,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.onSurface.withAlpha(50)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(warn ? labelThemeEditorLowContrast : hint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: warn ? colors.error : colors.secondary)),
                  ],
                ),
              ),
              if (warn)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.warning_amber_rounded,
                      size: 18, color: colors.error),
                ),
              Text(
                  picked == null
                      ? labelThemeColorAutomatic
                      : colorToHex(value).toUpperCase(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.secondary,
                      fontStyle: picked == null
                          ? FontStyle.italic
                          : FontStyle.normal)),
            ]),
          ),
        ),
      ));
      if (slot.key == ThemeSlot.otherBubbleKey) {
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
          child: Text(labelThemeBubblesNote,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.secondary)),
        ));
      }
    }
    return widgets;
  }

  /// Text and muted text under WCAG's 4.5:1 / 3:1 against the chat.
  bool lowContrast(String key) {
    if (key != "onSurface" && key != "secondary") return false;
    var fg = draft.colors[key];
    var bg = draft.colors["surface"];
    if (fg == null || bg == null) return false;
    var a = fg.computeLuminance(), b = bg.computeLuminance();
    var ratio = ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
    return ratio < (key == "onSurface" ? 4.5 : 3);
  }
}

/// Vommet: a drawing of the app — space rail, room list, chat with a few
/// messages and the message box — in [theme]'s colors.
class ThemeLivePreview extends StatelessWidget {
  const ThemeLivePreview(
      {required this.theme, this.compact = false, super.key});

  final ThemeData theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    var s = theme.colorScheme;
    var text = theme.textTheme;
    var foundation = theme.extension<FoundationSettings>();
    var glass = theme.extension<GlassSettings>();
    var shape = theme.extension<ThemeSettings>();
    var gap = shape?.caulkPadding ?? 0;
    var radius = BorderRadius.circular(shape?.caulkBorderRadius ?? 0);
    var border = shape?.caulkBorders == true
        ? Border.all(color: s.outline, width: shape!.caulkStrokeThickness)
        : null;

    // Over a gradient or image, panels let it show through.
    Color panel(Color c, double? opacity) => glass != null && opacity != null
        ? c.withAlpha((opacity * 255).round())
        : c;

    BoxDecoration box(Color c, double? opacity) => BoxDecoration(
        color: panel(c, opacity), borderRadius: radius, border: border);

    var link = theme.extension<ExtraColors>()?.linkColor ?? s.primary;
    var code = theme.extension<ExtraColors>()?.codeHighlight ?? s.tertiary;

    Widget avatar(Color c, String letter, double r) => CircleAvatar(
          radius: r,
          backgroundColor: c,
          child: Text(letter,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: r * 0.9,
                  fontWeight: FontWeight.w700)),
        );

    Widget room(String name, {bool sel = false, bool unread = false}) =>
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
              color: sel ? s.secondaryContainer : null,
              borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            Icon(Icons.tag, size: 14, color: s.secondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                      color: sel || unread ? s.onSurface : s.secondary,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w400)),
            ),
            if (unread)
              Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: s.onSurface, shape: BoxShape.circle)),
          ]),
        );

    Widget message(Color c, String who, List<InlineSpan> body,
            {bool mention = false}) =>
        Container(
          color: mention ? s.tertiary.withAlpha(30) : null,
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            avatar(c, who[0], 13),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(who,
                      style: text.bodySmall
                          ?.copyWith(color: c, fontWeight: FontWeight.w700)),
                  Text.rich(TextSpan(
                      style: text.bodySmall?.copyWith(color: s.onSurface),
                      children: body)),
                ],
              ),
            ),
            Text("12:4${who.length % 10}",
                style: text.labelSmall?.copyWith(color: s.secondary)),
          ]),
        );

    // The Chat bubbles layout's colors (Vommet issue 532).
    Widget bubble(String body, {required bool own}) {
      var (bg, fg) = TimelineEventLayoutBubble.bubbleColors(s,
          isOwnMessage: own, extra: theme.extension<ExtraColors>());
      return Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.fromLTRB(own ? 10 : 31, 3, 10, 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(body, style: text.bodySmall?.copyWith(color: fg)),
        ),
      );
    }

    var image = foundation?.image;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(gap),
      decoration: BoxDecoration(
        color: foundation?.color ?? s.surfaceContainerLowest,
        gradient: foundation?.gradient,
        image: image == null
            ? null
            : DecorationImage(
                image: image, fit: foundation?.imageFit ?? BoxFit.cover),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: s.outline),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 46,
          // The app paints the space rail with the Window color.
          decoration: box(s.surfaceDim, glass?.surfaceDimOpacity),
          padding: const EdgeInsets.only(top: 8),
          child: Column(children: [
            avatar(s.primary, "L", 15),
            const SizedBox(height: 8),
            avatar(s.secondary, "Q", 15),
            const SizedBox(height: 8),
            avatar(s.secondary, "P", 15),
          ]),
        ),
        if (!compact)
          Container(
            width: 150,
            margin: EdgeInsets.only(left: gap > 0 ? gap : 1),
            decoration:
                box(s.surfaceContainerLow, glass?.surfaceContainerLowOpacity),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                  child: Text("Lantern Club",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                          color: s.onSurface, fontWeight: FontWeight.w800)),
                ),
                room("general", sel: true),
                room("tea-time", unread: true),
                room("photos"),
                room("board-games"),
              ],
            ),
          ),
        Expanded(
          child: Container(
            margin: EdgeInsets.only(left: gap > 0 ? gap : 1),
            clipBehavior: Clip.antiAlias,
            decoration: box(s.surface, glass?.surfaceOpacity),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: s.outline))),
                  child: Row(children: [
                    Icon(Icons.tag, size: 15, color: s.secondary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text("general",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                              color: s.onSurface, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
                Expanded(
                  child: ClipRect(
                    child: ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        message(NordColors.nord12, "Marisol",
                            [const TextSpan(text: "kettle's on, who's in?")]),
                        message(
                            NordColors.nord14,
                            "Tobias",
                            [
                              const TextSpan(text: "me! "),
                              TextSpan(
                                  text: "@Wren",
                                  style: TextStyle(
                                      color: s.primary,
                                      fontWeight: FontWeight.w700)),
                              const TextSpan(text: " bring the "),
                              TextSpan(
                                  text: "shortbread",
                                  style: TextStyle(
                                      color: code, fontFamily: "Code")),
                            ],
                            mention: true),
                        message(NordColors.nord9, "Wren", [
                          TextSpan(
                              text: "lantern.example/menu",
                              style: TextStyle(
                                  color: link,
                                  decoration: TextDecoration.underline,
                                  decorationColor: link)),
                        ]),
                        bubble("see you at 9", own: false),
                        bubble("on my way!", own: true),
                      ],
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                      // Same color as the app's message box.
                      color: panel(s.surfaceContainerLow,
                          glass?.surfaceContainerLowOpacity),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(
                      child: Text("Message #general",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: s.secondary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: s.primary,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text("Send",
                          style: text.labelSmall?.copyWith(
                              color: s.onPrimary, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
