import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../services/ads_service.dart';
import '../../services/ai_service.dart';
import '../../services/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/processing_dialog.dart';
import '../paywall/paywall_screen.dart';
import 'ai_results_screen.dart';
import 'selfies_screen.dart';

/// Makes sure the user has an AI profile (selfies). Returns the selfie to use.
Future<File?> _ensureSelfie(BuildContext context) async {
  final state = context.read<AppState>();
  var existing = state.selfies.where((p) => File(p).existsSync()).toList();
  if (existing.isEmpty) {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SelfiesScreen()),
    );
    if (ok != true || !context.mounted) return null;
    existing = state.selfies.where((p) => File(p).existsSync()).toList();
  }
  return existing.isEmpty ? null : File(existing.first);
}

/// One photo from a single preset. Free users watch a rewarded ad.
Future<void> generateSingle(BuildContext context, PresetShot shot) async {
  final selfie = await _ensureSelfie(context);
  if (selfie == null || !context.mounted) return;
  final state = context.read<AppState>();
  if (!state.isPaid) {
    final earned = await context.read<AdsService>().showRewarded();
    if (!earned) {
      if (context.mounted) {
        showSnack(context, 'Watch the full ad to unlock this photo.');
      }
      return;
    }
    if (!context.mounted) return;
  }
  await _run(context, selfie, [shot], 'AI Photo');
}

/// The whole pack. Pro only.
Future<void> generatePack(BuildContext context, PresetPack pack) async {
  final state = context.read<AppState>();
  if (!state.isPro) {
    await openPaywall(context);
    if (!context.mounted || !state.isPro) return;
  }
  final selfie = await _ensureSelfie(context);
  if (selfie == null || !context.mounted) return;
  await _run(context, selfie, pack.shots, pack.title);
}

Future<void> _run(
  BuildContext context,
  File selfie,
  List<PresetShot> shots,
  String title,
) async {
  final state = context.read<AppState>();
  final ai = context.read<AiService>();
  final prompts = shots.map((s) => buildPresetPrompt(s, state.gender)).toList();
  try {
    final files = await runWithProgress<List<File>>(
      context,
      preview: selfie,
      initialStatus: 'Uploading your selfie...',
      task: (set) => ai.generateAiPhotos(
        selfie,
        prompts,
        onStatus: set,
        onProgress: (done, total) {
          if (total > 1 && done < total) set('Creating photo ${done + 1} of $total...');
        },
      ),
    );
    await state.addAiHistory(files.map((f) => f.path).toList());
    if (!context.mounted) return;
    if (files.length < shots.length) {
      showSnack(context,
          '${shots.length - files.length} photo(s) could not be generated.');
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AiResultsScreen(files: files, title: title),
    ));
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
  }
}
