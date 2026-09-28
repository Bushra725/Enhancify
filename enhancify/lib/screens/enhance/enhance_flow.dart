import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../config/app_config.dart';
import '../../services/ads_service.dart';
import '../../services/ai_service.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/processing_dialog.dart';
import '../collage/collage_screen.dart';
import '../export/export_screen.dart';
import '../tools/beauty_screen.dart';
import '../tools/bg_remover_screen.dart';
import '../tools/gif_maker_screen.dart';
import '../tools/music_screen.dart';
import '../tools/passport_screen.dart';
import '../tools/remove_object_screen.dart';
import '../paywall/paywall_screen.dart';
import '../edit/photo_editor_screen.dart';
import 'result_screen.dart';
import 'video_result_screen.dart';

/// Checks the daily free quota. When it's used up the user can watch a
/// rewarded ad for one more use, or upgrade. Returns true if allowed.
Future<bool> ensureQuota(
  BuildContext context, {
  required String key,
  required int freeLimit,
  required String what,
}) async {
  final state = context.read<AppState>();
  if (state.remaining(key, freeLimit) != 0) return true;

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_bottom_rounded,
                size: 44, color: AppColors.red),
            const SizedBox(height: 10),
            const Text('Daily limit reached',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'You used all your free $what for today. Watch a short ad to '
              'unlock one more, or go Pro for unlimited access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.textSecondary),
            ),
            const SizedBox(height: 20),
            PillButton(
              label: 'Go Pro',
              kind: ButtonStyleKind.brand,
              trailing: const ProBadge(small: true),
              onPressed: () => Navigator.pop(ctx, 'pro'),
            ),
            const SizedBox(height: 10),
            PillButton(
              label: 'Watch an ad',
              kind: ButtonStyleKind.outline,
              leading: const Icon(Icons.play_circle_outline, color: AppColors.primary),
              onPressed: () => Navigator.pop(ctx, 'ad'),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return false;
  if (choice == 'pro') {
    await openPaywall(context);
    if (!context.mounted) return false;
    return state.remaining(key, freeLimit) != 0;
  }
  if (choice == 'ad') {
    return context.read<AdsService>().showRewarded();
  }
  return false;
}

/// Preview dialog shown when a photo is tapped (Enhance / Remove Ads & Limits).
/// HEIC/HEIF photos → JPEG so every on-device tool (and ffmpeg) can read them.
Future<File> _readable(File file) async {
  final ext = file.path.toLowerCase();
  if (!(ext.endsWith('.heic') || ext.endsWith('.heif'))) return file;
  try {
    final target = '${Directory.systemTemp.path}/src_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final out = await FlutterImageCompress.compressAndGetFile(file.absolute.path, target,
        quality: 95, minWidth: 4000, minHeight: 4000, format: CompressFormat.jpeg);
    if (out != null) return File(out.path);
  } catch (_) {}
  return file;
}

Future<void> startPhotoEnhance(BuildContext context, File file, {String tool = 'enhance'}) async {
  if (const {'remove', 'passport', 'gif', 'music', 'bg', 'beauty'}.contains(tool)) {
    file = await _readable(file);
    if (!context.mounted) return;
  }
  switch (tool) {
    case 'remove':
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      final out = await RemoveObjectScreen.open(context, bytes);
      if (out == null || !context.mounted) return;
      final f = File('${Directory.systemTemp.path}/removed_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await f.writeAsBytes(out, flush: true);
      if (!context.mounted) return;
      await ExportScreen.open(context, f);
      return;
    case 'passport':
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'passport'),
        builder: (_) => PassportScreen(photo: bytes),
      ));
      return;
    case 'gif':
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'gif'),
        builder: (_) => GifMakerScreen(photos: [bytes]),
      ));
      return;
    case 'beauty':
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      final out = await BeautyScreen.open(context, bytes);
      if (out == null || !context.mounted) return;
      final f = File('${Directory.systemTemp.path}/beauty_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await f.writeAsBytes(out, flush: true);
      if (!context.mounted) return;
      await ExportScreen.open(context, f);
      return;
    case 'bg':
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      await BgRemoverScreen.open(context, bytes);
      return;
    case 'music':
      await Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'music'),
        builder: (_) => MusicScreen(image: file),
      ));
      return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
    settings: RouteSettings(name: tool),
    builder: (_) => tool == 'collage'
        ? CollageScreen(initialPhotos: [file])
        : PhotoEditorScreen(file: file, tool: tool),
  ));
}

