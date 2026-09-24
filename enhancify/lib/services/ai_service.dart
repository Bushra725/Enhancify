import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/ai_models.dart';
import '../config/app_config.dart';
import 'app_state.dart';
import 'cloudflare_service.dart';
import 'gemini_service.dart';
import 'replicate_service.dart';
import 'openai_service.dart';

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
  AiService({ReplicateService? replicate, CloudflareService? cloudflare})
      : _replicate = replicate ?? ReplicateService(),
        _cloudflare = cloudflare ?? CloudflareService();

  final ReplicateService _replicate;
  final CloudflareService _cloudflare;
  final _rand = Random();

  static const _restorePrompt =
      'Restore and enhance this photo into a sharp, high quality, high '
      'resolution photograph: remove blur, noise, scratches and compression '
      'artifacts, recover fine facial details, natural skin texture and clear '
      'eyes, and improve lighting. Keep exactly the same person, face, '
      'identity, expression, pose, clothing, background, composition and '
      'colors. Photorealistic.';
  static const _naturalPrompt =
      'Gently clean up this photo: slightly sharpen it and reduce noise and '
      'blur while keeping everything else identical: same person, face, '
      'colors, lighting and composition. Photorealistic, natural look.';
  static const _ultraPrompt =
      'Restore this photo in ultra high definition with maximum fine detail: '
      'crisp eyes, hair strands, skin pores and fabric texture, no blur, no '
      'noise. Keep exactly the same person, identity, expression, pose, '
      'background and colors. Photorealistic.';
  String Function()? _readOpenAiKey;

  void attachKey(String Function() read) => _readOpenAiKey = read;

  String get openAiKey {
    final saved = _readOpenAiKey?.call() ?? '';
    if (saved.isNotEmpty) return saved;
    return AppConfig.openAiApiKey;
  }

  String get geminiKey => AppConfig.geminiApiKey;

  bool get hasCloudflare => AppConfig.useCloudflare;
  bool get hasGemini =>
      AppConfig.backendUrl.isNotEmpty || geminiKey.isNotEmpty;
  bool get hasOpenAi => openAiKey.isNotEmpty;
  bool get hasReplicate =>
      AppConfig.backendUrl.isNotEmpty || AppConfig.replicateToken.isNotEmpty;

  /// No real backend is configured.
  bool get demoMode => !hasOpenAi && !hasReplicate;

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

  Future<File> _geminiEdit(
    File source,
    String prompt, {
    StatusCallback? onStatus,
  }) async {
    onStatus?.call('Sending your photo...');
    final prepared = await prepareImage(source, maxSide: 1280);
    onStatus?.call('Creating your result...');
    final bytes = await GeminiService(geminiKey).edit(
      image: prepared,
      prompt:
          'Edit the attached photo only. Keep the same person, face, pose, and identity. $prompt Do not replace this photo with a different picture.',
    );
    final out = await _newFile('jpg');
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  Future<File> _openAiEdit(
    File source,
    String prompt, {
    bool highDetail = false,
    StatusCallback? onStatus,
  }) async {
    onStatus?.call('Uploading image...');
    final prepared = await prepareImage(source);
    onStatus?.call('Creating your result...');
    final bytes = await OpenAiService(openAiKey).edit(
      image: prepared,
      prompt: prompt,
      highDetail: highDetail,
    );
    final out = await _newFile('jpg');
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  Future<List<CfInput>> _cfInputs(List<File> images) async {
    final out = <CfInput>[];
    for (final f in images) {
      try {
        out.add(await CloudflareService.shrink(await f.readAsBytes()));
      } on AiException {
        final converted = await prepareImage(f);
        try {
          out.add(await CloudflareService.shrink(await converted.readAsBytes()));
        } finally {
          if (converted.path != f.path) {
            try {
              await converted.delete();
            } catch (_) {}
          }
        }
      }
    }
    return out;
  }

  Future<File> _cfRun(
    List<CfInput> inputs,
    String prompt, {
    StatusCallback? onStatus,
  }) async {
    final bytes = await _cloudflare.edit(inputs, prompt);
    final isPng = bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final out = await _newFile(isPng ? 'png' : 'jpg');
    await out.writeAsBytes(bytes, flush: true);
    onStatus?.call('Almost done...');
    return out;
  }

  Future<File> _runCf(
    List<File> images,
    String prompt, {
    StatusCallback? onStatus,
  }) async {
    onStatus?.call('Uploading image...');
    final inputs = await _cfInputs(images);
    onStatus?.call('Working on your photo...');
    return _cfRun(inputs, prompt, onStatus: onStatus);
  }

  String _enhancePrompt(EnhanceVariant variant, EnhancerPrefs prefs) {
    final strength = prefs.faceFidelity < 0.4
        ? 'Apply a strong, crisp facial restoration.'
        : 'Keep the face close to the original.';
    return switch (variant) {
      EnhanceVariant.base =>
        'Restore this exact photograph. Sharpen detail, balance the light, and improve color. $strength Keep the same person, expression, pose, clothes, framing, and background. Photorealistic. Do not invent a new scene.',
      EnhanceVariant.natural =>
        'Make a very small natural correction only: slightly cleaner exposure and white balance. The photo must stay almost identical, including the same person, pose, clothes, and background.',
      EnhanceVariant.ultra =>
        'Rebuild this photograph in ultra high definition. Recover fine detail in eyes, hair, skin texture, fabric, and the background. Keep the same identity, expression, pose, clothes, and framing. Photorealistic, not illustrated.',
    };
  }

  // ------------------------------------------------------------ enhance
  Future<File> enhancePhoto(
    File source, {
    required EnhanceVariant variant,
    required EnhancerPrefs prefs,
    StatusCallback? onStatus,
  }) async {
    if (hasCloudflare) {
      final prompt = switch (variant) {
        EnhanceVariant.base => _restorePrompt,
        EnhanceVariant.natural => _naturalPrompt,
        EnhanceVariant.ultra => _ultraPrompt,
      };
      return _runCf([source], prompt, onStatus: onStatus);
    }
    if (hasGemini) {
      return _geminiEdit(source, _enhancePrompt(variant, prefs), onStatus: onStatus);
    }
    if (hasOpenAi) {
      return _openAiEdit(
        source,
        _enhancePrompt(variant, prefs),
        highDetail: variant == EnhanceVariant.ultra || prefs.upscale >= 4,
        onStatus: onStatus,
      );
    }
    if (!hasReplicate) {
      throw AiException('This photo could not be enhanced right now.');
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
    if (hasCloudflare) return _runCf([source], prompt, onStatus: onStatus);
    if (hasGemini) {
      return _geminiEdit(
        source,
        '$prompt Apply this style to the attached photo.',
        onStatus: onStatus,
      );
    }
    if (hasOpenAi) {
      return _openAiEdit(
        source,
        '$prompt Style: $demoLook. Apply this change to the whole photo. Keep the same person\'s identity.',
        onStatus: onStatus,
      );
    }
    if (!hasReplicate) {
      throw AiException('This photo could not be restyled right now.');
    }
    return _runImage(AiModels.imageEdit, source,
        input: {'prompt': prompt}, onStatus: onStatus);
  }

  // ---------------------------------------------------------- AI photos
  /// Generates one photo per prompt from a selfie. Runs up to 3 in parallel.
  Future<List<File>> generateAiPhotos(
    File selfie,
    List<String> prompts, {
    List<File> extraSelfies = const [],
    StatusCallback? onStatus,
    void Function(int done, int total)? onProgress,
  }) async {
    if (prompts.isEmpty) return [];
    if (hasCloudflare) {
      onStatus?.call('Creating your AI photos...');
      final refs = await _cfInputs([selfie, ...extraSelfies.take(3)]);
      final results = <File>[];
      final errors = <Object>[];
      var done = 0;
      for (var i = 0; i < prompts.length; i += 2) {
        final slice = prompts.sublist(i, min(i + 2, prompts.length));
        await Future.wait(slice.map((prompt) async {
          try {
            results.add(await _cfRun(refs, prompt));
          } catch (e) {
            errors.add(e);
          } finally {
            onProgress?.call(++done, prompts.length);
          }
        }));
      }
      if (results.isEmpty) {
        throw errors.isNotEmpty
            ? errors.first
            : AiException('Could not generate photos.');
      }
      return results;
    }
    if (!hasGemini && !hasOpenAi && !hasReplicate) {
      throw AiException('These photos could not be created right now.');
    }
    final slots = List<File?>.filled(prompts.length, null);
    var done = 0;
    if (hasGemini) {
      onStatus?.call('Creating your AI photos...');
      final prepared = await prepareImage(selfie, maxSide: 1280);
      final errors = <Object>[];
      for (var i = 0; i < prompts.length; i++) {
        try {
          final bytes = await GeminiService(geminiKey).edit(
            image: prepared,
            prompt:
                'Edit the attached photo only. Keep the same person and face. ${prompts[i]}',
          );
          final out = await _newFile('jpg');
          await out.writeAsBytes(bytes, flush: true);
          slots[i] = out;
        } catch (e) {
          errors.add(e);
        }
        onProgress?.call(i + 1, prompts.length);
      }
      final results = slots.whereType<File>().toList();
      if (results.isEmpty) {
        throw errors.isNotEmpty
            ? errors.first
            : AiException('Could not generate photos.');
      }
      return results;
    }
    if (hasOpenAi) {
      onStatus?.call('Creating your AI photos...');
      final prepared = await prepareImage(selfie);
      final errors = <Object>[];
      Future<void> one(int index) async {
        try {
          final bytes = await OpenAiService(openAiKey).edit(
            image: prepared,
            prompt: prompts[index],
            highDetail: true,
          );
          final out = await _newFile('jpg');
          await out.writeAsBytes(bytes, flush: true);
          slots[index] = out;
        } catch (e) {
          errors.add(e);
        } finally {
          onProgress?.call(++done, prompts.length);
        }
      }

      const batch = 2;
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
    if (hasCloudflare && !hasReplicate) {
      throw AiException('Video enhance is not available on the free AI plan yet.');
    }
    if (!hasReplicate) {
      throw AiException('Video enhance is not available right now.');
    }
    onStatus?.call('Uploading video...');
    final url = await _replicate.uploadFile(source);
    onStatus?.call('Enhancing video. This can take a few minutes...');
    final outs = await _replicate.run(AiModels.videoEnhance, mediaUrl: url);
    final o = outs.first;
    onStatus?.call('Downloading...');
    return _replicate.download(o, await _newFile(_extFromUrl(o, 'mp4')));
  }
}
