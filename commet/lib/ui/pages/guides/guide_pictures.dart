// Vommet: the pictures in guides and Getting started. Drawn with the current
// theme's colours rather than shipped as screenshots, so they never go stale
// and always match the theme in use. A guide asks for one by name with a
// line `[[picture: <name>]]`.
import 'package:flutter/material.dart';

class GuidePicture extends StatelessWidget {
  const GuidePicture(this.name, {this.height = 190, super.key});

  final String name;
  final double height;

  static const names = [
    "overview",
    "spaces",
    "rooms",
    "chat",
    "voice",
    "home",
    "menu",
    "shield",
    "accounts",
  ];

  static const _width = 380.0;
  static const _height = 190.0;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: FittedBox(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: _width,
              height: _height,
              color: c.surfaceContainerLowest,
              child: _build(context, c),
            ),
          ),
        ),
      ),
    );
  }

  Widget _build(BuildContext context, ColorScheme c) {
    switch (name) {
      case "overview":
        return _App(c, ring: null, labels: true);
      case "spaces":
        return _App(c, ring: _Ring.space, bubble: "Your spaces");
      case "rooms":
        return _App(c, ring: _Ring.spaceName, bubble: "All of its rooms");
      case "home":
        return _App(c, ring: _Ring.home, bubble: "Home: direct messages");
      case "chat":
        return _Chat(c);
      case "voice":
        return _Voice(c);
      case "menu":
        return _Menu(c);
      case "shield":
        return _Shield(c);
      case "accounts":
        return _Accounts(c);
    }
    return const SizedBox();
  }
}

const _ringColor = Color(0xFFFFC94D);

enum _Ring { space, spaceName, home }

Widget _ringed(bool on, Widget child, {double radius = 10}) {
  if (!on) return child;
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius + 3),
      border: Border.all(color: _ringColor, width: 2.5),
    ),
    padding: const EdgeInsets.all(2),
    child: child,
  );
}

Widget _bar(Color color, double width, {double height = 7}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(height / 2)),
    );

Widget _icon(Color color,
        {double size = 26, double radius = 13, Widget? child}) =>
    Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(radius)),
      child: child,
    );

Widget _label(String text, {Color color = _ringColor, double size = 11}) =>
    Text(text,
        // Any font fits: a long label ends in "…" instead of overflowing.
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: FontWeight.w700,
            height: 1.2));

/// A voice room's name with its speaker icon.
Widget _voiceLabel(String text, {required Color color, double size = 11}) =>
    Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
      Icon(Icons.volume_up, size: size + 1, color: color),
      Flexible(child: _label(text, color: color, size: size)),
    ]);

/// A small app window: space icons, a room list and a chat.
class _App extends StatelessWidget {
  const _App(this.c, {this.ring, this.labels = false, this.bubble});

  final ColorScheme c;
  final _Ring? ring;
  final bool labels;
  final String? bubble;

