import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/l10n.dart';
import '../../services/app_state.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/gallery_grid.dart';
import '../enhance/enhance_flow.dart';
import '../paywall/paywall_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _tool = 'enhance';

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
    await startPhotoEnhance(context, file, tool: _tool);
  }

  Future<void> _pickFromSystem() async {
    final f = await MediaService.pickImage();
    if (f != null && mounted) await startPhotoEnhance(context, f, tool: _tool);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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
                    selected: true,
                    onTap: () {},
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
                      type: RequestType.image,
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
                      onEnhance: () => setState(() => _tool = 'enhance'),
                      onRestore: () => setState(() => _tool = 'restore'),
                      onCrop: () => setState(() => _tool = 'crop'),
                      onRotate: () => setState(() => _tool = 'rotate'),
                      tool: _tool,
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
    required this.onRestore,
    required this.onCrop,
    required this.onRotate,
    required this.tool,
  });

  final double bottomInset;
  final VoidCallback onEnhance;
  final VoidCallback onRestore;
  final VoidCallback onCrop;
  final VoidCallback onRotate;
  final String tool;

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
          item(Icons.auto_awesome, 'Enhance', onEnhance, active: tool == 'enhance'),
          item(Icons.auto_fix_high, 'Restore', onRestore, active: tool == 'restore'),
          item(Icons.crop, 'Crop', onCrop, active: tool == 'crop'),
          item(Icons.rotate_right, 'Rotate', onRotate, active: tool == 'rotate'),
        ],
      ),
    );
  }
}
