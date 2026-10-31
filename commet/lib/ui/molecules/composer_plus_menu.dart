import 'dart:math' as math;

import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/composer_formatting/composer_formatting.dart';
import 'package:commet/ui/molecules/composer_ring_colors.dart';
import 'package:commet/ui/molecules/message_effect_picker.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet composer round 5: the + inside the message box opens one sheet
/// (phones) or menu (desktop) with three parts: SEND (photo or video,
/// camera, file, poll), IN THIS ROOM (translation and the formatting
/// toolbar) and THIS MESSAGE (schedule, effect).

/// Something to send from the + sheet.
class ComposerPlusAction {
  const ComposerPlusAction(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.grayed = false});

  final IconData icon;
  final String label;

  /// Runs after the sheet closed.
  final void Function() onTap;
  final bool grayed;
}

/// The room's translation settings, as the + sheet shows and changes them.
abstract class ComposerPlusRoomTranslation implements Listenable {
  /// "Translate this room".
  bool get readingOn;

  /// "Translate what I write"; works with or without the room translated.
  bool get writingOn;

  /// The language the room's messages are in, null when unknown.
  String? get language;

  /// What "Translate what I write" sends in, null when unknown.
  String? get writingLanguage;

  /// Remembers [code] as what you write in here.
  Future<void> setWritingLanguage(String code);

  Future<void> setReading(bool on);
  Future<void> setWriting(bool on);
  Future<void> setLanguage(String code);

  /// The short list under the language chip: the current language, recent
  /// and downloaded ones first.
  Future<List<String>> shortList();

  /// "More languages…": every language, in a picker titled [title]
  /// ("Messages here are in" by default). Null = none picked.
  Future<String?> pickMore(BuildContext context, {String? title});
}

/// At most this many languages in the chip's short list.
const int composerLanguageShortListLength = 5;

/// The chip's short list: [current], then [recent], then [downloaded],
/// keeping only languages in [reachable] (all when null), no repeats, at
/// most [composerLanguageShortListLength].
List<String> composerLanguageShortList(
    {String? current,
    required List<String> recent,
    required Iterable<String> downloaded,
    Set<String>? reachable}) {
  final result = <String>[];
  for (final code in [if (current != null) current, ...recent, ...downloaded]) {
    if (result.length >= composerLanguageShortListLength) break;
    if (result.contains(code)) continue;
    if (reachable != null && !reachable.contains(code)) continue;
    result.add(code);
  }
  return result;
}

class ComposerPlusMenu extends StatefulWidget {
  const ComposerPlusMenu({
    required this.send,
    this.translation,
    this.showFormattingToolbar = true,
    this.onSchedule,
    this.scheduleGrayed = false,
    this.effects = const [],
    this.effect,
    this.onEffect,
    this.phone = true,
    this.tablet = false,
    this.startAtRoom = false,
    super.key,
  });

  static const String labelSend = "SEND";
  static const String labelInThisRoom = "IN THIS ROOM";
  static const String labelThisMessage = "THIS MESSAGE";
  static const String labelTranslateRoom = "Translate this room";
  static const String labelTranslateWriting = "Translate what I write";
  static const String labelWriteIn = "Write in";
  static const String labelSchedule = "Schedule…";
  static const String labelEffect = "Effect";
  static const String labelNoEffect = "None";
  static const String labelMessagesAreIn = "MESSAGES HERE ARE IN";
  static const String labelMoreLanguages = "More languages…";
  static const String labelPickLanguage = "Language";

  /// SEND: tiles on phones, rows on desktop.
  final List<ComposerPlusAction> send;

  /// IN THIS ROOM's two translation rows; null hides them.
  final ComposerPlusRoomTranslation? translation;
  final bool showFormattingToolbar;

  /// THIS MESSAGE: "Schedule…"; null hides it.
  final void Function()? onSchedule;
  final bool scheduleGrayed;

