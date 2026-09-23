import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/ai_models.dart';
import '../config/app_config.dart';
import 'app_state.dart';
import 'replicate_service.dart';

enum EnhanceVariant { base, ultra, natural }

extension EnhanceVariantX on EnhanceVariant {
  String get label => switch (this) {
        EnhanceVariant.base => 'Enhance',
        EnhanceVariant.ultra => 'Ultra HD',
        EnhanceVariant.natural => 'Natural',
      };

  bool get requiresPro => this == EnhanceVariant.ultra;
}

typedef StatusCallback = void Function(String message);

/// High-level AI operations used by the UI.
class AiService {
  AiService({ReplicateService? replicate})
      : _replicate = replicate ?? ReplicateService();

  final ReplicateService _replicate;
  final _rand = Random();

  bool get demoMode => AppConfig.isDemoMode;

  Future<Directory> _workDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'enhancify'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _newFile(String ext) async {
    final dir = await _workDir();
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${_rand.nextInt(1 << 20)}.$ext';
    return File(p.join(dir.path, name));
  }

  String _extFromUrl(String url, String fallback) {
    final path = Uri.tryParse(url)?.path ?? '';
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    const ok = {'png', 'jpg', 'jpeg', 'webp', 'mp4', 'mov'};
    return ok.contains(ext) ? ext : fallback;
  }

  /// Resizes / re-encodes the photo to a JPEG under ~2048px so uploads are
  /// fast and every model accepts it (HEIC etc. are converted).
  Future<File> prepareImage(File src, {int maxSide = 2048}) async {
    try {
      final target = await _newFile('jpg');
      final out = await FlutterImageCompress.compressAndGetFile(
        src.absolute.path,
        target.path,
        minWidth: maxSide,
        minHeight: maxSide,
        quality: 92,
        format: CompressFormat.jpeg,
      );
      if (out != null) return File(out.path);
    } catch (_) {}
    return src;
  }

  Future<File> _runImage(
    AiModel model,
    File source, {
    Map<String, dynamic> input = const {},
    StatusCallback? onStatus,
  }) async {
    onStatus?.call('Uploading image...');
    final prepared = await prepareImage(source);
    final url = await _replicate.uploadFile(prepared);
    onStatus?.call('Enhancing...');
    final outputs = await _replicate.run(
      model,
      mediaUrl: url,
      input: input,
      onStatus: (s) {
        if (s == 'starting') onStatus?.call('Warming up the AI...');
        if (s == 'processing') onStatus?.call('Working on your photo...');
      },
    );
    onStatus?.call('Almost done...');
    final out = outputs.first;
    return _replicate.download(out, await _newFile(_extFromUrl(out, 'png')));
  }

  // ------------------------------------------------------------ enhance
  Future<File> enhancePhoto(
    File source, {
    required EnhanceVariant variant,
    required EnhancerPrefs prefs,
    StatusCallback? onStatus,
  }) async {
    if (demoMode) {
      return switch (variant) {
        EnhanceVariant.base => _demo(
            source,
            _DemoLook.enhance,
            onStatus: onStatus,
            scale: prefs.upscale >= 4 ? 2 : 1,
          ),
        EnhanceVariant.natural =>
          _demo(source, _DemoLook.natural, onStatus: onStatus),
        EnhanceVariant.ultra =>
          _demo(source, _DemoLook.vivid, onStatus: onStatus, scale: 2),
      };
    }
    switch (variant) {
      case EnhanceVariant.base:
        // CodeFormer only accepts 1x or 2x. A 4x preference is a 2x restore
        // followed by a 2x upscale.
        final faceScale = prefs.upscale <= 1 ? 1 : 2;
        final face = await _runImage(AiModels.faceEnhance, source,
            input: {
              'codeformer_fidelity': prefs.faceFidelity,
              'background_enhance': prefs.backgroundEnhance,
              'face_upsample': prefs.faceUpsample,
              'upscale': faceScale,
            },
            onStatus: onStatus);
        if (prefs.upscale < 4) return face;
        onStatus?.call('Upscaling to 4x...');
        return _runImage(AiModels.upscale, face,
            input: {'scale': 2, 'face_enhance': false}, onStatus: onStatus);
      case EnhanceVariant.natural:
        return _runImage(AiModels.faceEnhance, source,
            input: {
              'codeformer_fidelity': 0.9,
              'background_enhance': false,
              'face_upsample': true,
              'upscale': 2,
            },
            onStatus: onStatus);
      case EnhanceVariant.ultra:
        return _runImage(AiModels.upscale, source,
            input: {'scale': 4, 'face_enhance': true}, onStatus: onStatus);
    }
  }

