// Vommet: a small picture of each chat layout for the onboarding layout page
// (Vommet issue 524), drawn in the current theme's colours.
import 'package:flutter/material.dart';

class LayoutPreview extends StatelessWidget {
  const LayoutPreview(
      {required this.unified,
      this.bubbles = false,
      this.roomsButton = false,
      this.peopleButton = false,
      super.key});

  /// The Telegram-style unified chat list, else the space rail and Home.
  final bool unified;

  /// Vommet: the messages as chat bubbles (Settings › Appearance › Layout).
  final bool bubbles;

  /// Vommet: the rail's # "Standalone rooms" button under Home.
  final bool roomsButton;

  /// Vommet: the rail's People button under Home (New Home), above the #.
  final bool peopleButton;

  /// The size it's drawn at before scaling.
  static const size = Size(320, 180);
  static const double maxHeight = 200;

  static const _faces = [
    Color(0xff7fd1a8),
    Color(0xffc58cff),
    Color(0xffffb86b),
    Color(0xff6bb8ff),
    Color(0xffff7f9f),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Drawn at one size and scaled to fit, so it looks the same on a phone
    // and in a wide window.
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: maxHeight),
      child: AspectRatio(
        aspectRatio: size.aspectRatio,
        child: Container(
          // A frame, so the picture stands out from the card behind it.
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FittedBox(
              child: SizedBox.fromSize(
                size: size,
                child: Container(
                  key: ValueKey(
                      "layout-preview-${unified ? "telegram" : "discord"}"),
                  color: scheme.surface,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: unified
                        ? [
                            Expanded(flex: 4, child: _chatList(scheme)),
                            Expanded(flex: 6, child: _chat(scheme)),
                          ]
                        : [
                            _rail(scheme),
                            Expanded(flex: 3, child: _roomList(scheme)),
                            Expanded(flex: 6, child: _chat(scheme)),
                          ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _bar(Color color, double width, {double height = 5}) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(height / 2)),
      );

  Widget _dot(Color color, double size, {double radius = 0.5}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(size * radius)),
      );

  /// Cut off at the bottom on small cards instead of overflowing.
  Widget _clipped(Widget child) => SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(), child: child);

  Widget _rail(ColorScheme scheme) => Container(
        width: 30,
        color: scheme.surfaceContainerLowest,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _clipped(Column(
          spacing: 6,
          children: [
            _dot(scheme.primary, 18, radius: 0.3),
            if (peopleButton)
              _railButton(scheme, Icons.people_alt_rounded,
                  const ValueKey("layout-preview-people-button")),
            if (roomsButton)
              _railButton(scheme, Icons.tag,
                  const ValueKey("layout-preview-rooms-button")),
            Container(width: 12, height: 1.5, color: scheme.outlineVariant),
            for (final c in _faces.take(4)) _dot(c, 18, radius: 0.3),
          ],
        )),
      );

  Widget _railButton(ColorScheme scheme, IconData icon, Key key) => Container(
        key: key,
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18 * 0.3)),
        child: Icon(icon, size: 12, color: scheme.onSurface),
      );

  Widget _roomList(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerLow,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: _clipped(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 7,
          children: [
            _bar(scheme.onSurface.withAlpha(150), 44, height: 6),
            const SizedBox(height: 2),
            for (final w in [38.0, 30.0, 42.0, 26.0, 34.0])
              Row(spacing: 4, children: [
                Text("#",
                    style: TextStyle(
                        fontSize: 8,
                        height: 1,
                        color: scheme.onSurfaceVariant.withAlpha(160))),
                _bar(scheme.onSurfaceVariant.withAlpha(120), w),
              ]),
          ],
        )),
      );

  Widget _chatList(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerLow,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: _clipped(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 7,
          children: [
            for (var i = 0; i < 5; i++)
              Row(spacing: 6, children: [
                _dot(_faces[i], 16, radius: i == 2 ? 0.3 : 0.5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      _bar(scheme.onSurface.withAlpha(150), 34.0 + (i % 3) * 8,
                          height: 4.5),
                      _bar(scheme.onSurfaceVariant.withAlpha(90),
                          48.0 - (i % 2) * 12,
                          height: 3.5),
                    ],
                  ),
                ),
              ]),
          ],
        )),
      );

  Widget _chat(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
                child: bubbles
                    ? _bubbles(scheme)
                    : _clipped(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            for (var i = 0; i < 3; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: 6,
                                  children: [
                                    _dot(_faces[(i * 2) % _faces.length], 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        spacing: 3,
                                        children: [
                                          _bar(
                                              _faces[(i * 2) % _faces.length]
                                                  .withAlpha(200),
                                              26,
                                              height: 4),
                                          _bar(
                                              scheme.onSurfaceVariant
                                                  .withAlpha(110),
                                              70.0 - i * 14),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ]))),
            Container(
              height: 14,
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(7)),
            ),
          ],
        ),
      );

  /// Others' bubbles on the left, yours on the right.
  Widget _bubbles(ColorScheme scheme) {
    final own = Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.45), scheme.surface);
    Widget bubble(Color color, double width, bool mine) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              width: width,
              height: 14,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(7)),
            ),
          ),
        );
    return _clipped(Column(children: [
      bubble(scheme.surfaceContainerHighest, 78, false),
      bubble(own, 56, true),
      bubble(scheme.surfaceContainerHighest, 96, false),
      bubble(own, 40, true),
    ]));
  }
}