  /// THIS MESSAGE: "Effect"; none hides it.
  final List<MessageEffectOption> effects;
  final MessageEffectOption? effect;
  final void Function(MessageEffectOption? effect)? onEffect;

  final bool phone;

  /// The menu (not [phone]'s sheet) on an iPad or Android tablet: SEND as
  /// tiles and touch-sized rows (Vommet issue 943).
  final bool tablet;

  /// Opened from a pill: scrolled to IN THIS ROOM.
  final bool startAtRoom;

  @override
  State<ComposerPlusMenu> createState() => _ComposerPlusMenuState();
}

class _ComposerPlusMenuState extends State<ComposerPlusMenu> {
  final GlobalKey roomSectionKey = GlobalKey();
  bool languagesOpen = false;
  bool effectsOpen = false;
  List<String>? shortList;

  @override
  void initState() {
    super.initState();
    widget.translation?.addListener(onChanged);
    if (widget.startAtRoom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = roomSectionKey.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(target, alignment: 0.1);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.translation?.removeListener(onChanged);
    super.dispose();
  }

  void onChanged() {
    if (mounted) setState(() {});
  }

  void close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void run(void Function() action) {
    close();
    action();
  }

  Future<void> toggleLanguages() async {
    final t = widget.translation;
    if (t == null) return;
    setState(() => languagesOpen = !languagesOpen);
    if (languagesOpen) {
      final list = await t.shortList();
      if (mounted) setState(() => shortList = list);
    }
  }

  Future<void> pickLanguage(String code) async {
    await widget.translation?.setLanguage(code);
    if (mounted) setState(() => languagesOpen = false);
  }

  /// Turning "Translate what I write" on with no language known yet asks
  /// for one first.
  Future<void> setWriting(bool on) async {
    final t = widget.translation;
    if (t == null) return;
    if (on && t.writingLanguage == null) {
      final code =
          await t.pickMore(context, title: ComposerPlusMenu.labelWriteIn);
      if (code == null) return;
      await t.setWritingLanguage(code);
    }
    await t.setWriting(on);
    if (mounted) setState(() {});
  }

  Future<void> moreLanguages() async {
    final t = widget.translation;
    if (t == null) return;
    final code = await t.pickMore(context);
    if (code != null) await pickLanguage(code);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.translation;
    final hasRoom = t != null || widget.showFormattingToolbar;
    final hasMessage = widget.onSchedule != null || widget.effects.isNotEmpty;
    final large = widget.tablet;
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: widget.phone
              ? 560
              : large
                  ? ComposerPlusPopover.tabletMaxWidth
                  : ComposerPlusPopover.width),
      child: Column(
        key: const ValueKey("composer-plus-menu"),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.send.isNotEmpty) ...[
            _Header(ComposerPlusMenu.labelSend, large: large),
            if (widget.phone || large)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                // A Wrap rather than a Row: when the tiles don't fit (a
                // narrow menu, a large text size) the last ones move to a
                // second line instead of overflowing.
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 4,
                    children: [
                      for (final a in widget.send)
                        _SendTile(
                            action: a, large: large, onTap: () => run(a.onTap)),
                    ],
                  ),
                ),
              )
            else
              for (final a in widget.send)
                _MenuRow(
                  large: large,
                  icon: a.icon,
                  label: a.label,
                  grayed: a.grayed,
                  onTap: () => run(a.onTap),
                ),
          ],
          if (hasRoom) ...[
            if (widget.send.isNotEmpty) _Divider(large: large),
            _Header(ComposerPlusMenu.labelInThisRoom,
                large: large, key: roomSectionKey),
            if (t != null) ...[
              _MenuRow(
                large: large,
                key: const ValueKey("composer-plus-translate-room"),
                icon: Icons.translate,
                label: ComposerPlusMenu.labelTranslateRoom,
                onTap: () => t.setReading(!t.readingOn),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _LanguageChip(
                      language: t.language,
                      open: languagesOpen,
                      onTap: toggleLanguages),
                  Switch(
                    key: const ValueKey("composer-plus-translate-room-switch"),
                    value: t.readingOn,
                    onChanged: (on) => t.setReading(on),
                  ),
                ]),
              ),
              if (languagesOpen)
                _LanguageList(
                  languages: shortList,
                  current: t.language,
                  onPick: pickLanguage,
                  onMore: moreLanguages,
                ),
              _MenuRow(
                large: large,
                key: const ValueKey("composer-plus-translate-writing"),
                icon: Icons.edit_outlined,
                label: ComposerPlusMenu.labelTranslateWriting,
                onTap: () => setWriting(!t.writingOn),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (t.writingLanguage != null)
                    tiamat.Text.labelLow(
                        "into ${translationLanguageName(t.writingLanguage!)}"),
                  Switch(
                    key: const ValueKey(
                        "composer-plus-translate-writing-switch"),
                    value: t.writingOn,
                    onChanged: setWriting,
                  ),
                ]),
              ),
            ],
            if (widget.showFormattingToolbar)
              _MenuRow(
                large: large,
                icon: Icons.text_format,
                label: ComposerFormatting.labelFormattingToolbar,
                onTap: toggleFormatting,
                trailing: Switch(
                  key: const ValueKey("composer-formatting-toolbar-switch"),
                  value: preferences.formattingToolbar.value,
                  onChanged: (_) => toggleFormatting(),
                ),
              ),
          ],
          if (hasMessage) ...[
            if (widget.send.isNotEmpty || hasRoom) _Divider(large: large),
            _Header(ComposerPlusMenu.labelThisMessage, large: large),
            if (widget.onSchedule != null)
              _MenuRow(
                large: large,
                key: const ValueKey("composer-plus-schedule"),
                icon: Icons.schedule_send_outlined,
                label: ComposerPlusMenu.labelSchedule,
                grayed: widget.scheduleGrayed,
                onTap: () => run(widget.onSchedule!),
              ),
            if (widget.onSchedule != null && widget.effects.isNotEmpty)
              const _Divider(thin: true),
            if (widget.effects.isNotEmpty) ...[
              _MenuRow(
                large: large,
                key: const ValueKey("composer-plus-effect"),
                leading: const Text("✨", style: TextStyle(fontSize: 18)),
                label: ComposerPlusMenu.labelEffect,
                onTap: () => setState(() => effectsOpen = !effectsOpen),
                trailing: tiamat.Text.labelLow(
                    "${effectName(widget.effect)} ${effectsOpen ? "▴" : "▸"}"),
              ),
              if (effectsOpen)
                EffectGrid(
                  options: widget.effects,
                  selected: widget.effect,
                  onPick: (option) {
                    widget.onEffect
                        ?.call(option == widget.effect ? null : option);
                    close();
                  },
                ),
            ],
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  static String effectName(MessageEffectOption? effect) => effect == null
      ? ComposerPlusMenu.labelNoEffect
      : "${effect.emoji} ${effect.label()}";

  Future<void> toggleFormatting() async {
    await preferences.formattingToolbar
        .set(!preferences.formattingToolbar.value);
    onChanged();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.large = false, super.key});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: large
          ? const EdgeInsets.fromLTRB(16, 14, 16, 6)
          : const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(text,
          style: TextStyle(
              fontSize: large ? 13 : 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({this.thin = false, this.large = false});

  final bool thin;
  final bool large;

  @override
  Widget build(BuildContext context) => Divider(
      height: thin ? 1 : (large ? 16 : 12),
      indent: large ? 14 : 10,
      endIndent: large ? 14 : 10,
      color: Theme.of(context).colorScheme.outlineVariant.withAlpha(110));
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(
      {required this.label,
      required this.onTap,
      this.icon,
      this.leading,
      this.trailing,
      this.grayed = false,
      this.large = false,
      super.key});

  final IconData? icon;
  final Widget? leading;
  final String label;
  final void Function() onTap;
  final Widget? trailing;
  final bool grayed;

  /// Touch-sized, for tablets.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = grayed ? Theme.of(context).disabledColor : scheme.onSurface;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: large ? 52 : 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: large ? 16 : 12),
            child: Row(
              children: [
                SizedBox(
                    width: large ? 28 : 24,
                    child: Center(
                        child: leading ??
                            Icon(icon, size: large ? 24 : 20, color: color))),
                SizedBox(width: large ? 16 : 12),
                Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color, fontSize: large ? 17 : null))),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendTile extends StatelessWidget {
  const _SendTile(
      {required this.action, required this.onTap, this.large = false});

  final ComposerPlusAction action;
  final void Function() onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: large ? 28 : 24,
              backgroundColor: scheme.surfaceContainerHighest,
              child: Icon(action.icon,
                  size: large ? 26 : null, color: scheme.onSurface),
            ),
            SizedBox(height: large ? 7 : 6),
            Text(action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: large ? 13 : 12, color: scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip(
      {required this.language, required this.open, required this.onTap});

  final String? language;
  final bool open;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = language == null
        ? ComposerPlusMenu.labelPickLanguage
        : translationLanguageName(language!);
    return Material(
      key: const ValueKey("composer-plus-language-chip"),
      color: scheme.primary.withAlpha(40),
      shape: StadiumBorder(side: BorderSide(color: scheme.primary)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Text("$name ${open ? "▴" : "▾"}",
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary)),
        ),
      ),
    );
  }
}

