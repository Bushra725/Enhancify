import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/l10n.dart';
import '../../services/ads_service.dart';
import '../../services/app_state.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bottom_banner.dart';
import '../../widgets/common.dart';
import '../collage/collage_screen.dart';
import '../enhance/enhance_flow.dart';
import '../paywall/paywall_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _tool = 'home';

  static const _quickTools = [
    ('beauty', Icons.face_retouching_natural, 'beauty'),
    ('bg', Icons.wallpaper, 'changeBg'),
    ('remove', Icons.cleaning_services, 'removeObject'),
    ('passport', Icons.badge_outlined, 'passport'),
    ('gif', Icons.gif_box, 'makeGif'),
    ('music', Icons.music_note, 'photoMusic'),
  ];

  /// Opens the system photo picker (no media permission needed).
  Future<void> _pickFromSystem([String? tool]) async {
    final t = tool ?? _tool;
    if (t == 'collage') {
      final files = await MediaService.pickImages(limit: 6);
      if (files.isEmpty || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'collage'),
        builder: (_) => CollageScreen(initialPhotos: files),
      ));
      return;
    }
    final f = await MediaService.pickImage();
    if (f != null && mounted) {
      await startPhotoEnhance(context, f, tool: t == 'home' ? 'edit' : t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tr = context.tr;
    final palette = context.palette;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bannerPad = state.showAds ? 54.0 : 0.0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await context.read<AdsService>().showInterstitial();
        await SystemNavigator.pop();
      },
      child: Scaffold(
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
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(tr('enhance'),
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    _TabPill(
                      label: tr('photos'),
                      selected: true,
                      onTap: () => _pickFromSystem(),
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
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  children: [
                    for (final (id, icon, key) in _quickTools)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          avatar: Icon(icon,
                              size: 16,
                              color: _tool == id
                                  ? Colors.white
                                  : AppColors.primary),
                          label: Text(tr(key)),
                          selected: _tool == id,
                          showCheckmark: false,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _tool == id
                                ? Colors.white
                                : palette.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) {
                            setState(() => _tool = id);
                            _pickFromSystem(id);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _PickerHome(
                        bottomPadding: 96 + bottomInset + bannerPad,
                        tool: _tool,
                        onPick: _pickFromSystem,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.showAds)
                            const Center(child: BottomBannerAd()),
                          _BottomBar(
                            bottomInset: bottomInset,
                            tool: _tool,
                            onSelect: (tool) {
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                              if (tool == 'collage') {
                                Navigator.of(context).push(MaterialPageRoute(
                                  settings:
                                      const RouteSettings(name: 'collage'),
                                  builder: (_) => const CollageScreen(),
                                ));
                                return;
                              }
                              setState(() => _tool = tool);
                              if (tool != 'home') _pickFromSystem(tool);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    required this.onSelect,
    required this.tool,
  });

  final double bottomInset;
  final ValueChanged<String> onSelect;
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
              padding: const EdgeInsets.symmetric(vertical: 2),
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
                  const SizedBox(height: 2),
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
      padding: EdgeInsets.fromLTRB(8, 4, 8, bottomInset + 2),
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
          item(Icons.home_rounded, context.tr('home'), () => onSelect('home'),
              active: tool == 'home'),
          item(Icons.edit_outlined, context.tr('edit'), () => onSelect('edit'),
              active: tool == 'edit'),
          item(Icons.auto_fix_high, context.tr('restore'),
              () => onSelect('restore'),
              active: tool == 'restore'),
          item(Icons.grid_view_rounded, context.tr('collage'),
              () => onSelect('collage'),
              active: tool == 'collage'),
          item(Icons.auto_awesome, context.tr('enhance'),
              () => onSelect('enhance'),
              active: tool == 'enhance'),
        ],
      ),
    );
  }
}

/// Home without a gallery grid: a big "Choose a photo" card and tool tiles.
/// Every tile opens the system photo picker, so the app never needs
/// READ_MEDIA_IMAGES / READ_MEDIA_VIDEO.
class _PickerHome extends StatelessWidget {
  const _PickerHome(
      {required this.bottomPadding, required this.tool, required this.onPick});

  final double bottomPadding;
  final String tool;
  final void Function([String? tool]) onPick;

  static const _tiles = [
    ('enhance', Icons.auto_awesome, 'enhance'),
    ('edit', Icons.edit_outlined, 'edit'),
    ('restore', Icons.auto_fix_high, 'restore'),
    ('beauty', Icons.face_retouching_natural, 'beauty'),
    ('bg', Icons.wallpaper, 'changeBg'),
    ('remove', Icons.cleaning_services, 'removeObject'),
    ('collage', Icons.grid_view_rounded, 'collage'),
    ('passport', Icons.badge_outlined, 'passport'),
    ('gif', Icons.gif_box, 'makeGif'),
    ('music', Icons.music_note, 'photoMusic'),
  ];

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final palette = context.palette;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
      children: [
        Material(
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onPick(),
            child: Ink(
              decoration:
                  const BoxDecoration(gradient: AppColors.brandGradient),
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.add_photo_alternate_outlined,
                        color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('choosePhoto'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(tr('choosePhotoSub'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(tr('allTools'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            for (final (id, icon, key) in _tiles)
              Material(
                color: tool == id ? AppColors.blush : palette.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onPick(id),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: AppColors.primary, size: 28),
                        const SizedBox(height: 8),
                        Text(tr(key),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
