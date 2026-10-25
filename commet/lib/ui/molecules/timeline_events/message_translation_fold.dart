import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:flutter/material.dart';

/// On-device translation under a message (Vommet issue 680): a "Translate"
/// pill at the end of a message in another language; tapping it shows the
/// translation under the original, behind a divider, with a caption and a
/// chevron that folds it away again, like a voice message transcript.
///
/// [wrap] leaves [child] alone where translation can't run (web, Windows,
/// macOS, iOS, Android before 9, CPUs without SSE4.2).
class MessageTranslationFold extends StatefulWidget {
  const MessageTranslationFold({
    required this.eventId,
    required this.text,
    required this.child,
    this.translation,
    this.confirmDownload = askToDownload,
    super.key,
  });

  final String eventId;
  final String text;
  final Widget child;

  /// Defaults to [MessageTranslation.instance].
  final MessageTranslation? translation;

  /// Asks before the first download from a language; tests answer it.
  final Future<bool?> Function(
      BuildContext context, String title, String prompt) confirmDownload;

  /// [child] with a Translate pill when [text] is in a language we can
  /// translate; [child] unchanged otherwise.
  static Widget wrap({
    required String eventId,
    required String text,
    required Widget child,
    MessageTranslation? translation,
    Future<bool?> Function(BuildContext context, String title, String prompt)
        confirmDownload = askToDownload,
  }) {
    final t = translation ?? MessageTranslation.instance;
    if (!t.supported || text.trim().isEmpty) return child;
    return MessageTranslationFold(
        eventId: eventId,
        text: text,
        translation: t,
        confirmDownload: confirmDownload,
        child: child);
  }

  @override
  State<MessageTranslationFold> createState() => _MessageTranslationFoldState();
}

class _MessageTranslationFoldState extends State<MessageTranslationFold> {
  late MessageTranslation translation;
  late ValueNotifier<TranslationState> state;
  String? language;
  bool collapsed = false;

  /// Edits change the text, so the key covers it too.
  String get key => "${widget.eventId}\u0000${widget.text.hashCode}";

  @override
  void initState() {
    super.initState();
    translation = widget.translation ?? MessageTranslation.instance;
    bind();
  }

  @override
  void didUpdateWidget(MessageTranslationFold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId || oldWidget.text != widget.text) {
      bind();
    }
  }

  void bind() {
    language = translation.translatableLanguage(key, widget.text);
    state = translation.stateFor(key);
  }

  Future<void> start() async {
    final from = language;
    if (from == null) return;
    final to = translation.targetLanguage;
    final route = translation.route(from, to);
    if (route == null) return;
    final missing = await translation.missingModels(route);
    if (missing.isNotEmpty) {
      if (!mounted) return;
      final ok = await widget.confirmDownload(
          context,
          "Download the ${translationLanguageName(from)} language model?",
          downloadPrompt(from, to, missing));
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => collapsed = false);
    await translation.translate(key, widget.text, from);
  }

  void onPill(TranslationState value) {
    switch (value) {
      case TranslationDownloading() || TranslationRunning():
        translation.cancel(key);
      case TranslationDone():
        setState(() => collapsed = false);
      case TranslationIdle() || TranslationFailed():
        start();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (language == null) return widget.child;
    return ValueListenableBuilder<TranslationState>(
      valueListenable: state,
      builder: (context, value, _) {
        if (value case TranslationDone(:final text, :final from, :final to)
            when !collapsed) {
          return translated(text, from, to);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: widget.child),
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: TranslatePill(
                      state: value, onPressed: () => onPill(value)),
                ),
              ],
            ),
            if (value case TranslationFailed(:final message))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        );
      },
    );
  }

  Widget translated(String text, String from, String to) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.child,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ),
        SelectableText(text, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                "${translationLanguageName(from)} → ${translationLanguageName(to)}"
                " · translated on this device",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: "Hide translation",
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => collapsed = true),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      shape: BoxShape.circle),
                  child: Icon(Icons.keyboard_arrow_up,
                      size: 18, color: scheme.onSurface),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<bool?> askToDownload(
        BuildContext context, String title, String prompt) =>
    AdaptiveDialog.confirmation(context,
        title: title,
        prompt: prompt,
        confirmationText: "Download",
        cancelText: "Cancel");

/// The dialog text before the first translation from a language.
String downloadPrompt(
    String from, String to, List<TranslationModelSpec> missing) {
  final size = formatModelSize(missing.fold(0, (sum, s) => sum + s.bytes));
  final what = missing.length == 1
      ? "a language model ($size)"
      : "${missing.length} language models ($size, through English)";
  return "Translation runs on this device, so messages never leave it. "
      "Translating ${translationLanguageName(from)} into "
      "${translationLanguageName(to)} needs $what, downloaded once from "
      "Mozilla (the models Firefox uses). You can delete it later in Settings, under Translation.";
}

String formatModelSize(int bytes) {
  final mb = bytes / 1000000;
  return mb >= 10 ? "${mb.round()} MB" : "${mb.toStringAsFixed(1)} MB";
}

/// "Translate" in a rounded pill; while busy it shows progress and cancels.
class TranslatePill extends StatelessWidget {
  const TranslatePill(
      {required this.state, required this.onPressed, super.key});

  final TranslationState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    final (String label, String tooltip, double? progress, bool busy) =
        switch (state) {
      TranslationDownloading(:final progress) => (
          progress == null ? "Downloading" : "${(progress * 100).round()}%",
          "Cancel the download",
          progress,
          true
        ),
      TranslationRunning() => ("Translating", "Cancel", null, true),
      TranslationDone() => (
          "Show translation",
          "Show translation",
          null,
          false
        ),
      _ => ("Translate", "Translate on this device", null, false),
    };
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, value: progress, color: scheme.primary),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(label, style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
