import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../data/catalog.dart';
import '../../l10n/l10n.dart';
import '../../services/ai_service.dart';
import '../../services/app_state.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/gallery_grid.dart';
import '../ai_filters/ai_filters_screen.dart';
import '../ai_photos/pick_preset_screen.dart';
import '../enhance/enhance_flow.dart';
import '../paywall/paywall_screen.dart';
import '../settings/settings_screen.dart';
import '../tools/quick_tool.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _videos = false;

  Future<File?> _openAsset(AssetEntity a) async {
    try {
      final direct = await a.file;
      if (direct != null) return direct;
    } catch (_) {}
    try {
      return await a.originFile;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onAsset(AssetEntity a) async {
    final file = await _openAsset(a);
    if (!mounted) return;
    if (file == null) {
      showSnack(context, 'Could not open this item.');
      return;
    }
    if (a.type == AssetType.video) {
      await startVideoEnhance(
        context,
        file,
        duration: a.videoDuration,
        thumbnail: AssetEntityImage(
          a,
          isOriginal: false,
          thumbnailSize: const ThumbnailSize.square(600),
          fit: BoxFit.cover,
        ),
      );
    } else {
      await startPhotoEnhance(context, file);
    }
  }

  Future<void> _pickFromSystem() async {
    if (_videos) {
      final f = await MediaService.pickVideo();
      if (f != null && mounted) await startVideoEnhance(context, f);
    } else {
      final f = await MediaService.pickImage();
      if (f != null && mounted) await startPhotoEnhance(context, f);
    }
  }

  void _openAiPhotos() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const PickPresetScreen()));

  void _openFilters() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const AiFiltersScreen()));

  void _allTools() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) {
        Widget tool(IconData icon, String label, VoidCallback onTap,
                {bool pro = false}) =>
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  onTap();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black26),
                  shape: const StadiumBorder(),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    if (pro) ...[
                      const SizedBox(width: 4),
                      const ProBadge(small: true),
                    ],
                  ],
                ),
              ),
            );
        Widget header(String t) => Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Text(t,
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header(context.tr('enhance')),
                Row(children: [
                  tool(Icons.auto_awesome, context.tr('enhancePhotos'),
                      () => setState(() => _videos = false)),
                  const SizedBox(width: 10),
                  tool(Icons.videocam_outlined, context.tr('enhanceVideos'),
                      () => setState(() => _videos = true),
                      pro: true),
                ]),
                const SizedBox(height: 8),
                header(context.tr('aiGeneration')),
                Row(children: [
                  tool(Icons.face_retouching_natural, context.tr('aiPhotos'), _openAiPhotos),
                  const SizedBox(width: 10),
                  tool(Icons.filter_vintage_outlined, context.tr('aiFilters'), _openFilters),
                ]),
                const SizedBox(height: 8),
                header(context.tr('restore')),
                Row(children: [
                  tool(Icons.palette_outlined, context.tr('colorize'), () {
                    runQuickTool(context,
                        title: 'Colorized',
                        prompt: colorizePrompt,
                        demoLook: 'warm');
                  }),
                  const SizedBox(width: 10),
                  tool(Icons.hd_outlined, context.tr('upscale'), () {
                    runQuickTool(context,
                        title: 'Upscaled',
                        variant: EnhanceVariant.ultra);
                  }, pro: true),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ai = context.read<AiService>();
    final tr = context.tr;
    final palette = context.palette;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  const Text(AppConfig.appName,
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  if (!state.isPro)
                    GestureDetector(
                      onTap: () => openPaywall(context),
                      child: const ProBadge(),
                    ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            if (ai.demoMode)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tr('addKeyBanner'),
                  style: TextStyle(fontSize: 12, color: palette.textPrimary),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Text(tr('enhance'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  _TabPill(
                    label: tr('photos'),
                    selected: !_videos,
                    onTap: () => setState(() => _videos = false),
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: tr('videos'),
                    selected: _videos,
                    onTap: () => setState(() => _videos = true),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                        backgroundColor: palette.surface),
                    tooltip: tr('browseGallery'),
                    onPressed: _pickFromSystem,
                    icon: const Icon(Icons.photo_library_outlined, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GalleryGrid(
                      type: _videos ? RequestType.video : RequestType.image,
                      onTap: _onAsset,
                      bottomPadding: 96 + bottomInset,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _BottomBar(
                      bottomInset: bottomInset,
                      onEnhance: () => setState(() => _videos = false),
                      onAiPhotos: _openAiPhotos,
                      onFilters: _openFilters,
                      onAllTools: _allTools,
                      enhanceLabel: tr('enhance'),
                      photosLabel: tr('aiPhotos'),
                      filtersLabel: tr('aiFilters'),
                      toolsLabel: tr('allTools'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.red : context.palette.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : context.palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.bottomInset,
    required this.onEnhance,
    required this.onAiPhotos,
    required this.onFilters,
    required this.onAllTools,
    required this.enhanceLabel,
    required this.photosLabel,
    required this.filtersLabel,
    required this.toolsLabel,
  });

  final double bottomInset;
  final VoidCallback onEnhance;
  final VoidCallback onAiPhotos;
  final VoidCallback onFilters;
  final VoidCallback onAllTools;
  final String enhanceLabel;
  final String photosLabel;
  final String filtersLabel;
  final String toolsLabel;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, VoidCallback onTap,
            {bool active = false}) =>
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: active ? AppColors.brandGradient : null,
                      color: active ? null : context.palette.surfaceHigh,
                    ),
                    child: Icon(icon, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        );
    final bg = context.palette.background;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 10, 8, 6 + bottomInset),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            bg.withValues(alpha: 0),
            bg.withValues(alpha: 0.95),
            bg,
          ],
          stops: const [0, 0.35, 1],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          item(Icons.auto_awesome, enhanceLabel, onEnhance, active: true),
          item(Icons.face_retouching_natural, photosLabel, onAiPhotos),
          item(Icons.filter_vintage_outlined, filtersLabel, onFilters),
          item(Icons.keyboard_arrow_up_rounded, toolsLabel, onAllTools),
        ],
      ),
    );
  }
}
