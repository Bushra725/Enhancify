import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../avatar/avatar_painter.dart';
import '../theme/app_theme.dart';
import 'layers.dart';
import 'text_view.dart';

/// Draws all overlay layers of a photo/collage and lets the user move,
/// pinch-zoom and rotate them. One finger drags; two fingers scale + rotate;
/// the corner handle scales + rotates with one finger.
///
/// The parent owns [layers] and rebuilds on [onChanged].
class LayerStage extends StatefulWidget {
  const LayerStage({
    super.key,
    required this.layers,
    required this.selectedId,
    required this.onSelect,
    required this.onChanged,
    this.onEditText,
    this.interactive = true,
  });

  final List<OverlayLayer> layers;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onChanged;
  final ValueChanged<OverlayLayer>? onEditText;
  final bool interactive;

  @override
  State<LayerStage> createState() => _LayerStageState();
}

class _LayerStageState extends State<LayerStage> {
  double _startScale = 1;
  double _startRotation = 0;
  // One-finger corner handle.
  double _handleStartDist = 1;
  double _handleStartAngle = 0;

  void _bringToFront(OverlayLayer l) {
    final list = widget.layers;
    if (list.isNotEmpty && list.last.id != l.id) {
      list.remove(l);
      list.add(l);
    }
  }

  void _select(OverlayLayer l) {
    _bringToFront(l);
    widget.onSelect(l.id);
    widget.onChanged();
  }

  void _delete(OverlayLayer l) {
    widget.layers.remove(l);
    widget.onSelect(null);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
        return const SizedBox.shrink();
      }
      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (final l in widget.layers)
            Positioned(
              key: ValueKey(l.id),
              left: l.center.dx * w,
              top: l.center.dy * h,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: Transform.rotate(
                  angle: l.rotation,
                  child: Transform.scale(
                    scale: l.scale,
                    child: _gestures(l, w, h, _decorated(l, w)),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _gestures(OverlayLayer l, double w, double h, Widget child) {
    if (!widget.interactive) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (widget.selectedId == l.id && l.kind == LayerKind.text) {
          widget.onEditText?.call(l);
        } else {
          _select(l);
        }
      },
      onScaleStart: (d) {
        _startScale = l.scale;
        _startRotation = l.rotation;
        if (widget.selectedId != l.id) _select(l);
      },
      onScaleUpdate: (d) {
        l.center = Offset(
          (l.center.dx + d.focalPointDelta.dx / w).clamp(0.0, 1.0),
          (l.center.dy + d.focalPointDelta.dy / h).clamp(0.0, 1.0),
        );
        if (d.pointerCount > 1) {
          l.scale = _startScale * d.scale;
          l.clampScale();
          l.rotation = _startRotation + d.rotation;
        }
        widget.onChanged();
      },
      onScaleEnd: (_) {
        l.normalizeRotation();
        widget.onChanged();
      },
      child: child,
    );
  }

  /// The layer content plus selection chrome. Selected and unselected
  /// layers have the same size, and every handle sits inside the layer's
  /// bounds so it can be tapped.
  Widget _decorated(OverlayLayer l, double stageW) {
    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: LayerContent(layer: l, stageWidth: stageW),
    );
    if (!widget.interactive || widget.selectedId != l.id) return content;
    // Keep handles a usable size at any zoom without swamping small layers.
    final inv = (1 / l.scale).clamp(0.4, 2.0);
    Widget corner({double? left, double? top, double? right, double? bottom, required Widget child}) =>
        Positioned(
          left: left,
          top: top,
          right: right,
          bottom: bottom,
          width: 28,
          height: 28,
          child: Transform.scale(scale: inv, child: child),
        );
    return Stack(
      children: [
        content,
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              margin: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                border: Border.all(
                    color: AppColors.primary, width: math.max(1.0, 2 * inv)),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        corner(left: 0, top: 0, child: _handle(Icons.close, () => _delete(l))),
        if (l.kind == LayerKind.text)
          corner(
              right: 0,
              top: 0,
              child: _handle(Icons.edit, () => widget.onEditText?.call(l))),
        corner(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              final c = _centerGlobal(l);
              if (c == null) return;
              final v = d.globalPosition - c;
              _handleStartDist = math.max(8, v.distance);
              _handleStartAngle = math.atan2(v.dy, v.dx);
              _startScale = l.scale;
              _startRotation = l.rotation;
            },
            onPanUpdate: (d) {
              final c = _centerGlobal(l);
              if (c == null) return;
              final v = d.globalPosition - c;
              l.scale = _startScale * (v.distance / _handleStartDist);
              l.clampScale();
              l.rotation =
                  _startRotation + (math.atan2(v.dy, v.dx) - _handleStartAngle);
              widget.onChanged();
            },
            onPanEnd: (_) {
              l.normalizeRotation();
              widget.onChanged();
            },
            child: _handleBody(Icons.open_in_full_rounded),
          ),
        ),
      ],
    );
  }

  Offset? _centerGlobal(OverlayLayer l) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(
        Offset(l.center.dx * box.size.width, l.center.dy * box.size.height));
  }

  Widget _handle(IconData icon, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _handleBody(icon),
      );

  Widget _handleBody(IconData icon) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Icon(icon, size: 16, color: AppColors.primary),
      );
}

/// Visual content of a layer without any interaction chrome.
class LayerContent extends StatelessWidget {
  const LayerContent({super.key, required this.layer, required this.stageWidth});

  final OverlayLayer layer;
  final double stageWidth;

  @override
  Widget build(BuildContext context) {
    final base = stageWidth * layer.baseFraction;
    switch (layer.kind) {
      case LayerKind.text:
        return TextLayerView(
          spec: layer.text!,
          fontSize: base,
          maxWidth: stageWidth * 0.9,
        );
      case LayerKind.emoji:
        return Text(layer.emoji ?? '',
            style: TextStyle(fontSize: base, height: 1.1));
      case LayerKind.sticker:
        return Image.asset(layer.asset!,
            width: base, height: base, fit: BoxFit.contain);
      case LayerKind.photo:
        return Image.memory(layer.image!,
            width: base, fit: BoxFit.contain, gaplessPlayback: true);
      case LayerKind.avatar:
        return SizedBox(
          width: base,
          height: base * AvatarPainter.aspect,
          child: CustomPaint(
            painter: AvatarPainter(layer.avatar!, pose: layer.pose ?? 'happy'),
          ),
        );
    }
  }
}
