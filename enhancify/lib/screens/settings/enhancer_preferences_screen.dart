import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class EnhancerPreferencesScreen extends StatelessWidget {
  const EnhancerPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.enhancerPrefs;
    void set(EnhancerPrefs n) => state.setEnhancerPrefs(n);

    Widget sw(String title, String sub, bool v, ValueChanged<bool> on) =>
        SwitchListTile(
          value: v,
          onChanged: on,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub,
              style:
                  TextStyle(color: context.palette.textSecondary, fontSize: 13)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Enhancer Preferences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DarkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Face enhancement strength',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                    'Stronger gives crisper faces; Natural keeps them closer to '
                    'the original.',
                    style: TextStyle(
                        color: context.palette.textSecondary, fontSize: 13)),
                Slider(
                  // UI: left = natural, right = strong. Model fidelity is the inverse.
                  value: (1 - p.faceFidelity).clamp(0.0, 1.0),
                  onChanged: (v) => set(p.copyWith(faceFidelity: 1 - v)),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Natural',
                        style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                    Text('Strong',
                        style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DarkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Output resolution',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('Original')),
                    ButtonSegment(value: 2, label: Text('2x')),
                    ButtonSegment(value: 4, label: Text('4x')),
                  ],
                  selected: {p.upscale},
                  onSelectionChanged: (s) => set(p.copyWith(upscale: s.first)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DarkCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                sw('Enhance background', 'Also sharpen the rest of the photo.',
                    p.backgroundEnhance,
                    (v) => set(p.copyWith(backgroundEnhance: v))),
                sw('Sharpen faces', 'Upsample faces for extra detail.',
                    p.faceUpsample, (v) => set(p.copyWith(faceUpsample: v))),
                sw('Auto-save results', 'Save every enhanced photo to your gallery.',
                    p.autoSave, (v) => set(p.copyWith(autoSave: v))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => set(const EnhancerPrefs()),
            child: const Text('Reset to defaults',
                style: TextStyle(color: AppColors.redLight)),
          ),
        ],
      ),
    );
  }
}
