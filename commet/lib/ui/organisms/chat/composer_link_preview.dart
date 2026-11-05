import 'dart:async';

import 'package:commet/client/components/url_preview/link_preview_fetcher.dart';
import 'package:commet/client/components/url_preview/outgoing_url_preview.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 676 phase 2: the preview for the link in the message box.
/// After a short pause in typing, this device fetches the page (like
/// Signal); the bar above the box shows the result with an × to drop it,
/// and sending attaches it to the message (MSC4095).
class ComposerLinkPreview extends ChangeNotifier {
  ComposerLinkPreview({
    this.delay = const Duration(milliseconds: 800),
    Future<OutgoingUrlPreview?> Function(Uri url)? fetch,
    bool Function()? enabled,
  })  : _fetch = fetch ?? fetchOutgoingUrlPreview,
        _enabled = enabled ??
            (() =>
                canMakeLinkPreviews &&
                preferences.bundledUrlPreviewsAttach.value);

  final Duration delay;
  final Future<OutgoingUrlPreview?> Function(Uri url) _fetch;
  final bool Function() _enabled;

  /// Fetched previews by link, so editing the text around a link doesn't
  /// fetch it again. Null = the page gave nothing.
  final Map<String, OutgoingUrlPreview?> _results = {};
  final Set<String> _dismissed = {};

  Uri? _link;
  Timer? _timer;
  bool _disposed = false;

  /// The link the box would preview, while a preview is wanted for it.
  Uri? get link => _link;

  /// The preview ready to send, if any.
  OutgoingUrlPreview? get preview =>
      _link == null ? null : _results[_link.toString()];

  /// Waiting for the pause or the page.
  bool get loading => _link != null && !_results.containsKey("$_link");

  /// Call with the box's text whenever it changes.
  void update(String text) {
    final link = _enabled() ? OutgoingUrlPreview.linkFor(text) : null;
    final wanted = link != null && !_dismissed.contains(link.toString());
    final next = wanted ? link : null;
    if (next == _link) return;

    _timer?.cancel();
    _link = next;
    if (next != null && !_results.containsKey(next.toString())) {
      _timer = Timer(delay, () => _load(next));
    }
    _notify();
  }

  Future<void> _load(Uri link) async {
    final key = link.toString();
    if (_results.containsKey(key)) return;
    OutgoingUrlPreview? result;
    try {
      result = await _fetch(link);
    } catch (_) {
      result = null;
    }
    if (_disposed) return;
    if (_results.length > 20) _results.clear();
    _results[key] = result;
    if (_link == link) _notify();
  }

  /// The × on the bar: this message goes without a preview for this link.
  void dismiss() {
    final link = _link;
    if (link == null) return;
    _dismissed.add(link.toString());
    _timer?.cancel();
    _link = null;
    _notify();
  }

  /// The preview to attach to [message], then a fresh start for the next
  /// one. Null when none is ready for the link [message] previews.
  List<OutgoingUrlPreview>? takeForSend(String message) {
    final ready = preview;
    clear();
    if (ready == null || !ready.hasData) return null;
    if (OutgoingUrlPreview.linkFor(message) != ready.matchedUrl) return null;
    return [ready];
  }

  void clear() {
    _timer?.cancel();
    _link = null;
    _dismissed.clear();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// The bar above the message box with the preview that will be attached.
class ComposerLinkPreviewBar extends StatelessWidget {
  const ComposerLinkPreviewBar({required this.preview, super.key});

  final ComposerLinkPreview preview;

  static String get labelMakingLinkPreview =>
      Intl.message("Making link preview…",
          desc: "Shown above the message box while this device builds the "
              "preview it will attach for a link",
          name: "labelMakingLinkPreview");

  static String get promptDropLinkPreview =>
      Intl.message("Send without preview",
          desc: "Tooltip of the × on the link preview above the message box",
          name: "promptDropLinkPreview");

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preview,
      builder: (context, _) {
        final link = preview.link;
        final ready = preview.preview;
        if (link == null || (!preview.loading && ready == null)) {
          return const SizedBox.shrink();
        }
        return _bar(context, link, ready);
      },
    );
  }

  Widget _bar(BuildContext context, Uri link, OutgoingUrlPreview? ready) {
    final colors = Theme.of(context).colorScheme;
    final image = ready?.image;
    final title = ready?.title ?? ready?.siteName ?? link.host;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
        child: Row(
          children: [
            Icon(Icons.link, color: colors.primary),
            const SizedBox(width: 8),
            if (image != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(image.bytes,
                      width: 36, height: 36, fit: BoxFit.cover),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  tiamat.Text.labelEmphasised(
                      ready == null ? labelMakingLinkPreview : title,
                      color: colors.primary,
                      overflow: TextOverflow.ellipsis),
                  tiamat.Text.labelLow(link.host,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              tooltip: promptDropLinkPreview,
              icon: const Icon(Icons.close),
              onPressed: preview.dismiss,
            ),
          ],
        ),
      ),
    );
  }
}
