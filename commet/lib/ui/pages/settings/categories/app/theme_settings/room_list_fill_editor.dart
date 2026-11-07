import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/config/style/room_list_fill.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// Vommet issue 1194: bounded controls for the named navigation surface.
class RoomListFillEditor extends StatelessWidget {
  const RoomListFillEditor(
      {required this.fill,
      required this.onChanged,
      required this.preview,
      super.key});
  final RoomListFill? fill;
  final ThemeData preview;
  final ValueChanged<RoomListFill?> onChanged;

  String get title => Intl.message('Room list fill', name: 'roomListFillTitle');
  String get solid => Intl.message('Solid', name: 'roomListFillSolid');
  String get gradient => Intl.message('Gradient', name: 'roomListFillGradient');
  String get colorLabel => Intl.message('Color', name: 'roomListFillColor');
  String get position => Intl.message('Position', name: 'roomListFillPosition');
  String get direction =>
      Intl.message('Direction', name: 'roomListFillDirection');
  String get opacity => Intl.message('Opacity', name: 'roomListFillOpacity');
  String get add => Intl.message('Add color', name: 'roomListFillAdd');
  String get remove => Intl.message('Remove color', name: 'roomListFillRemove');
  String get done => Intl.message('Done', name: 'roomListFillDone');
  String get contrast => Intl.message(
      'Room list contrast may be low. Check text, icons and selected rows.',
      name: 'roomListFillContrast');
  String get transparency => Intl.message(
      'Transparent fills depend on the window background. Image contrast cannot be guaranteed.',
      name: 'roomListFillTransparency');

  static List<double> even(int count) =>
      [for (var i = 0; i < count; i++) i / (count - 1)];

  Future<void> edit(BuildContext context, int index) async {
    final value = fill!;
    await AdaptiveDialog.show(context,
        title: colorLabel,
        builder: (dialog) => SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ThemeColorPicker(
                  initial: value.colors[index],
                  onChanged: (color) {
                    final colors = List<Color>.of(value.colors)
                      ..[index] = color;
                    onChanged(value.copyWith(colors: colors));
                  }),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (value.colors.length > 2)
                  TextButton(
                      onPressed: () {
                        final colors = List<Color>.of(value.colors)
                          ..removeAt(index);
                        onChanged(value.copyWith(
                            colors: colors, stops: even(colors.length)));
                        Navigator.of(dialog).pop();
                      },
                      child: Text(remove)),
                TextButton(
                    onPressed: () => Navigator.of(dialog).pop(),
                    child: Text(done)),
              ]),
            ])));
  }

  bool lowContrast(RoomListFill value) {
    final window = preview.extension<FoundationSettings>();
    final base = window?.color ?? preview.colorScheme.surfaceDim;
    final backdrops = <Color>[base];
    final windowGradient = window?.gradient;
    if (windowGradient is LinearGradient) {
      for (var i = 0; i < windowGradient.colors.length - 1; i++) {
        for (var step = 0; step <= 16; step++) {
          backdrops.add(Color.alphaBlend(
              Color.lerp(windowGradient.colors[i], windowGradient.colors[i + 1],
                  step / 16)!,
              base));
        }
      }
    }
    final inks = [
      preview.colorScheme.onSurface,
      preview.colorScheme.secondary,
      preview.iconTheme.color ?? preview.colorScheme.secondary
    ];
    // Bounded editor-only sampling includes interiors, not just stop colors.
    for (var segment = 0; segment < value.colors.length - 1; segment++) {
      for (var step = 0; step <= 16; step++) {
        final sample = Color.lerp(
            value.colors[segment], value.colors[segment + 1], step / 16)!;
        for (final backdrop in backdrops) {
          final bg = Color.alphaBlend(
              sample.withValues(alpha: sample.a * value.opacity), backdrop);
          for (final ink in inks) {
            final a = ink.computeLuminance(), b = bg.computeLuminance();
            if (((a > b ? a : b) + .05) / ((a > b ? b : a) + .05) < 4.5)
              return true;
          }
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final value = fill;
    Widget slider(String label, double current, ValueChanged<double> change,
            {double min = 0, double max = 1, String suffix = '%'}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '$label ${(current * (suffix == '%' ? 100 : 1)).round()}$suffix'),
          Slider(
              semanticFormatterCallback: (v) =>
                  '${(v * (suffix == '%' ? 100 : 1)).round()}$suffix',
              value: current,
              min: min,
              max: max,
              onChanged: change),
        ]);
    return Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: false,
                    label: Text(solid, key: const ValueKey("room-list-solid"))),
                ButtonSegment(
                    value: true,
                    label: Text(gradient,
                        key: const ValueKey("room-list-gradient"))),
              ],
              selected: {
                value != null
              },
              onSelectionChanged: (selection) => onChanged(selection.first
                  ? RoomListFill([
                      preview.colorScheme.surfaceContainerLow,
                      preview.colorScheme.surfaceContainerLow,
                    ], const [
                      0,
                      1
                    ])
                  : null)),
          if (value != null) ...[
            for (var i = 0; i < value.colors.length; i++)
              Row(children: [
                IconButton(
                    tooltip: '$colorLabel ${i + 1}',
                    onPressed: () => edit(context, i),
                    icon: CircleAvatar(
                        radius: 14, backgroundColor: value.colors[i])),
                Expanded(
                    child: slider('$position ${i + 1}', value.stops[i], (stop) {
                  final stops = List<double>.of(value.stops)..[i] = stop;
                  onChanged(value.copyWith(stops: stops));
                },
                        min: i == 0 ? 0 : value.stops[i - 1],
                        max: i == value.stops.length - 1
                            ? 1
                            : value.stops[i + 1])),
              ]),
            if (value.colors.length < 5)
              TextButton.icon(
                  onPressed: () {
                    final colors = [...value.colors, value.colors.last];
                    onChanged(value.copyWith(
                        colors: colors, stops: even(colors.length)));
                  },
                  icon: const Icon(Icons.add),
                  label: Text(add)),
            slider(direction, value.angle,
                (angle) => onChanged(value.copyWith(angle: angle)),
                max: 360, suffix: '°'),
            slider(opacity, value.opacity,
                (opacity) => onChanged(value.copyWith(opacity: opacity))),
            if (lowContrast(value))
              Text(contrast,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (value.opacity < 1 || value.colors.any((c) => c.a < 1))
              Text(transparency),
          ],
        ]));
  }
}