class _LanguageList extends StatelessWidget {
  const _LanguageList(
      {required this.languages,
      required this.current,
      required this.onPick,
      required this.onMore});

  /// Null while loading.
  final List<String>? languages;
  final String? current;
  final void Function(String code) onPick;
  final void Function() onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey("composer-plus-language-list"),
      margin: const EdgeInsets.fromLTRB(48, 0, 12, 6),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withAlpha(120),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Header(ComposerPlusMenu.labelMessagesAreIn),
          if (languages == null)
            const Padding(
                padding: EdgeInsets.all(8),
                child: Center(
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))))
          else
            for (final code in languages!)
              InkWell(
                key: ValueKey("composer-plus-language-$code"),
                onTap: () => onPick(code),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Expanded(child: Text(translationLanguageName(code))),
                    if (code == current)
                      Icon(Icons.check, size: 18, color: scheme.primary),
                  ]),
                ),
              ),
          InkWell(
            key: const ValueKey("composer-plus-more-languages"),
            onTap: onMore,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(ComposerPlusMenu.labelMoreLanguages,
                  style: TextStyle(color: scheme.primary)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [menu]: a sheet on phones, a menu over [anchor] on desktop.
/// [tablet]: a touch screen in the desktop layout (iPad, Android tablet),
/// where the menu is wider and scales with the screen.
Future<void> showComposerPlusMenu(BuildContext context,
    {required Widget Function(BuildContext context, bool phone) builder,
    BuildContext? anchor,
    bool tablet = false}) async {
  if (!MediaQuery.of(context).desktop) {
    await AdaptiveDialog.show<void>(context,
        builder: (context) => builder(context, true));
    return;
  }
  final overlay = Navigator.of(context).overlay?.context.findRenderObject();
  final anchorContext = anchor ?? context;
  final box = anchorContext.findRenderObject();
  if (overlay is! RenderBox || box is! RenderBox || !box.hasSize) {
    await AdaptiveDialog.show<void>(context,
        builder: (context) => builder(context, false));
    return;
  }
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (dialogContext, _, __) => ComposerPlusPopover(
        anchor: anchorContext,
        overlay: overlay,
        tablet: tablet,
        child: builder(dialogContext, false)),
  );
}

/// The desktop menu, above [anchor] (the +) and lined up with its left
/// edge.
///
/// Vommet issue 943: opening the menu takes focus from the message box, so
/// on a tablet the on-screen keyboard closes and the box moves down. The
/// menu used to stay where + was with the keyboard up (top left on an iPad
/// in landscape). It now measures + again after every frame in which the
/// screen's size or insets changed, and follows it.
class ComposerPlusPopover extends StatefulWidget {
  const ComposerPlusPopover(
      {required this.anchor,
      required this.overlay,
      required this.child,
      this.tablet = false,
      super.key});

  final BuildContext anchor;
  final RenderBox overlay;
  final Widget child;
  final bool tablet;

  static const double width = 320;
  static const double tabletMinWidth = 360;
  static const double tabletMaxWidth = 440;

  /// On a tablet the menu takes 45% of the screen's shorter side, so it's
  /// the same width in portrait and landscape.
  static double widthFor(Size screen, {required bool tablet}) => tablet
      ? (screen.shortestSide * 0.45).clamp(tabletMinWidth, tabletMaxWidth)
      : width;

  /// Between + and the menu, and between the menu and the screen's edges.
  static const double gap = 8;

  @override
  State<ComposerPlusPopover> createState() => _ComposerPlusPopoverState();
}

class _ComposerPlusPopoverState extends State<ComposerPlusPopover> {
  /// Where + is, in the overlay's coordinates.
  Rect? anchorRect;

  @override
  void initState() {
    super.initState();
    anchorRect = measure();
  }

  Rect? measure() {
    if (!widget.anchor.mounted || !widget.overlay.attached) return null;
    final box = widget.anchor.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: widget.overlay) & box.size;
  }

  void remeasure() {
    if (!mounted) return;
    final rect = measure();
    if (rect != null && rect != anchorRect) setState(() => anchorRect = rect);
  }

  @override
  Widget build(BuildContext context) {
    // Depending on these rebuilds this while the keyboard slides away or the
    // window changes size; + has its new place once that frame is laid out.
    MediaQuery.viewInsetsOf(context);
    MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top + ComposerPlusPopover.gap;
    WidgetsBinding.instance.addPostFrameCallback((_) => remeasure());

    final rect = anchorRect;
    if (rect == null) return const SizedBox.shrink();
    final size = widget.overlay.size;
    final width = ComposerPlusPopover.widthFor(size, tablet: widget.tablet);
    const gap = ComposerPlusPopover.gap;
    final scheme = Theme.of(context).colorScheme;
    return Stack(children: [
      Positioned(
        left: math.max(gap, math.min(rect.left, size.width - width - gap)),
        bottom: size.height - rect.top + gap,
        child: Material(
          color: scheme.surfaceContainer,
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: width,
                minWidth: width,
                maxHeight: math.max(160, rect.top - gap - top)),
            child: SingleChildScrollView(child: widget.child),
          ),
        ),
      ),
    ]);
  }
}

