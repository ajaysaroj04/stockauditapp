import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Photographs (or picks) a label image and reads its printed text on-device
/// with Google ML Kit. Nothing is uploaded anywhere.
class LabelOcrService {
  LabelOcrService._();

  /// Returns the recognised text, or null if the user cancelled.
  static Future<String?> readLabel(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 95,
      maxWidth: 3000,
    );
    if (file == null) return null;

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      return result.text;
    } finally {
      await recognizer.close();
    }
  }
}