  // ------------------------------------------------------------ filters
  Future<File> applyPrompt(
    File source,
    String prompt, {
    StatusCallback? onStatus,
    String demoLook = 'warm',
  }) async {
    if (demoMode) {
      return _demo(source, _DemoLook.fromName(demoLook), onStatus: onStatus);
    }
    return _runImage(AiModels.imageEdit, source,
        input: {'prompt': prompt}, onStatus: onStatus);
  }

  // ---------------------------------------------------------- AI photos
  /// Generates one photo per prompt from a selfie. Runs up to 3 in parallel.
  Future<List<File>> generateAiPhotos(
    File selfie,
    List<String> prompts, {
    StatusCallback? onStatus,
    void Function(int done, int total)? onProgress,
  }) async {
    if (prompts.isEmpty) return [];
    final slots = List<File?>.filled(prompts.length, null);
    var done = 0;
    if (demoMode) {
      const looks = _DemoLook.values;
      for (var i = 0; i < prompts.length; i++) {
        slots[i] = await _demo(selfie, looks[i % looks.length], onStatus: onStatus);
        onProgress?.call(++done, prompts.length);
      }
      return slots.whereType<File>().toList();
    }
    onStatus?.call('Uploading your selfie...');
    final url = await _replicate.uploadFile(await prepareImage(selfie));
    onStatus?.call('Creating your AI photos...');
    final errors = <Object>[];
    Future<void> one(int index) async {
      try {
        final outs = await _replicate.run(
          AiModels.imageEdit,
          mediaUrl: url,
          input: {'prompt': prompts[index]},
        );
        final o = outs.first;
        slots[index] =
            await _replicate.download(o, await _newFile(_extFromUrl(o, 'jpg')));
      } catch (e) {
        errors.add(e);
      } finally {
        onProgress?.call(++done, prompts.length);
      }
    }

    const batch = 3;
    for (var i = 0; i < prompts.length; i += batch) {
      final end = min(i + batch, prompts.length);
      await Future.wait([for (var j = i; j < end; j++) one(j)]);
    }
    final results = slots.whereType<File>().toList();
    if (results.isEmpty) {
      throw errors.isNotEmpty
          ? errors.first
          : AiException('Could not generate photos.');
    }
    return results;
  }

  // ------------------------------------------------------------- video
  Future<File> enhanceVideo(File source, {StatusCallback? onStatus}) async {
    if (demoMode) {
      onStatus?.call('Uploading video...');
      await Future<void>.delayed(const Duration(seconds: 2));
      onStatus?.call('Enhancing video (demo)...');
      await Future<void>.delayed(const Duration(seconds: 2));
      var ext = p.extension(source.path).replaceFirst('.', '').toLowerCase();
      if (ext.isEmpty || ext.length > 4) ext = 'mp4';
      final out = await _newFile(ext);
      return source.copy(out.path);
    }
    onStatus?.call('Uploading video...');
    final url = await _replicate.uploadFile(source);
    onStatus?.call('Enhancing video. This can take a few minutes...');
    final outs = await _replicate.run(AiModels.videoEnhance, mediaUrl: url);
    final o = outs.first;
    onStatus?.call('Downloading...');
    return _replicate.download(o, await _newFile(_extFromUrl(o, 'mp4')));
  }

