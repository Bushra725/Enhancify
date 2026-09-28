import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'pollinations_service.dart';

/// AI-made backgrounds from the free Pollinations image server. No account
/// or key. Every result is kept on the phone so it can be reused.
class AiBackgroundService {
  AiBackgroundService._();

  static Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/ai_backgrounds');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Newest first.
  static Future<List<File>> saved() async {
    try {
      final d = await _dir();
      final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.png')).toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files;
    } catch (_) {
      return const [];
    }
  }

  static Future<File> generate(String prompt, {double aspect = 9 / 16}) async {
    final (w, h) = _pixelSize(aspect);
    final bytes = Uint8List.fromList(
      await PollinationsService().generate(prompt, width: w, height: h),
    );
    final d = await _dir();
    final ext = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50 ? 'png' : 'jpg';
    final f = File('${d.path}/bg_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static (int, int) _pixelSize(double aspect) {
    const long = 1024;
    if (aspect >= 1) {
      return (long, (long / aspect).round().clamp(256, long));
    }
    return (((long * aspect).round()).clamp(256, long), long);
  }

  static Future<void> delete(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }
}
