import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../editor/mask_painter.dart';
import '../../l10n/l10n.dart';
import '../../services/object_remover.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

enum _Mode { brush, lasso, erase, move }

/// Remove objects: brush over them or circle them with the lasso, then tap
/// Remove. Returns the cleaned photo (or null if cancelled).
class RemoveObjectScreen extends StatefulWidget {
  const RemoveObjectScreen({super.key, required this.photo});

  final Uint8List photo;

  static Future<Uint8List?> open(BuildContext context, Uint8List photo) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'remove'),
        builder: (_) => RemoveObjectScreen(photo: photo),
      ),
    );
  }

  @override
  State<RemoveObjectScreen> createState() => _RemoveObjectScreenState();
}

class _RemoveObjectScreenState extends State<RemoveObjectScreen> {
  late Uint8List _current = widget.photo;
  final List<Uint8List> _history = [];
  final List<MaskOp> _ops = [];
  final _viewer = TransformationController();
  _Mode _mode = _Mode.brush;
  double _brush = 0.03;
  FillMode _fill = FillMode.texture;
  double _aspect = 1;
  bool _busy = false;
  bool _showOriginal = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _readAspect(_current);
  }

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  Future<void> _readAspect(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final f = await codec.getNextFrame();
      final a = f.image.width / f.image.height;
      f.image.dispose();
      codec.dispose();
      if (mounted) setState(() => _aspect = a);
    } catch (_) {}
  }

  Offset _norm(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  void _start(Offset p) {
    final kind = switch (_mode) {
      _Mode.lasso => MaskOpKind.lasso,
      _Mode.erase => MaskOpKind.erase,
      _ => MaskOpKind.brush,
    };
    setState(() => _ops.add(MaskOp(kind, _brush, [p])));
  }

  void _extend(Offset p) {
    if (_ops.isEmpty) return;
    final pts = _ops.last.points;
    // Skip tiny moves to keep masks light.
    if ((pts.last - p).distance < 0.002) return;
    setState(() => pts.add(p));
  }

  void _end() {
    if (_ops.isEmpty) return;
    final last = _ops.last;
    if (last.kind == MaskOpKind.lasso && last.points.length < 3) {
      setState(() => _ops.removeLast());
    }
  }

  bool get _hasMarks => _ops.any((o) => o.kind != MaskOpKind.erase && o.points.isNotEmpty);

  Future<void> _remove({required bool ai}) async {
    if (!_hasMarks) {
      showSnack(context, 'Brush over or circle what you want to remove.');
      return;
    }
    setState(() {
      _busy = true;
      _status = ai ? 'AI is filling the area…' : 'Removing…';
    });
    try {
      final ops = List<MaskOp>.of(_ops);
      final out = ai ? await removeMarkedWithAi(_current, ops) : await removeMarked(_current, ops, mode: _fill);
      if (!mounted) return;
      setState(() {
        _history.add(_current);
        if (_history.length > 10) _history.removeAt(0);
        _current = out;
        _ops.clear();
      });
      _readAspect(out);
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : 'Could not remove that area. Try a smaller mark.';
      showSnack(context, msg);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  void _undo() {
    if (_ops.isNotEmpty) {
      setState(() => _ops.removeLast());
    } else if (_history.isNotEmpty) {
      setState(() => _current = _history.removeLast());
      _readAspect(_current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final drawing = _mode != _Mode.move;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('removeObject')),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _busy || (_ops.isEmpty && _history.isEmpty) ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _busy || _history.isEmpty ? null : () => Navigator.of(context).pop(_current),
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
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _aspect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: InteractiveViewer(
                        transformationController: _viewer,
                        panEnabled: !drawing,
                        scaleEnabled: !drawing,
                        maxScale: 6,
                        child: LayoutBuilder(builder: (context, box) {
                          final size = box.biggest;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: drawing && !_busy ? (d) => _start(_norm(d.localPosition, size)) : null,
                            onPanUpdate: drawing && !_busy ? (d) => _extend(_norm(d.localPosition, size)) : null,
                            onPanEnd: drawing ? (_) => _end() : null,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  _showOriginal ? widget.photo : _current,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                                if (!_showOriginal) CustomPaint(painter: MaskOpsPainter(_ops)),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_busy)
              Column(
                children: [
                  const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
                  Padding(padding: const EdgeInsets.all(4), child: Text(_status)),
                ],
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _modeButton(_Mode.brush, Icons.brush, 'Brush'),
                  _modeButton(_Mode.lasso, Icons.gesture, 'Lasso'),
                  _modeButton(_Mode.erase, Icons.auto_fix_off, 'Erase'),
                  _modeButton(_Mode.move, Icons.pan_tool_outlined, 'Zoom'),
                  GestureDetector(
                    onTapDown: (_) => setState(() => _showOriginal = true),
                    onTapUp: (_) => setState(() => _showOriginal = false),
                    onTapCancel: () => setState(() => _showOriginal = false),
                    child: _iconLabel(Icons.compare, 'Hold', palette.textSecondary, palette.surface),
                  ),
                ],
              ),
            ),
            if (_mode == _Mode.brush || _mode == _Mode.erase)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('Size', style: TextStyle(fontWeight: FontWeight.w600)),
                    Expanded(
                      child: Slider(
                        value: _brush,
                        min: 0.008,
                        max: 0.09,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _brush = v),
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      child: Container(
                        width: 6 + _brush * 240,
                        height: 6 + _brush * 240,
                        decoration: const BoxDecoration(color: Color(0x88EA026A), shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _mode == _Mode.lasso
                      ? 'Draw a loop around the object.'
                      : 'Pinch to zoom, drag to move.',
                  style: TextStyle(color: palette.textSecondary),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PopupMenuButton<FillMode>(
                    tooltip: 'Fill type',
                    initialValue: _fill,
                    onSelected: (m) => setState(() => _fill = m),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: FillMode.texture, child: Text('Texture fill (objects, grass, walls)')),
                      PopupMenuItem(value: FillMode.smooth, child: Text('Smooth fill (spots, plain areas)')),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.tune, size: 16),
                      label: Text(_fill == FillMode.texture ? 'Texture' : 'Smooth'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear marks',
                    onPressed: _busy || _ops.isEmpty ? null : () => setState(_ops.clear),
                    icon: const Icon(Icons.layers_clear),
                  ),
                  if (AppConfig.useCloudflare) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                      onPressed: _busy || !_hasMarks ? null : () => _remove(ai: true),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('AI remove'),
                    ),
                  ],
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    onPressed: _busy || !_hasMarks ? null : () => _remove(ai: false),
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(_Mode m, IconData icon, String label) {
    final sel = _mode == m;
    final palette = context.palette;
    return GestureDetector(
      onTap: () {
        setState(() => _mode = m);
        if (m != _Mode.move && _viewer.value.getMaxScaleOnAxis() <= 1.01) {
          _viewer.value = Matrix4.identity();
        }
      },
      child: _iconLabel(icon, label, sel ? Colors.white : AppColors.primary,
          sel ? AppColors.primary : palette.surface),
    );
  }

  Widget _iconLabel(IconData icon, String label, Color fg, Color bg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 21, backgroundColor: bg, child: Icon(icon, color: fg, size: 20)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
