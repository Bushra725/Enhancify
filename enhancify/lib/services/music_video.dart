import 'dart:io';

/// Photo + music used to rely on FFmpeg (~30 MB per CPU architecture).
/// That encoder was removed so the Play Store download stays near 20–30 MB.
class MusicVideo {
  MusicVideo._();

  static Future<double?> durationOf(String audioPath) async => null;

  static Future<File> render({
    required String imagePath,
    required String audioPath,
    required double start,
    required double seconds,
    bool zoom = true,
    bool fade = true,
  }) async {
    throw StateError(
      'Photo + music video is not included in this Play Store build. '
      'Share the photo instead.',
    );
  }
}
