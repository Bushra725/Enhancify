import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'avatar_builder_screen.dart';
import 'avatar_model.dart';
import 'avatar_painter.dart';

/// Editor/collage panel: shows the user's avatar in every pose. Tapping a
/// pose adds it as a sticker. First-time users are asked to create one.
class AvatarPanel extends StatefulWidget {
  const AvatarPanel({super.key, required this.onPick});
  final void Function(AvatarConfig config, String pose) onPick;

  @override
  State<AvatarPanel> createState() => _AvatarPanelState();
}

class _AvatarPanelState extends State<AvatarPanel> {
  AvatarConfig? _config;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    AvatarStore.load().then((c) {
      if (mounted) setState(() {
        _config = c;
        _loaded = true;
      });
    });
  }

  Future<void> _edit([AvatarConfig? start]) async {
    final c = await AvatarBuilderScreen.open(context, initial: start ?? _config);
    if (c != null && mounted) setState(() => _config = c);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    final config = _config;
    if (config == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _edit(AvatarConfig.girl()),
                child: AvatarView(config: AvatarConfig.girl(), width: 56),
              ),
              GestureDetector(
                onTap: () => _edit(AvatarConfig.boy()),
                child: AvatarView(config: AvatarConfig.boy(), width: 56),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Create your avatar',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Pick girl or boy, design your cartoon, use it as stickers.',
                        style: TextStyle(color: palette.textSecondary, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary, visualDensity: VisualDensity.compact),
                          onPressed: () => _edit(AvatarConfig.girl()),
                          child: const Text('Girl'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3A7BD5), visualDensity: VisualDensity.compact),
                          onPressed: () => _edit(AvatarConfig.boy()),
                          child: const Text('Boy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('Tap a pose to add it',
                    style: TextStyle(color: palette.textSecondary, fontSize: 13)),
              ),
              TextButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit avatar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            itemCount: avatarPoseOrder.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final pose = avatarPoseOrder[i];
              return GestureDetector(
                onTap: () => widget.onPick(config.copy(), pose),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1 / AvatarPainter.aspect,
                    child: CustomPaint(painter: AvatarPainter(config, pose: pose)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