  @override
  Widget build(BuildContext context) {
    final dim = c.onSurface.withAlpha(60);
    final faint = c.onSurface.withAlpha(30);
    final spaces = [
      const Color(0xFF3D7A5A),
      const Color(0xFF8A4FBF),
      const Color(0xFFB56A2C),
    ];
    return Stack(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 48,
          color: c.surfaceContainerLowest,
          padding: const EdgeInsets.only(top: 8),
          child: Column(spacing: 5, children: [
            _ringed(
                ring == _Ring.home,
                _icon(c.primary,
                    size: 22,
                    radius: 8,
                    child: Icon(Icons.home, size: 15, color: c.onPrimary))),
            _bar(faint, 18, height: 2),
            for (final (i, color) in spaces.indexed)
              _ringed(ring == _Ring.space && i < 3,
                  _icon(color, size: 22, radius: 11)),
            _icon(c.surfaceContainerHigh,
                size: 22,
                radius: 11,
                child: Icon(Icons.add, size: 15, color: Colors.green)),
          ]),
        ),
        Container(
          width: 120,
          color: c.surfaceContainer,
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                _ringed(
                    ring == _Ring.spaceName,
                    radius: 4,
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child:
                          _label("Pine Hollow", color: c.onSurface, size: 11.5),
                    )),
                for (final room in ["general", "art-share", "gaming"])
                  _label("# $room",
                      color: c.onSurface.withAlpha(170), size: 10.5),
                _voiceLabel("Hangout",
                    color: c.onSurface.withAlpha(170), size: 10.5),
              ]),
        ),
        Expanded(
          child: Container(
            color: c.surface,
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  for (final (w1, w2) in [
                    (50.0, 120.0),
                    (40.0, 90.0),
                    (56.0, 140.0)
                  ])
                    Row(spacing: 8, children: [
                      _icon(dim, size: 20, radius: 10),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 4,
                          children: [_bar(dim, w1), _bar(faint, w2)]),
                    ]),
                ]),
          ),
        ),
      ]),
      if (labels) ...[
        Positioned(left: 4, bottom: 8, child: _label("Spaces", size: 10)),
        Positioned(left: 56, bottom: 8, child: _label("Rooms", size: 10)),
        Positioned(right: 12, bottom: 8, child: _label("Chat", size: 10)),
      ],
      if (bubble != null)
        Positioned(
          // Beside the rooms, pointing back at what is ringed.
          left: 176,
          top: ring == _Ring.home ? 8 : (ring == _Ring.spaceName ? 6 : 64),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
                color: _ringColor, borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
              const Icon(Icons.arrow_back, size: 12, color: Colors.black87),
              _label(bubble!, color: Colors.black87, size: 11),
            ]),
          ),
        ),
    ]);
  }
}

/// A message with a reply, reactions and a thread.
class _Chat extends StatelessWidget {
  const _Chat(this.c);
  final ColorScheme c;

  @override
  Widget build(BuildContext context) {
    final text = c.onSurface;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.all(14),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Row(spacing: 8, children: [
              _icon(const Color(0xFF3D7A5A), size: 26),
              Flexible(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _label("mossfox", color: text, size: 11.5),
                    _label("anyone up for drawing night?",
                        color: text.withAlpha(200), size: 11),
                  ])),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Row(spacing: 5, children: [
                for (final r in ["🎨 3", "👍 2"])
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: c.primary.withAlpha(50),
                        border: Border.all(color: c.primary.withAlpha(140)),
                        borderRadius: BorderRadius.circular(8)),
                    child: _label(r, color: text, size: 10),
                  ),
                const SizedBox(width: 6),
                _label("Reactions", size: 10),
              ]),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Row(spacing: 6, children: [
                Container(width: 2, height: 14, color: text.withAlpha(90)),
                Flexible(
                  child: _label("mossfox: anyone up for drawing…",
                      color: text.withAlpha(140), size: 10),
                ),
                _label("← a reply", size: 10),
              ]),
            ),
            Row(spacing: 8, children: [
              _icon(const Color(0xFFB56A2C), size: 26),
              Flexible(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _label("tinbird", color: text, size: 11.5),
                    _label("yes!! hangout at 8?",
                        color: text.withAlpha(200), size: 11),
                  ])),
            ]),
            const Spacer(),
            Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                  color: c.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8)),
              child: _label("Message #general",
                  color: text.withAlpha(110), size: 10.5),
            ),
          ]),
    );
  }
}

/// A voice room in the room list with the people in it.
class _Voice extends StatelessWidget {
  const _Voice(this.c);
  final ColorScheme c;

  @override
  Widget build(BuildContext context) {
    final text = c.onSurface;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 170,
        color: c.surfaceContainer,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 7,
            children: [
              _label("# general", color: text.withAlpha(170), size: 10.5),
              _ringed(
                  true,
                  radius: 4,
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: _voiceLabel("Hangout", color: text, size: 11),
                  )),
              for (final (name, color, talking) in [
                ("mossfox", const Color(0xFF3D7A5A), true),
                ("tinbird", const Color(0xFFB56A2C), false),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Row(spacing: 6, children: [
                    Container(
                      decoration: talking
                          ? BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.green, width: 2))
                          : null,
                      child: _icon(color, size: 18, radius: 9),
                    ),
                    Flexible(
                        child:
                            _label(name, color: text.withAlpha(200), size: 10)),
                  ]),
                ),
            ]),
      ),
      Expanded(
        child: Container(
          color: c.surface,
          padding: const EdgeInsets.all(14),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: [
                _label("Click a voice room to join.\nNobody gets rung.",
                    size: 12),
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 8,
                    children: [
                      for (final i in [
                        Icons.mic,
                        Icons.videocam,
                        Icons.screen_share,
                      ])
                        _icon(c.surfaceContainerHigh,
                            size: 30,
                            radius: 15,
                            child: Icon(i, size: 16, color: text)),
                      _icon(Colors.red.shade700,
                          size: 30,
                          radius: 15,
                          child: const Icon(Icons.call_end,
                              size: 16, color: Colors.white)),
                    ]),
              ]),
        ),
      ),
    ]);
  }
}

