import 'package:commet/client/attachment.dart';
import 'package:matrix/matrix.dart';

class MatrixProcessedAttachment extends ProcessedAttachment {
  MatrixFile file;

  MatrixImageFile? thumbnailFile;

  /// Diagnostics timings carried from the pending attachment (see Telemetry).
  Map<String, int> telemetryMs = {};

  MatrixProcessedAttachment(this.file, {this.thumbnailFile});
}
