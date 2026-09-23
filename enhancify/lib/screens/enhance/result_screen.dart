import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/ads_service.dart';
import '../../services/ai_service.dart';
import '../../services/app_state.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/before_after.dart';
import '../../widgets/common.dart';
import '../../widgets/processing_dialog.dart';
import '../paywall/paywall_screen.dart';
import 'enhance_flow.dart';

/// Shows original vs result with save / share, and (for Enhance) the
/// Enhance / Natural / Ultra HD variants.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.original,
    required this.result,
    this.title = 'Result',
    this.variant = EnhanceVariant.base,
    this.enableVariants = false,
  });

  final File original;
  final File result;
  final String title;
  final EnhanceVariant variant;
  final bool enableVariants;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late EnhanceVariant _variant = widget.variant;
  late final Map<EnhanceVariant, File> _results = {widget.variant: widget.result};
  bool _saving = false;
  bool _autoSaved = false;

  File get _current => _results[_variant] ?? widget.result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AppState>().enhancerPrefs.autoSave) {
        _save(silentLimit: true, auto: true);
      }
    });
  }

  Future<void> _save({bool silentLimit = false, bool auto = false}) async {
    if (_saving) return;
    final state = context.read<AppState>();
    final left = state.remaining(UsageKeys.save, AppConfig.freeSavesPerDay);
    if (left == 0) {
      if (silentLimit) return;
      final upgraded = await openPaywall(context);
      if (!upgraded || !mounted) return;
    }
    setState(() => _saving = true);
    final err = await MediaService.saveToGallery(_current);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err == null) {
      await state.incrementUsage(UsageKeys.save);
      if (!mounted) return;
      if (auto) setState(() => _autoSaved = true);
      showSnack(context, 'Saved to your gallery ✨');
    } else {
      showSnack(context, err);
    }
  }

  Future<void> _selectVariant(EnhanceVariant v) async {
    if (v == _variant) return;
    final state = context.read<AppState>();
    if (v.requiresPro && !state.isPro) {
      await openPaywall(context);
      if (!mounted || !state.isPro) return;
    }
    if (_results.containsKey(v)) {
      setState(() => _variant = v);
      return;
    }
    if (!v.requiresPro) {
      final ok = await ensureQuota(context,
          key: UsageKeys.enhance,
          freeLimit: AppConfig.freeEnhancementsPerDay,
          what: 'enhancements');
      if (!ok || !mounted) return;
    }
    final ai = context.read<AiService>();
    final ads = context.read<AdsService>();
    try {
      final file = await runWithProgress<File>(
        context,
        preview: widget.original,
        task: (set) => ai.enhancePhoto(widget.original,
            variant: v, prefs: state.enhancerPrefs, onStatus: set),
      );
      if (!v.requiresPro) await state.incrementUsage(UsageKeys.enhance);
      await ads.showInterstitial();
      if (!mounted) return;
      setState(() {
        _results[v] = file;
        _variant = v;
      });
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.read<AiService>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => MediaService.shareFiles([_current]),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (ai.demoMode)
            Container(
              width: double.infinity,
              color: AppColors.maroon,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: const Text(
                'Demo mode: connect your AI backend to get real results.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ColoredBox(
                  color: Colors.black,
                  child: BeforeAfter(
                    key: ValueKey(_current.path),
                    before: widget.original,
                    after: _current,
                  ),
                ),
              ),
            ),
          ),
          if (widget.enableVariants)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final v in EnhanceVariant.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: v == _variant,
                        onSelected: (_) => _selectVariant(v),
                        showCheckmark: false,
                        selectedColor: AppColors.red,
                        backgroundColor: AppColors.surface,
                        shape: const StadiumBorder(),
                        side: BorderSide.none,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(v.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            if (v.requiresPro) ...[
                              const SizedBox(width: 6),
                              const ProBadge(small: true),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: PillButton(
                label: _autoSaved ? 'Save again' : 'Save',
                kind: ButtonStyleKind.brand,
                loading: _saving,
                leading: _saving
                    ? null
                    : const Icon(Icons.download_rounded, color: Colors.white),
                onPressed: _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
