import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'ai_photos_flow.dart';

class PresetDetailScreen extends StatelessWidget {
  const PresetDetailScreen({super.key, required this.pack, required this.shot});

  final PresetPack pack;
  final PresetShot shot;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                GradientThumb(
                  colors: shot.colors,
                  icon: shot.icon,
                  imageUrl: shot.imageUrl,
                  radius: 0,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, context.palette.background],
                      stops: const [0.6, 1],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black54),
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: Text(
                    '${shot.title} · ${pack.title}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: [
                  Text('PRESET',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: context.palette.textSecondary)),
                  const SizedBox(height: 8),
                  const Text(
                    "We'll use the style and composition of this preset to "
                    'generate photos of yourself',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.35),
                  ),
                  const SizedBox(height: 18),
                  PillButton(
                    label: 'Use This Preset',
                    trailing: state.isPaid
                        ? const Icon(Icons.arrow_forward_ios_rounded)
                        : const Icon(Icons.play_circle_outline),
                    onPressed: () => generateSingle(context, shot),
                  ),
                  if (!state.isPaid)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Free with a short ad',
                          style: TextStyle(
                              color: context.palette.textMuted, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
