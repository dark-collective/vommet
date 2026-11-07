import 'package:commet/client/components/threads/thread_preview_content.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: what a thread card previews (Settings › Appearance › Threads).
enum ThreadPreviewMode {
  latest("Latest reply"),
  first("First reply"),
  both("First and latest reply");

  const ThreadPreviewMode(this.label);
  final String label;

  static ThreadPreviewMode parse(String value) =>
      ThreadPreviewMode.values.firstWhere((m) => m.name == value,
          orElse: () => ThreadPreviewMode.latest);
}

/// One reply shown on a [ThreadCard].
class ThreadCardReply {
  const ThreadCardReply({
    required this.senderName,
    required this.body,
    required this.time,
    required this.maxLines,
    this.senderId,
    this.senderColor,
    this.senderAvatar,
  });

  final String senderName;

  /// Who sent it, for redacted mode; falls back to [senderName].
  final String? senderId;
  final Color? senderColor;
  final ImageProvider? senderAvatar;
  final String body;
  final String time;

  /// The body is cut after this many lines; the last one fades out.
  final int maxLines;
}

/// A person on a [ThreadCard]'s stack of recent repliers.
class ThreadCardFace {
  const ThreadCardFace({required this.name, this.id, this.color, this.avatar});
  final String name;

  /// Who it is, for redacted mode; falls back to [name].
  final String? id;
  final Color? color;
  final ImageProvider? avatar;
}

/// Vommet: the card under a message that started a thread (Discord-style):
/// reply count, recent repliers and when the last reply came, then one or
/// two replies cut off with a fade. Tapping it opens the thread.
class ThreadCard extends StatelessWidget {
  const ThreadCard({
    required this.replyCount,
    required this.replies,
    this.faces = const [],
    this.emptyLabel,
    this.onTap,
    super.key,
  });

  final int? replyCount;
  final String? emptyLabel;
  final List<ThreadCardFace> faces;

  /// Shown top to bottom with a divider between them.
  final List<ThreadCardReply> replies;
  final VoidCallback? onTap;

  // Vommet issue 982: the server aggregate is not a message-only count.
  static String countLabel(int count) => threadEventCount(count);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          key: const ValueKey("thread-card"),
          color: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          // Vommet issue 695: inside the desktop timeline's SelectionArea the
          // card's Text would show the text cursor over the InkWell's hand.
          child: SelectionContainer.disabled(
              child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  const SizedBox(height: 6),
                  Text(
                      replies.isEmpty
                          ? (emptyLabel ?? threadPreviewUnavailable)
                          : threadPreviewSample,
                      style: Theme.of(context).textTheme.labelSmall),
                  for (final (i, reply) in replies.indexed) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1, color: scheme.outlineVariant),
                      )
                    else
                      const SizedBox(height: 8),
                    _reply(context, reply),
                  ],
                ],
              ),
            ),
          )),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = faces.take(3).toList();
    return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Icon(Icons.forum_rounded, size: 16, color: scheme.primary),
          Text(
              replyCount == null
                  ? threadActivityLabel
                  : countLabel(replyCount!),
              style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary, fontWeight: FontWeight.w700)),
          if (shown.isNotEmpty) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 20.0 + (shown.length - 1) * 12,
              height: 20,
              child: Stack(children: [
                for (final (i, face) in shown.indexed)
                  Positioned(
                    left: i * 12.0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: scheme.surfaceContainerHigh, width: 2),
                      ),
                      child: tiamat.Avatar(
                        image: face.avatar,
                        placeholderText: face.name,
                        placeholderColor: face.color,
                        redactionKey: face.id ?? face.name,
                        radius: 8,
                      ),
                    ),
                  ),
              ]),
            ),
          ],
          Icon(Icons.chevron_right_rounded,
              size: 18, color: scheme.onSurfaceVariant),
        ]);
  }

  Widget _reply(BuildContext context, ThreadCardReply reply) {
    final theme = Theme.of(context);
    final redaction = RedactionScope.of(context);
    final id = reply.senderId ?? reply.senderName;
    final color = redaction.redactsNames
        ? redaction.identityColor(id)
        : reply.senderColor;
    final bodyStyle = redaction.drawsTextAsBars
        ? redaction.redactedTextStyle(
            theme.textTheme.bodyMedium!.copyWith(height: 1.35),
            theme.colorScheme.onSurface.withAlpha(90))
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          tiamat.Avatar(
            image: reply.senderAvatar,
            placeholderText: reply.senderName,
            placeholderColor: reply.senderColor,
            redactionKey: id,
            radius: 9,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: tiamat.Text(
              redaction.name(reply.senderName, id),
              color: color,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              autoAdjustBrightness: true,
            ),
          ),
          const SizedBox(width: 6),
          Text(reply.time,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 3),
        FadedText(redaction.text(reply.body),
            maxLines: reply.maxLines, style: bodyStyle),
      ],
    );
  }
}

/// Text cut after [maxLines] lines; when it is cut, the last line fades out
/// so it reads as cut off rather than finished.
class FadedText extends StatelessWidget {
  const FadedText(this.text, {required this.maxLines, this.style, super.key});
  final String text;
  final int maxLines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = this.style ??
        Theme.of(context).textTheme.bodyMedium!.copyWith(height: 1.35);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: maxLines,
      )..layout(maxWidth: box.maxWidth);
      final cut = painter.didExceedMaxLines;
      painter.dispose();
      final child = Text(text,
          maxLines: maxLines,
          overflow: TextOverflow.clip,
          softWrap: true,
          style: style);
      if (!cut) return child;
      final solid = 1 - 1 / maxLines;
      return ShaderMask(
        key: const ValueKey("thread-card-fade"),
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.white, Colors.white, Color(0x33FFFFFF)],
          stops: [0, solid, 1],
        ).createShader(rect),
        child: child,
      );
    });
  }
}