Future<void> enhancePhoto(BuildContext context, File file) async {
  final ok = await ensureQuota(context,
      key: UsageKeys.enhance,
      freeLimit: AppConfig.freeEnhancementsPerDay,
      what: 'enhancements');
  if (!ok || !context.mounted) return;

  final state = context.read<AppState>();
  final ai = context.read<AiService>();
  final ads = context.read<AdsService>();
  try {
    final result = await runWithProgress<File>(
      context,
      preview: file,
      task: (set) => ai.enhancePhoto(file,
          variant: EnhanceVariant.base,
          prefs: state.enhancerPrefs,
          onStatus: set),
    );
    await state.incrementUsage(UsageKeys.enhance);
    await ads.showInterstitial();
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultScreen(
        original: file,
        result: result,
        title: 'Enhanced',
        variant: EnhanceVariant.base,
        enableVariants: true,
      ),
    ));
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
  }
}

/// Video tap -> preview -> Pro check -> enhance.
Future<void> startVideoEnhance(
  BuildContext context,
  File file, {
  Duration? duration,
  Widget? thumbnail,
}) async {
  if (!AppConfig.supportsVideo) {
    showSnack(context, 'Video enhance is not available on the free AI plan yet.');
    return;
  }
  final go = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => _PreviewDialog(
      preview: thumbnail ??
          Container(
            color: AppColors.maroonDeep,
            child: const Icon(Icons.movie_outlined,
                size: 70, color: Colors.white38),
          ),
      primaryLabel: 'Enhance',
      primaryPro: true,
    ),
  );
  if (go != true || !context.mounted) return;

  final state = context.read<AppState>();
  if (!state.isPro) {
    await openPaywall(context);
    if (!context.mounted || !state.isPro) return;
  }
  if (duration == null || duration.inMilliseconds == 0) {
    final probe = VideoPlayerController.file(file);
    try {
      await probe.initialize();
      duration = probe.value.duration;
    } catch (_) {
      // Unknown length: let the server decide.
    } finally {
      await probe.dispose();
    }
    if (!context.mounted) return;
  }
  if (duration != null && duration.inSeconds > AppConfig.maxVideoSeconds) {
    showSnack(context,
        'Please pick a video up to ${AppConfig.maxVideoSeconds} seconds long.');
    return;
  }
  final ai = context.read<AiService>();
  try {
    final result = await runWithProgress<File>(
      context,
      isVideo: true,
      initialStatus: 'Uploading video...',
      task: (set) => ai.enhanceVideo(file, onStatus: set),
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoResultScreen(original: file, result: result),
    ));
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
  }
}

class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({
    required this.preview,
    required this.primaryLabel,
    required this.primaryPro,
  });

  final Widget preview;
  final String primaryLabel;
  final bool primaryPro;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.sizeOf(context).width * 0.84,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: preview,
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      child: const CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PillButton(
                label: primaryLabel,
                kind: ButtonStyleKind.dark,
                trailing: primaryPro && !state.isPro
                    ? const ProBadge()
                    : const Icon(Icons.arrow_forward_ios_rounded),
                onPressed: () => Navigator.pop(context, true),
              ),
              if (!state.isPaid) ...[
                const SizedBox(height: 10),
                PillButton(
                  label: 'Remove Ads & Limits',
                  kind: ButtonStyleKind.white,
                  trailing: const ProBadge(),
                  onPressed: () async {
                    await openPaywall(context);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
