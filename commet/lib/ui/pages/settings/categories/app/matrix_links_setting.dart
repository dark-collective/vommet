import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 85: Android 12+ only opens matrix.to links in Vommet once the
/// user allows it under App info › Open by default (we can't verify the
/// domain). This row says whether that's on and opens the page. Hidden on
/// other platforms and before Android 12, where Android asks which app opens
/// a link.
class MatrixLinksSetting extends StatefulWidget {
  const MatrixLinksSetting({super.key});

  @override
  State<MatrixLinksSetting> createState() => _MatrixLinksSettingState();
}

class _MatrixLinksSettingState extends State<MatrixLinksSetting>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('chat.commet.commetapp/utils');

  bool? allowed;

  @override
  void initState() {
    super.initState();
    if (!PlatformUtils.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android's settings page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    bool? value;
    try {
      value = await _channel.invokeMethod<bool>("matrixToLinksAllowed");
    } catch (e) {
      Log.w("Could not read matrix.to link handling: $e");
    }
    if (mounted && value != allowed) setState(() => allowed = value);
  }

  @override
  Widget build(BuildContext context) {
    final allowed = this.allowed;
    if (allowed == null) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.labelEmphasised(labelMatrixLinksTitle),
              tiamat.Text.labelLow(allowed
                  ? labelMatrixLinksAllowed
                  : labelMatrixLinksNotAllowed),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
          child: tiamat.Button.secondary(
            text: labelMatrixLinksButton,
            onTap: () => _channel
                .invokeMethod("openByDefaultSettings")
                .catchError((Object e) {
              Log.w("Could not open Open by default settings: $e");
              return null;
            }),
          ),
        ),
      ],
    );
  }
}

String get labelMatrixLinksTitle => Intl.message("Open matrix.to links",
    name: "labelMatrixLinksTitle",
    desc:
        "Title of the Android setting row about opening matrix.to links from other apps in Vommet");

String get labelMatrixLinksAllowed => Intl.message(
    "On: matrix.to links from other apps open in Vommet.",
    name: "labelMatrixLinksAllowed",
    desc:
        "Shown when Android is set to open matrix.to links in Vommet (Open by default)");

String get labelMatrixLinksNotAllowed => Intl.message(
    "Off: to open matrix.to links from other apps here, tap Open by default, then Add link and pick matrix.to.",
    name: "labelMatrixLinksNotAllowed",
    desc:
        "Shown when Android doesn't open matrix.to links in Vommet yet; explains the Open by default steps");

String get labelMatrixLinksButton => Intl.message("Open by default",
    name: "labelMatrixLinksButton",
    desc:
        "Button that opens Android's Open by default settings page for Vommet. Use the name of that Android settings page");
