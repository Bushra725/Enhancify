import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/ads_service.dart';
import '../../services/ai_service.dart';
import '../../services/app_state.dart';
import '../../services/media_service.dart';
import '../../widgets/common.dart';
import '../../widgets/processing_dialog.dart';
import '../enhance/enhance_flow.dart';
import '../enhance/result_screen.dart';
import '../paywall/paywall_screen.dart';

/// Picks a photo and runs a one-tap tool: either an edit [prompt]
/// (e.g. Colorize) or an enhance [variant] (e.g. Upscale 4x).
Future<void> runQuickTool(
  BuildContext context, {
  required String title,
  String? prompt,
  EnhanceVariant? variant,
  String demoLook = 'warm',
}) async {
  assert(prompt != null || variant != null);
  final state = context.read<AppState>();
  if (variant != null && variant.requiresPro && !state.isPro) {
    await openPaywall(context);
    if (!context.mounted || !state.isPro) return;
  }
  final File? file = await MediaService.pickImage();
  if (file == null || !context.mounted) return;

  final key = prompt != null ? UsageKeys.filter : UsageKeys.enhance;
  final limit = prompt != null
      ? AppConfig.freeFiltersPerDay
      : AppConfig.freeEnhancementsPerDay;
  final ok = await ensureQuota(context,
      key: key, freeLimit: limit, what: prompt != null ? 'AI edits' : 'enhancements');
  if (!ok || !context.mounted) return;

  final ai = context.read<AiService>();
  final ads = context.read<AdsService>();
  try {
    final result = await runWithProgress<File>(
      context,
      preview: file,
      task: (set) => prompt != null
          ? ai.applyPrompt(file, prompt, onStatus: set, demoLook: demoLook)
          : ai.enhancePhoto(file,
              variant: variant!, prefs: state.enhancerPrefs, onStatus: set),
    );
    await state.incrementUsage(key);
    await ads.showInterstitial();
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultScreen(original: file, result: result, title: title),
    ));
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
  }
}
