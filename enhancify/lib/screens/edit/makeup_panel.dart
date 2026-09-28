import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../editor/color_picker.dart';
import '../../services/makeup_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Makeup controls. Detection runs once per photo. The slider is debounced.
class MakeupPanel extends StatefulWidget {
  const MakeupPanel({
    super.key,
    required this.photo,
    required this.onPreview,
    required this.onApply,
  });

  final Uint8List photo;
  final ValueChanged<Uint8List> onPreview;
  final ValueChanged<Uint8List> onApply;

  @override
  State<MakeupPanel> createState() => _MakeupPanelState();
}

class _MakeupPanelState extends State<MakeupPanel> {
  final _renderer = MakeupRenderer();
  FaceContourResult? _face;
  bool _busy = false;
  String _part = 'lipstick';
  Timer? _debounce;
  int _token = 0;

  final _amount = <String, double>{
    'lipstick': 0.7,
    'blush': 0,
    'eyeshadow': 0,
    'eyeliner': 0,
    'brows': 0,
  };
  final _color = <String, Color>{
    'lipstick': const Color(0xFFB11226),
    'blush': const Color(0xFFE58A8A),
    'eyeshadow': const Color(0xFF8D6E63),
    'eyeliner': const Color(0xFF1A1A1A),
    'brows': const Color(0xFF3E2723),
  };

  static const _shades = <String, List<Color>>{
    'lipstick': [
      Color(0xFFB11226), Color(0xFFD7263D), Color(0xFFE35D8A), Color(0xFFEA026A),
      Color(0xFFC2185B), Color(0xFF8E2A4A), Color(0xFF6D1B3B), Color(0xFFE06A4E),
      Color(0xFFD9826B), Color(0xFFC48A78), Color(0xFFB5695A), Color(0xFF9C4F46),
      Color(0xFFF08A9C), Color(0xFF7B2D26),
    ],
    'blush': [
      Color(0xFFE58A8A), Color(0xFFF4A4C0), Color(0xFFFF8FAB), Color(0xFFF0B27A),
      Color(0xFFE07A5F), Color(0xFFC47A9A), Color(0xFFD96C75), Color(0xFFB85C5C),
    ],
    'eyeshadow': [
      Color(0xFF8D6E63), Color(0xFFC4A35A), Color(0xFFB08968), Color(0xFF7A6A62),
      Color(0xFF6A3E6A), Color(0xFFD48AA0), Color(0xFF9C6644), Color(0xFF4A3B5C),
      Color(0xFF3E5C76), Color(0xFF5B7F5E), Color(0xFFB76E79),
    ],
    'eyeliner': [
      Color(0xFF1A1A1A),
      Color(0xFF4E342E),
      Color(0xFF1A237E),
      Color(0xFF37474F),
      Color(0xFF4A148C),
    ],
    'brows': [
      Color(0xFF1A1A1A),
      Color(0xFF3E2723),
      Color(0xFF6D4C41),
      Color(0xFF8D4B32),
      Color(0xFF263238),
    ],
  };

  @override
  void initState() {
    super.initState();
    // No setState inside initState: mark busy directly.
    _busy = true;
    _detect(initial: true);
  }

  @override
  void didUpdateWidget(MakeupPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo != widget.photo) _detect();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _detect({bool initial = false}) async {
    if (!initial) setState(() => _busy = true);
    FaceContourResult face;
    try {
      face = await detectFaceContours(widget.photo);
    } catch (_) {
      face = FaceContourResult.fail('Face detection failed on this photo.');
    }
    if (!mounted) return;
    setState(() {
      _face = face;
      _busy = false;
    });
    if (!face.ok) {
      showSnack(context, face.message!);
      return;
    }
    // After "Apply" the new photo already has the makeup; only preview
    // again if something is still dialed in.
    if (_amount.values.any((v) => v > 0)) _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _render);
  }

  Future<void> _render({bool commit = false}) async {
    final face = _face;
    if (face == null || !face.ok) return;
    final token = ++_token;
    setState(() => _busy = true);
    try {
      final bytes = await _renderer.compose(
        widget.photo,
        face,
        lipstick: _color['lipstick']!,
        lipstickAmount: _amount['lipstick']!,
        blush: _color['blush']!,
        blushAmount: _amount['blush']!,
        eyeshadow: _color['eyeshadow']!,
        eyeshadowAmount: _amount['eyeshadow']!,
        eyeliner: _color['eyeliner']!,
        eyelinerAmount: _amount['eyeliner']!,
        brow: _color['brows']!,
        browAmount: _amount['brows']!,
      );
      if (!mounted || token != _token) return;
      if (commit) {
        // The makeup is now part of the photo: reset so it isn't applied twice.
        setState(() => _amount.updateAll((k, v) => 0));
        widget.onApply(bytes);
      } else {
        widget.onPreview(bytes);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Makeup could not be applied.');
    } finally {
      if (mounted && token == _token) setState(() => _busy = false);
    }
  }

  static const _labels = {
    'lipstick': ('Lipstick', Icons.favorite),
    'blush': ('Blush', Icons.circle),
    'eyeshadow': ('Eyeshadow', Icons.visibility),
    'eyeliner': ('Eyeliner', Icons.edit),
    'brows': ('Brows', Icons.horizontal_rule),
  };

  void _pick(Color c) {
    setState(() {
      _color[_part] = c;
      // Picking a color should show it, even if the slider was at zero.
      if (_amount[_part]! < 0.05) _amount[_part] = 0.6;
    });
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shades = _shades[_part]!;
    final current = _color[_part]!;
    final custom = !shades.any((c) => c.toARGB32() == current.toARGB32());
    Widget dot(Color c) {
      final sel = c.toARGB32() == current.toARGB32();
      return GestureDetector(
        onTap: () => _pick(c),
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: sel ? AppColors.primary : palette.border, width: sel ? 3 : 1.2),
            boxShadow: sel ? const [BoxShadow(color: Color(0x55EA026A), blurRadius: 6)] : null,
          ),
          child: sel ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final part in _labels.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: Icon(_labels[part]!.$2,
                        size: 14, color: _part == part ? Colors.white : AppColors.primary),
                    label: Text(_labels[part]!.$1),
                    selected: _part == part,
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _part == part ? Colors.white : palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _part = part),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: () async {
                  final c = await showColorPickerSheet(context, current);
                  if (c != null && mounted) _pick(c);
                },
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(colors: [
                      Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF),
                      Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
                    ]),
                    border: custom ? Border.all(color: AppColors.primary, width: 3) : null,
                  ),
                  child: const Icon(Icons.colorize, color: Colors.white, size: 16),
                ),
              ),
              if (custom) dot(current),
              for (final c in shades) dot(c),
            ],
          ),
        ),
        Row(
          children: [
            SizedBox(
              width: 70,
              child: Text('Intensity', style: TextStyle(color: palette.textSecondary, fontSize: 13)),
            ),
            Expanded(
              child: Slider(
                value: _amount[_part]!,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _amount[_part] = v),
                onChangeEnd: (_) => _schedule(),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text('${(_amount[_part]! * 100).round()}%', textAlign: TextAlign.end),
            ),
          ],
        ),
        Row(
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() => _amount.updateAll((k, v) => 0));
                      _schedule();
                    },
              child: const Text('Remove all'),
            ),
            const Spacer(),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _busy || _face?.ok != true ? null : () => _render(commit: true),
              child: const Text('Apply makeup'),
            ),
          ],
        ),
      ],
    );
  }
}
