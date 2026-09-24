import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/makeup_service.dart';
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
      Color(0xFFB11226),
      Color(0xFFE06A4E),
      Color(0xFFC48A78),
      Color(0xFF8E2A4A),
      Color(0xFFE35D8A),
    ],
    'blush': [
      Color(0xFFE58A8A),
      Color(0xFFF0B27A),
      Color(0xFFC47A9A),
      Color(0xFFF4A4C0),
      Color(0xFFE07A5F),
    ],
    'eyeshadow': [
      Color(0xFF8D6E63),
      Color(0xFFC4A35A),
      Color(0xFF7A6A62),
      Color(0xFF6A3E6A),
      Color(0xFFD48AA0),
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
    _detect();
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

  Future<void> _detect() async {
    setState(() => _busy = true);
    final face = await detectFaceContours(widget.photo);
    if (!mounted) return;
    setState(() {
      _face = face;
      _busy = false;
    });
    if (!face.ok) {
      showSnack(context, face.message!);
      return;
    }
    _schedule();
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

  @override
  Widget build(BuildContext context) {
    final shades = _shades[_part]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final part in const ['lipstick', 'blush', 'eyeshadow', 'eyeliner', 'brows'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(part),
                    selected: _part == part,
                    onSelected: (_) => setState(() => _part = part),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: Row(
            children: [
              for (final c in shades)
                GestureDetector(
                  onTap: () {
                    setState(() => _color[_part] = c);
                    _schedule();
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color[_part] == c ? Colors.white : Colors.black26,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            const Text('Intensity'),
            Expanded(
              child: Slider(
                value: _amount[_part]!,
                onChanged: (v) => setState(() => _amount[_part] = v),
                onChangeEnd: (_) => _schedule(),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy || _face?.ok != true ? null : () => _render(commit: true),
            child: Text(_busy ? 'Working...' : 'Apply'),
          ),
        ),
      ],
    );
  }
}
