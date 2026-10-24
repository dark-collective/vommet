import 'package:commet/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:flutter/widgets.dart';

/// Vommet: only the web app frames widgets in the page.
class MatrixWidgetWebFrame {
  static String get parentUrl => "commet://widget";

  static Future<void> open(
      {required String url,
      required MatrixUserWidgetInfo info,
      required MatrixRoom room,
      required MatrixWidgetComponent component,
      required BuildContext context}) {
    throw UnsupportedError("Widget frames are only in the web app");
  }
}
