import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'color_picker.dart';
import 'fonts.dart';

enum BrushKind { pen, marker, neon, eraser }

/// One finger stroke. Points are normalized (0..1) to the stage so drawings
/// line up at any size, including the full-resolution export.
class DrawStroke {
  DrawStroke({
    required this.color,
    required this.width,
    required this.kind,
    List<Offset>? points,
  }) : points = points ?? [];

  final Color color;

  /// Fraction of the stage width.
  final double width;
  final BrushKind kind;
  final List<Offset> points;
}

class DrawSettings {
  Color color = AppColors.primary;
  double width = 0.012;
  BrushKind kind = BrushKind.pen;
}

class StrokesPainter extends CustomPainter {
  StrokesPainter(this.strokes, {this.revision = 0});
  final List<DrawStroke> strokes;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    // A layer so the eraser can cut through earlier strokes only.
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final w = s.width * size.width;
      final path = Path();
      final first = Offset(s.points.first.dx * size.width, s.points.first.dy * size.height);
      path.moveTo(first.dx, first.dy);
      if (s.points.length == 1) {
        path.lineTo(first.dx + 0.1, first.dy + 0.1);
      } else {
        // Smooth with quadratic midpoints.
        for (var i = 1; i < s.points.length; i++) {
          final a = Offset(s.points[i - 1].dx * size.width, s.points[i - 1].dy * size.height);
          final b = Offset(s.points[i].dx * size.width, s.points[i].dy * size.height);
          final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
          path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
        }
        final last = s.points.last;
        path.lineTo(last.dx * size.width, last.dy * size.height);
      }
      final base = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      switch (s.kind) {
        case BrushKind.pen:
          canvas.drawPath(path, base..color = s.color..strokeWidth = w);
        case BrushKind.marker:
          canvas.drawPath(
              path,
              base
                ..color = s.color.withValues(alpha: 0.45)
                ..strokeWidth = w * 2.2
                ..strokeCap = StrokeCap.square);
        case BrushKind.neon:
          canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..color = s.color
                ..strokeWidth = w * 2.4
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.2));
          canvas.drawPath(path, base..color = Colors.white..strokeWidth = w * 0.7);
        case BrushKind.eraser:
          canvas.drawPath(
              path,
              base
                ..color = Colors.black
                ..blendMode = BlendMode.clear
                ..strokeWidth = w * 2.2);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StrokesPainter old) => true;
}

/// Brush controls: colors (swatches + rainbow slider), size and brush type.
class DrawPanel extends StatelessWidget {
  const DrawPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onUndo,
    required this.onClear,
    required this.canUndo,
  });

  final DrawSettings settings;
  final VoidCallback onChanged;
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        Wrap(
          spacing: 0,
          runSpacing: 4,
          children: [
            for (final k in BrushKind.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: k == BrushKind.eraser ? const Icon(Icons.auto_fix_off, size: 16) : null,
                  label: Text(switch (k) {
                    BrushKind.pen => 'Pen',
                    BrushKind.marker => 'Marker',
                    BrushKind.neon => 'Neon',
                    BrushKind.eraser => 'Eraser',
                  }),
                  selected: settings.kind == k,
                  onSelected: (_) {
                    settings.kind = k;
                    onChanged();
                  },
                ),
              ),
          ],
        ),
        Row(
          children: [
            Text(settings.kind == BrushKind.eraser ? 'Drag over a drawing to erase it' : 'Brush color',
                style: TextStyle(color: palette.textSecondary, fontSize: 12)),
            const Spacer(),
            IconButton(
              tooltip: 'Undo stroke',
              onPressed: canUndo ? onUndo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Clear drawing',
              onPressed: canUndo ? onClear : null,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        if (settings.kind != BrushKind.eraser)
          ColorRow(
            selected: settings.color,
            onPick: (c) {
              settings.color = c;
              onChanged();
            },
          ),
        Row(
          children: [
            Text('Size', style: TextStyle(color: palette.textSecondary)),
            Expanded(
              child: Slider(
                value: settings.width,
                min: 0.004,
                max: 0.04,
                onChanged: (v) {
                  settings.width = v;
                  onChanged();
                },
              ),
            ),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              child: Container(
                width: 4 + settings.width * 500,
                height: 4 + settings.width * 500,
                decoration: BoxDecoration(color: settings.color, shape: BoxShape.circle,
                    border: Border.all(color: palette.border)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Swatches (tap), a "custom" button with a full picker, and light/dark
/// shades of the current color. Used by draw, text and collage.
class ColorRow extends StatelessWidget {
  const ColorRow({super.key, required this.selected, required this.onPick});
  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hsl = HSLColor.fromColor(selected);
    final shades = [
      for (final l in const [0.2, 0.35, 0.5, 0.65, 0.8, 0.92])
        hsl.withLightness(l).toColor(),
    ];
    Widget dot(Color c, {double size = 34}) {
      final sel = c.toARGB32() == selected.toARGB32();
      return GestureDetector(
        onTap: () => onPick(c),
        child: Container(
          width: size,
          height: size,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: sel ? AppColors.primary : palette.border, width: sel ? 3 : 1.2),
            boxShadow: sel ? const [BoxShadow(color: Color(0x55EA026A), blurRadius: 6)] : null,
          ),
          child: sel
              ? Icon(Icons.check, size: size * 0.5, color: c.computeLuminance() > 0.55 ? Colors.black : Colors.white)
              : null,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Custom color: opens the full picker.
              GestureDetector(
                onTap: () async {
                  final c = await showColorPickerSheet(context, selected);
                  if (c != null) onPick(c);
                },
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.fromLTRB(0, 3, 8, 3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: [
                      Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF),
                      Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
                    ]),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ),
              for (final c in [...recentColors.take(3), ...editorSwatches])
                Padding(padding: const EdgeInsets.only(right: 8), child: dot(c)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('Shade', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
            const SizedBox(width: 8),
            for (final c in shades)
              Expanded(
                child: GestureDetector(
                  onTap: () => onPick(c),
                  child: Container(
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: c.toARGB32() == selected.toARGB32() ? AppColors.primary : palette.border,
                        width: c.toARGB32() == selected.toARGB32() ? 2.5 : 1,
                      ),
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