/// A right-click menu with its help item highlighted.
class _Menu extends StatelessWidget {
  const _Menu(this.c);
  final ColorScheme c;

  @override
  Widget build(BuildContext context) {
    final text = c.onSurface;
    Widget item(IconData icon, String label, {bool on = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
              color: on ? c.primary : null,
              borderRadius: BorderRadius.circular(4)),
          child: Row(spacing: 8, children: [
            Icon(icon, size: 13, color: on ? c.onPrimary : text),
            Flexible(
                child:
                    _label(label, color: on ? c.onPrimary : text, size: 10.5)),
          ]),
        );
    return Stack(children: [
      Positioned.fill(child: _App(c)),
      Positioned(
        left: 40,
        top: 54,
        child: Container(
          width: 170,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
              color: c.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: c.surfaceContainerHigh),
              boxShadow: const [
                BoxShadow(blurRadius: 12, color: Colors.black45)
              ]),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            item(Icons.visibility, "Mark as read"),
            item(Icons.settings, "Space settings"),
            Divider(height: 8, color: c.surfaceContainerHigh),
            item(Icons.help_outline, "What's a space?", on: true),
          ]),
        ),
      ),
      Positioned(
        left: 220,
        top: 120,
        child: _label("Right-click, or press\nand hold on a phone", size: 12),
      ),
    ]);
  }
}

/// The icons after a room's name that say whether it is encrypted
/// (EncryptionMarker): none when it is, and the exceptions.
class _Shield extends StatelessWidget {
  const _Shield(this.c);
  final ColorScheme c;

  @override
  Widget build(BuildContext context) {
    final text = c.onSurface;
    Widget row(String name, IconData? icon, Color? color, String note) =>
        Row(spacing: 6, children: [
          SizedBox(
              width: 120,
              child: Row(spacing: 4, children: [
                Flexible(child: _label(name, color: text, size: 11)),
                if (icon != null) Icon(icon, size: 13, color: color),
              ])),
          Flexible(
              child: _label(note,
                  color: color ?? text.withAlpha(170), size: 10.5)),
        ]);
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(22, 14, 14, 14),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 13,
          children: [
            row("# general", null, null, "No icon: encrypted"),
            row("# lobby", Icons.no_encryption_outlined, text.withAlpha(150),
                "Gray: not encrypted"),
            row("mossfox", Icons.verified_user, Colors.green.shade400,
                "Green: you verified them"),
            row("bot", Icons.no_encryption_outlined, Colors.orange.shade300,
                "Amber: a chat that isn't encrypted"),
            row("tinbird", Icons.gpp_maybe, Colors.red.shade400,
                "Red: their identity changed"),
          ]),
    );
  }
}

/// Accounts on different homeservers talking to each other.
class _Accounts extends StatelessWidget {
  const _Accounts(this.c);
  final ColorScheme c;

  @override
  Widget build(BuildContext context) {
    final text = c.onSurface;
    Widget server(String name, String user, Color color) => Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            _icon(color,
                size: 48,
                radius: 10,
                child: const Icon(Icons.dns, color: Colors.white, size: 24)),
            _label(name, color: text, size: 11),
            _label(user, color: text.withAlpha(170), size: 10),
          ],
        );
    return Container(
      color: c.surface,
      padding: const EdgeInsets.all(16),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        Flexible(
            child: server("example.org", "@mossfox:example.org",
                const Color(0xFF3D7A5A))),
        Column(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          Icon(Icons.sync_alt, color: _ringColor, size: 26),
          _label("They talk\nto each other", size: 10.5),
        ]),
        Flexible(
            child: server("chat.example", "@tinbird:chat.example",
                const Color(0xFF8A4FBF))),
      ]),
    );
  }
}
