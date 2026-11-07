import 'package:commet/config/theme_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet: saturation/value square, hue bar, hex field and a row of palette
/// swatches. Every change is reported at once so the theme preview follows.
class ThemeColorPicker extends StatefulWidget {
  const ThemeColorPicker(
      {required this.initial,
      required this.onChanged,
      this.palette = const [],
      super.key});

  final Color initial;
  final ValueChanged<Color> onChanged;
  final List<Color> palette;

  @override
  State<ThemeColorPicker> createState() => _ThemeColorPickerState();
}

class _ThemeColorPickerState extends State<ThemeColorPicker> {
  late HSVColor hsv;
  late TextEditingController hex;

  @override
  void initState() {
    super.initState();
    hsv = HSVColor.fromColor(widget.initial);
    hex = TextEditingController(text: colorToHex(widget.initial));
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  void set(HSVColor value, {bool updateText = true}) {
    setState(() => hsv = value);
    var color = value.toColor();
    if (updateText) hex.text = colorToHex(color);
    widget.onChanged(color);
  }

  void pickSquare(Offset local, Size size) {
    var s = (local.dx / size.width).clamp(0.0, 1.0);
    var v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    set(hsv.withSaturation(s).withValue(v));
  }

  void pickHue(Offset local, double width) {
    var h = (local.dx / width).clamp(0.0, 1.0) * 360;
    set(hsv.withHue(h == 360 ? 0 : h));
  }

  @override
  Widget build(BuildContext context) {
    var colors = Theme.of(context).colorScheme;
    var pure = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();

    return LayoutBuilder(builder: (context, constraints) {
      var width = constraints.maxWidth.isFinite
          ? constraints.maxWidth.clamp(200.0, 360.0)
          : 300.0;
      var squareSize = Size(width, width * 0.55);

      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onPanDown: (d) => pickSquare(d.localPosition, squareSize),
              onPanUpdate: (d) => pickSquare(d.localPosition, squareSize),
              child: SizedBox.fromSize(
                size: squareSize,
                child: Stack(children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient:
                              LinearGradient(colors: [Colors.white, pure])),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black])),
                    ),
                  ),
                  Positioned(
                    left: hsv.saturation * squareSize.width - 8,
                    top: (1 - hsv.value) * squareSize.height - 8,
                    child: IgnorePointer(
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 2)
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onPanDown: (d) => pickHue(d.localPosition, width),
              onPanUpdate: (d) => pickHue(d.localPosition, width),
              child: SizedBox(
                width: width,
                height: 20,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4,
                    height: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: const LinearGradient(colors: [
                          Color(0xffff0000),
                          Color(0xffffff00),
                          Color(0xff00ff00),
                          Color(0xff00ffff),
                          Color(0xff0000ff),
                          Color(0xffff00ff),
                          Color(0xffff0000),
                        ]),
                      ),
                    ),
                  ),
                  Positioned(
                    left: hsv.hue / 360 * width - 9,
                    top: 1,
                    child: IgnorePointer(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: pure,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: hsv.toColor(),
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.onSurface.withAlpha(60)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: hex,
                  style: TextStyle(color: colors.onSurface),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r"[#0-9a-fA-F]")),
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                  onChanged: (text) {
                    var c = colorFromHex(text);
                    if (c != null)
                      set(HSVColor.fromColor(c), updateText: false);
                  },
                ),
              ),
            ]),
            if (widget.palette.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var c in widget.palette)
                  InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    customBorder: const CircleBorder(),
                    onTap: () => set(HSVColor.fromColor(c)),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          width:
                              c.toARGB32() == hsv.toColor().toARGB32() ? 3 : 1,
                          color: c.toARGB32() == hsv.toColor().toARGB32()
                              ? colors.onSurface
                              : colors.onSurface.withAlpha(50),
                        ),
                      ),
                    ),
                  ),
              ]),
            ],
          ],
        ),
      );
    });
  }
}
