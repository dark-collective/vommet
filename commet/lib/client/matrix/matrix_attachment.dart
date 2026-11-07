import 'package:commet/client/attachment.dart';
import 'package:matrix/matrix.dart';

class MatrixProcessedAttachment extends ProcessedAttachment {
  MatrixFile file;

  MatrixImageFile? thumbnailFile;

  /// Diagnostics timings carried from the pending attachment (see Telemetry).
  Map<String, int> telemetryMs = {};

  /// Vommet: send as a spoiler (MSC4193), see PendingFileAttachment.
  bool spoiler = false;
  String? spoilerReason;

  MatrixProcessedAttachment(this.file, {this.thumbnailFile});
}