/// The + inside the message box, with the ring for what's on.
class ComposerPlusButton extends StatelessWidget {
  const ComposerPlusButton(
      {required this.size,
      required this.ring,
      required this.onPressed,
      super.key});

  final double size;
  final ComposerRing ring;
  final void Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inner = size * 0.78;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: inner,
            height: inner,
            child: CustomPaint(
              foregroundPainter: ComposerRingPainter(ring),
              child: Material(
                color: scheme.surfaceContainerHighest,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey("composer-plus"),
                  onTap: onPressed,
                  child: Icon(Icons.add,
                      size: inner * 0.62, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
          if (ring.more > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                key: const ValueKey("composer-plus-ring-more"),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6)),
                child: Text("+${ring.more}",
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface)),
              ),
            ),
        ],
      ),
    );
  }
}

/// One solid ring, or two or three arcs with gaps between them.
class ComposerRingPainter extends CustomPainter {
  ComposerRingPainter(this.ring);

  final ComposerRing ring;

  /// The gap at each end of an arc, in degrees.
  static const double gapDegrees = 9;

  @override
  void paint(Canvas canvas, Size size) {
    if (ring.isEmpty) return;
    const stroke = 2.5;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final n = ring.segments.length;
    if (n == 1) {
      canvas.drawOval(rect, paint..color = ring.segments.first);
      return;
    }
    final each = 2 * math.pi / n;
    final gap = gapDegrees * math.pi / 180;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(rect, -math.pi / 2 + i * each + gap, each - 2 * gap, false,
          paint..color = ring.segments[i]);
    }
  }

  @override
  bool shouldRepaint(ComposerRingPainter oldDelegate) =>
      !_sameRing(oldDelegate.ring, ring);

  static bool _sameRing(ComposerRing a, ComposerRing b) {
    if (a.more != b.more || a.segments.length != b.segments.length) {
      return false;
    }
    for (var i = 0; i < a.segments.length; i++) {
      if (a.segments[i] != b.segments[i]) return false;
    }
    return true;
  }
}