  // -------------------------------------------------------------- demo
  /// Local stand-in used when no AI backend is configured, so the whole app
  /// can be tried end-to-end. Applies a colour/contrast look with dart:ui.
  Future<File> _demo(
    File src,
    _DemoLook look, {
    StatusCallback? onStatus,
    int scale = 1,
  }) async {
    onStatus?.call('Uploading image...');
    await Future<void>.delayed(const Duration(milliseconds: 900));
    onStatus?.call('Enhancing (demo mode)...');
    final prepared = await prepareImage(src, maxSide: 1600);
    final bytes = await prepared.readAsBytes();
    if (bytes.isEmpty) {
      throw AiException('Could not read this photo. Try another one.');
    }
    late final ui.Image img;
    try {
      img = await _decode(bytes, maxSide: 1600);
    } catch (_) {
      throw AiException('Could not read this photo. Try another one.');
    }
    final factor = scale < 1 ? 1 : scale;
    final outW = img.width * factor;
    final outH = img.height * factor;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.high
      ..colorFilter = ui.ColorFilter.matrix(look.matrix);
    canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    final outImg = await picture.toImage(outW, outH);
    final data = await outImg.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    outImg.dispose();
    if (data == null) throw AiException('Could not process image.');
    final out = await _newFile('png');
    await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return out;
  }

  Future<ui.Image> _decode(Uint8List bytes, {required int maxSide}) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final img = frame.image;
    final longest = max(img.width, img.height);
    if (longest <= maxSide) return img;
    final targetW = img.width >= img.height ? maxSide : null;
    final targetH = img.height > img.width ? maxSide : null;
    img.dispose();
    final scaled = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetW,
      targetHeight: targetH,
    );
    final scaledFrame = await scaled.getNextFrame();
    scaled.dispose();
    return scaledFrame.image;
  }
}

enum _DemoLook {
  enhance,
  natural,
  warm,
  cool,
  mono,
  vivid;

  static _DemoLook fromName(String n) =>
      _DemoLook.values.firstWhere((l) => l.name == n, orElse: () => warm);

  List<double> get matrix {
    final m = switch (this) {
        // contrast 1.15 + saturation 1.2 + slight brightness
        _DemoLook.enhance => <double>[
            1.25, -0.08, -0.02, 0, -14, //
            -0.04, 1.22, -0.03, 0, -14, //
            -0.04, -0.08, 1.27, 0, -14, //
            0, 0, 0, 1, 0,
          ],
        _DemoLook.natural => <double>[
            1.04, 0, 0, 0, 6, //
            0, 1.04, 0, 0, 6, //
            0, 0, 1.04, 0, 6, //
            0, 0, 0, 1, 0,
          ],
        _DemoLook.warm => <double>[
            1.15, 0.05, 0, 0, 10, //
            0, 1.05, 0, 0, 4, //
            0, 0, 0.85, 0, -6, //
            0, 0, 0, 1, 0,
          ],
        _DemoLook.cool => <double>[
            0.9, 0, 0, 0, -4, //
            0, 1.0, 0.05, 0, 2, //
            0, 0.05, 1.2, 0, 12, //
            0, 0, 0, 1, 0,
          ],
        _DemoLook.mono => <double>[
            0.33, 0.59, 0.11, 0, 0, //
            0.33, 0.59, 0.11, 0, 0, //
            0.33, 0.59, 0.11, 0, 0, //
            0, 0, 0, 1, 0,
          ],
        _DemoLook.vivid => <double>[
            1.5, -0.25, -0.25, 0, -10, //
            -0.25, 1.5, -0.25, 0, -10, //
            -0.25, -0.25, 1.5, 0, -10, //
            0, 0, 0, 1, 0,
          ],
      };
    assert(m.length == 20, 'Color matrix must have 20 values');
    return m;
  }
}
