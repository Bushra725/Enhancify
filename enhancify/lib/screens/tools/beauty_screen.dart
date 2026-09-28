import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/beauty_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Snapchat-style beauty: face-aware smoothing, glow, eyes, teeth and face
/// shape. Returns the retouched photo (full size) or null.
class BeautyScreen extends StatefulWidget {
  const BeautyScreen({super.key, required this.photo});

  final Uint8List photo;

  static Future<Uint8List?> open(BuildContext context, Uint8List photo) => Navigator.of(context)
      .push<Uint8List>(MaterialPageRoute(
        settings: const RouteSettings(name: 'beauty'),
        builder: (_) => BeautyScreen(photo: photo),
      ));

  @override
  State<BeautyScreen> createState() => _BeautyScreenState();
}

class _Feature {
  const _Feature(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

class _BeautyScreenState extends State<BeautyScreen> {
  static const _features = [
    _Feature('smooth', 'Smooth', Icons.blur_on),
    _Feature('brighten', 'Glow', Icons.wb_sunny_outlined),
    _Feature('even', 'Even tone', Icons.gradient),
    _Feature('eyes', 'Bright eyes', Icons.remove_red_eye_outlined),
    _Feature('bigEyes', 'Big eyes', Icons.visibility),
    _Feature('slim', 'Slim face', Icons.face_retouching_natural),
    _Feature('nose', 'Nose', Icons.air),
    _Feature('teeth', 'Whiten', Icons.sentiment_very_satisfied),
    _Feature('lips', 'Lips', Icons.favorite_border),
  ];

  Uint8List? _jpg;
  List<BeautyFace> _faces = const [];
  Uint8List? _preview;
  String? _error;
  bool _busy = false;
  bool _compare = false;
  String _preset = 'Natural';
  String _feature = 'smooth';
  BeautySettings _s = BeautySettings.presets['Natural']!.copy();
  Timer? _debounce;
  int _job = 0;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _analyze() async {
    try {
      final (jpg, faces) = await BeautyService.analyze(widget.photo);
      if (!mounted) return;
      setState(() {
        _jpg = jpg;
        _faces = faces;
      });
      if (faces.isEmpty) {
        setState(() => _error = 'No face found. Try a clear, front-facing photo.');
        return;
      }
      _render();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not read this photo.');
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _render);
  }

  Future<void> _render() async {
    final jpg = _jpg;
    if (jpg == null || _faces.isEmpty) return;
    final job = ++_job;
    setState(() => _busy = true);
    try {
      final out = await BeautyService.apply(jpg, _faces, _s, maxSide: 1080);
      if (!mounted || job != _job) return;
      setState(() => _preview = out);
    } catch (_) {
      if (mounted && job == _job) showSnack(context, 'Could not apply beauty to this photo.');
    } finally {
      if (mounted && job == _job) setState(() => _busy = false);
    }
  }

  Future<void> _done() async {
    final jpg = _jpg;
    if (jpg == null) return;
    setState(() => _busy = true);
    try {
      final out = await BeautyService.apply(jpg, _faces, _s);
      if (!mounted) return;
      Navigator.of(context).pop(out);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'Could not apply beauty to this photo.');
      }
    }
  }

  double _get(String id) => switch (id) {
        'smooth' => _s.smooth,
        'brighten' => _s.brighten,
        'even' => _s.even,
        'eyes' => _s.eyes,
        'bigEyes' => _s.bigEyes,
        'slim' => _s.slim,
        'nose' => _s.nose,
        'teeth' => _s.teeth,
        _ => _s.lips,
      };

  void _set(String id, double v) {
    switch (id) {
      case 'smooth':
        _s.smooth = v;
      case 'brighten':
        _s.brighten = v;
      case 'even':
        _s.even = v;
      case 'eyes':
        _s.eyes = v;
      case 'bigEyes':
        _s.bigEyes = v;
      case 'slim':
        _s.slim = v;
      case 'nose':
        _s.nose = v;
      case 'teeth':
        _s.teeth = v;
      default:
        _s.lips = v;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shown = _compare ? (_jpg ?? widget.photo) : (_preview ?? _jpg ?? widget.photo);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('beauty')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _preview == null || _busy ? null : _done,
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.memory(shown, fit: BoxFit.contain, gaplessPlayback: true),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                        child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                      )
                    else if (_jpg == null)
                      const CircularProgressIndicator(color: AppColors.primary),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: GestureDetector(
                        onTapDown: (_) => setState(() => _compare = true),
                        onTapUp: (_) => setState(() => _compare = false),
                        onTapCancel: () => setState(() => _compare = false),
                        child: const CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.compare, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                children: [
                  for (final name in BeautySettings.presets.keys)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: _preset == name,
                        showCheckmark: false,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: _preset == name ? Colors.white : palette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: _faces.isEmpty
                            ? null
                            : (_) {
                                setState(() {
                                  _preset = name;
                                  _s = BeautySettings.presets[name]!.copy();
                                });
                                _schedule();
                              },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('Off'),
                      selected: _preset == 'Off',
                      onSelected: _faces.isEmpty
                          ? null
                          : (_) {
                              setState(() {
                                _preset = 'Off';
                                _s = BeautySettings();
                              });
                              _schedule();
                            },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 74,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in _features)
                    GestureDetector(
                      onTap: () => setState(() => _feature = f.id),
                      child: SizedBox(
                        width: 70,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 21,
                              backgroundColor: _feature == f.id ? AppColors.primary : palette.surface,
                              child: Icon(f.icon, size: 20, color: _feature == f.id ? Colors.white : AppColors.primary),
                            ),
                            const SizedBox(height: 4),
                            Text(f.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, fontWeight: _feature == f.id ? FontWeight.w800 : FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text('${(_get(_feature) * 100).round()}',
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Slider(
                      value: _get(_feature),
                      activeColor: AppColors.primary,
                      onChanged: _faces.isEmpty
                          ? null
                          : (v) => setState(() {
                                _set(_feature, v);
                                _preset = 'Custom';
                              }),
                      onChangeEnd: (_) => _schedule(),
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