/// Faint names of what's on, in the empty message box ("文A Spanish",
/// "✎ Spanish"); tapping one opens + at IN THIS ROOM.
///
/// Phones show just the colored "文A" / "✎" (in their ring colors): the
/// header toggles already name the language, and the worded pills hid the
/// box's hint.
class ComposerStatePills extends StatelessWidget {
  const ComposerStatePills(
      {required this.states,
      required this.language,
      this.writingLanguage,
      required this.onTap,
      this.compact = false,
      this.colors = const [],
      super.key});

  final List<ComposerRingState> states;

  /// Icons only, no words or outline (phones).
  final bool compact;

  /// Each state's ring color, in [states] order; the compact icons use
  /// them.
  final List<Color> colors;

  /// The room's language ("文A").
  final String? language;

  /// What you write goes out in ("✎").
  final String? writingLanguage;
  final void Function() onTap;

  static String label(ComposerRingState state, String? language) {
    final name = language == null ? null : translationLanguageName(language);
    return "${icon(state)} ${name ?? "Translating"}";
  }

  static String icon(ComposerRingState state) => switch (state) {
        ComposerRingState.reading => "文A",
        ComposerRingState.writing => "✎",
      };

  String _labelFor(ComposerRingState s) =>
      label(s, s == ComposerRingState.writing ? writingLanguage : language);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withAlpha(110);
    if (compact) return _icons(color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in states)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              key: ValueKey("composer-pill-${s.name}"),
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: ShapeDecoration(
                    shape: StadiumBorder(
                        side: BorderSide(color: color.withAlpha(60)))),
                child: Text(_labelFor(s),
                    maxLines: 1,
                    style: TextStyle(fontSize: 11.5, color: color)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _icons(Color fallback) {
    return Semantics(
        button: true,
        label: states.map(_labelFor).join(", "),
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey("composer-pills-compact"),
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, s) in states.indexed)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                    child: Text(icon(s),
                        key: ValueKey("composer-pill-${s.name}"),
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: i < colors.length ? colors[i] : fallback)),
                  ),
              ],
            ),
          ),
        ));
  }
}

/// "🎉 Confetti ×" above the box: the effect the next message goes with.
class ComposerEffectChip extends StatelessWidget {
  const ComposerEffectChip(
      {required this.effect, required this.onClear, super.key});

  final MessageEffectOption effect;
  final void Function() onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
        child: Material(
          key: const ValueKey("composer-effect-chip"),
          color: scheme.primary.withAlpha(40),
          shape: StadiumBorder(side: BorderSide(color: scheme.primary)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text("${effect.emoji} ${effect.label()}",
                  style: TextStyle(fontSize: 12.5, color: scheme.primary)),
              InkWell(
                key: const ValueKey("composer-effect-chip-clear"),
                customBorder: const CircleBorder(),
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: scheme.primary),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
