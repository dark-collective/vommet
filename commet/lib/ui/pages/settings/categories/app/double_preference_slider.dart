import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class DoublePreferenceSlider extends StatefulWidget {
  const DoublePreferenceSlider(
      {required this.preference,
      required this.min,
      required this.max,
      required this.title,
      this.units,
      this.description,
      this.numDecimals = 1,
      this.requiresConfirmationButton = false,
      this.onChanged,
      this.onChangeEnd,
      this.formatValue,
      this.divisions,
      super.key});

  final DoublePreference preference;
  final Function(double)? onChanged;

  /// Vommet: called once the slider is let go, for settings too costly to
  /// apply on every step.
  final Function(double)? onChangeEnd;

  /// Vommet: shows the value another way (a 0-2 volume as 0-200 %).
  final String Function(double)? formatValue;
  final int? divisions;
  final String? units;

  final double min;
  final double max;
  final bool requiresConfirmationButton;
  final int numDecimals;
  final String title;
  final String? description;

  @override
  State<DoublePreferenceSlider> createState() => _DoublePreferenceSliderState();
}

class _DoublePreferenceSliderState extends State<DoublePreferenceSlider> {
  late double value;

  @override
  void initState() {
    value = widget.preference.value;
    super.initState();
  }

  @override
  Widget build(BuildContext context) => SettingsSearchTarget(
      ids: [widget.preference.key, widget.title], child: _build(context));

  // Vommet: the original build; wrapped so settings search can flash it.
  Widget _build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: ColorScheme.of(context).surfaceContainer.withAlpha(100),
          border: BoxBorder.all(
              color: ColorScheme.of(context).secondary.withAlpha(20)),
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text(widget.title),
            if (widget.description != null)
              tiamat.Text.labelLow(widget.description!),
            Row(
              children: [
                tiamat.Text.labelLow(widget.formatValue?.call(value) ??
                    "${value.toStringAsFixed(widget.numDecimals)}${widget.units ?? ""}"),
                Expanded(
                  child: tiamat.Slider(
                    value: value,
                    min: widget.min,
                    max: widget.max,
                    divisions: widget.divisions,
                    onChangeEnd: widget.requiresConfirmationButton
                        ? null
                        : widget.onChangeEnd,
                    onChanged: (newValue) {
                      var strValue =
                          newValue.toStringAsFixed(widget.numDecimals);
                      var finalValue = double.parse(strValue);
                      setState(() {
                        value = finalValue;

                        if (!widget.requiresConfirmationButton) {
                          widget.onChanged?.call(finalValue);
                          widget.preference.set(finalValue);
                        }
                      });
                    },
                  ),
                ),
                if (widget.requiresConfirmationButton)
                  tiamat.Button.secondary(
                    text: CommonStrings.promptApply,
                    onTap: () {
                      widget.preference.set(value);
                      widget.onChanged?.call(value);
                    },
                  )
              ],
            )
          ],
        ),
      ),
    );
  }
}
