import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

/// On-device image labeling used to suggest tags for a captured artwork.
///
/// Runs entirely offline via ML Kit; failures degrade to an empty suggestion
/// list so tagging falls back to manual input.
class LabelingService {
  static const double _confidenceThreshold = 0.6;

  Future<List<String>> suggestTags(String imagePath) async {
    final labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: _confidenceThreshold),
    );
    try {
      final labels =
          await labeler.processImage(InputImage.fromFilePath(imagePath));
      return labels.map((label) => label.label.toLowerCase()).toList();
    } catch (_) {
      return const [];
    } finally {
      await labeler.close();
    }
  }
}
