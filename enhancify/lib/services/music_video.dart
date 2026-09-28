import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:image/image.dart' as img;

/// Turns a still photo + a song into an MP4 (H.264 + AAC) that Instagram,
/// Facebook, TikTok and WhatsApp accept.
class MusicVideo {
  MusicVideo._();

  /// Song length in seconds, or null if it can't be read.
  static Future<double?> durationOf(String audioPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(audioPath);
      final d = session.getMediaInformation()?.getDuration();
      return d == null ? null : double.tryParse(d);
    } catch (_) {
      return null;
    }
  }

  /// Renders [imagePath] for [seconds] with the song starting at [start].
  /// [zoom] adds a slow push-in so the video doesn't look frozen.
  static Future<File> render({
    required String imagePath,
    required String audioPath,
    required double start,
    required double seconds,
    bool zoom = true,
    bool fade = true,
  }) async {
    final out = '${Directory.systemTemp.path}/enhancify_music_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final dur = seconds.toStringAsFixed(2);
    final frames = (seconds * 30).round();
    final audio = fade
        ? 'afade=t=in:st=0:d=0.8,afade=t=out:st=${(seconds - 1.2).clamp(0, 9999).toStringAsFixed(2)}:d=1.2'
        : 'anull';

    // ffmpeg ignores JPEG EXIF rotation, so camera photos straight from the
    // gallery would come out sideways. Bake the rotation into a temp copy.
    String? rotated;
    try {
      rotated = await Isolate.run(() => _uprightCopy(imagePath));
    } catch (_) {
      rotated = null;
    }
    final photo = rotated ?? imagePath;

    // Output size: long side at most 1080 px, both sides even.
    final size = await _imageSize(photo);
    final w = size == null ? 1080 : _even(size.$1, size.$2, true);
    final h = size == null ? 1080 : _even(size.$1, size.$2, false);
    // zoompan turns ONE input frame into `frames` frames, so the zoom path
    // reads the photo once; the still path loops it at 30 fps.
    final vf = zoom
        ? 'scale=${w * 2}:${h * 2},'
            "zoompan=z='min(1+0.0008*on,1.12)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
            ':d=$frames:s=${w}x$h:fps=30,format=yuv420p'
        : 'scale=$w:$h,format=yuv420p';
    final imageInput = zoom
        ? ['-i', photo]
        : ['-loop', '1', '-framerate', '30', '-i', photo];

    List<String> args(String codec) => [
          '-y',
          ...imageInput,
          '-ss', start.toStringAsFixed(2), '-t', dur, '-i', audioPath,
          '-map', '0:v', '-map', '1:a',
          '-vf', vf,
          '-af', audio,
          if (codec == 'libx264') ...['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-tune', 'stillimage']
          else ...['-c:v', 'mpeg4', '-q:v', '2'],
          '-pix_fmt', 'yuv420p', '-r', '30',
          '-c:a', 'aac', '-b:a', '192k',
          '-movflags', '+faststart',
          '-shortest', '-t', dur,
          out,
        ];

    var session = await FFmpegKit.executeWithArguments(args('libx264'));
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      session = await FFmpegKit.executeWithArguments(args('mpeg4'));
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        final log = await session.getAllLogsAsString() ?? '';
        final tail = log.length > 300 ? log.substring(log.length - 300) : log;
        throw StateError('Could not make the video. $tail');
      }
    }
    if (rotated != null) {
      try {
        await File(rotated).delete();
      } catch (_) {}
    }
    final file = File(out);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('Could not make the video.');
    }
    return file;
  }

  /// Upright JPEG copy of [path] when its EXIF says it is rotated, else null.
  static String? _uprightCopy(String path) {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length < 3 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    final o = img.decodeJpgExif(Uint8List.fromList(bytes))?.imageIfd.orientation;
    if (o == null || o == 1) return null;
    final d = img.decodeJpg(bytes);
    if (d == null) return null;
    var im = img.bakeOrientation(d);
    if (im.width > 2160 || im.height > 2160) {
      im = im.width >= im.height
          ? img.copyResize(im, width: 2160, interpolation: img.Interpolation.average)
          : img.copyResize(im, height: 2160, interpolation: img.Interpolation.average);
    }
    final out = '${Directory.systemTemp.path}/enhancify_upright_${DateTime.now().microsecondsSinceEpoch}.jpg';
    File(out).writeAsBytesSync(img.encodeJpg(im, quality: 92), flush: true);
    return out;
  }

  static Future<(int, int)?> _imageSize(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final streams = session.getMediaInformation()?.getStreams() ?? const [];
      for (final s in streams) {
        final w = s.getWidth(), h = s.getHeight();
        if (w != null && h != null && w > 0 && h > 0) return (w, h);
      }
    } catch (_) {}
    return null;
  }

  /// Output size matching the scale filter (long side ≤ 1080, even).
  static int _even(int w, int h, bool width) {
    final long = w > h ? w : h;
    final f = long > 1080 ? 1080 / long : 1.0;
    final v = ((width ? w : h) * f).floor();
    return v - v % 2;
  }
}
