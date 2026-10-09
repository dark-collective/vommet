import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: "What's this?" for the attachment dialog's metadata switch. Says
/// plainly what hidden info files carry, what Vommet removes and what it
/// can't, so the switch doesn't promise more than it does.
class MetadataExplainer extends StatelessWidget {
  const MetadataExplainer({super.key});

  static String get promptWhatsThis => Intl.message("What's this?",
      desc: "Small link in the attachment dialog that explains file metadata",
      name: "promptWhatsThis");

  static String get titleMetadata => Intl.message("Hidden info in files",
      desc: "Title of the dialog that explains file metadata",
      name: "titleMetadata");

  static Future<void> show(BuildContext context) => AdaptiveDialog.show(
        context,
        title: titleMetadata,
        builder: (_) => const MetadataExplainer(),
      );

  @override
  Widget build(BuildContext context) {
    Widget section(IconData icon, String title, String body,
        {required bool removed}) {
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Icon(icon, color: scheme.primary),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  tiamat.Text.labelEmphasised(title),
                  tiamat.Text.label(body),
                  Row(
                    spacing: 4,
                    children: [
                      Icon(removed ? Icons.check_circle : Icons.warning_amber,
                          size: 16,
                          color: removed ? Colors.green : scheme.error),
                      Flexible(
                        child: tiamat.Text.labelLow(removed
                            ? "Vommet removes this when “Remove hidden info” is on (the default)."
                            : "Vommet can't remove this. Check the file before you send it."),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: tiamat.Text.label(
                "Many files carry hidden information (metadata) next to what you can see: where a photo was taken, which phone took it, who wrote a document. People who receive the file can read it with ordinary tools."),
          ),
          section(Icons.photo, "Photos (JPEG, PNG, WebP, BMP)",
              "GPS location, phone or camera model and serial number, date and time taken, editing software, sometimes your name or a copyright line. Images from AI generators often hold the full prompt and settings.",
              removed: true),
          section(
              Icons.picture_as_pdf,
              "PDFs and documents (Word, Google Docs, LibreOffice)",
              "Author name, which is often your real name or account name, plus organisation, creation and edit dates, the app used, and sometimes comments or earlier revisions. A PDF exported from Google Docs can carry the name on your Google account.",
              removed: false),
          section(Icons.videocam, "Videos",
              "Phones often record the location, the device model and the date inside the video file.",
              removed: false),
          section(Icons.gif_box, "GIFs, HEIC photos, audio and other files",
              "Can hold names, comments, tags, device details or location (iPhone HEIC photos usually include it).",
              removed: false),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: tiamat.Text.label(
                "For files Vommet can't clean, remove the info first: set the author in the document's properties before exporting, or use a metadata cleaner such as ExifTool, or Metadata Cleaner (mat2) on Linux."),
          ),
          tiamat.Text.labelLow(
              "Removing hidden info doesn't change what's visible: faces, names in screenshots and the background of a photo can still give things away. Photos are re-saved at full quality, so they look the same; a colour profile may be dropped."),
        ],
      ),
    );
  }
}
