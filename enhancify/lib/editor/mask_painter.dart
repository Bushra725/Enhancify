import 'package:flutter/material.dart';

import '../services/object_remover.dart';

/// Shows brush strokes and lasso loops in translucent pink. Erase strokes
/// visibly cut the pink away, so the user sees exactly what will be filled.
class MaskOpsPainter extends CustomPainter {
  MaskOpsPainter(this.ops) : _sig = _signature(ops);

  final List<MaskOp> ops;
  final int _sig;

  static int _signature(List<MaskOp> ops) {
    var n = ops.length;
    for (final o in ops) {
      n = n * 31 + o.points.length;
    }
    return n;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (ops.isEmpty) return;
    canvas.saveLayer(Offset.zero & size, Paint());
    const pink = Color(0xFFEA026A);
    for (final op in ops) {
      if (op.points.isEmpty) continue;
      final pts = [for (final p in op.points) Offset(p.dx * size.width, p.dy * size.height)];
      if (op.kind == MaskOpKind.lasso) {
        final path = Path()..addPolygon(pts, true);
        canvas.drawPath(path, Paint()..color = pink.withValues(alpha: 0.45));
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        continue;
      }
      final erase = op.kind == MaskOpKind.erase;
      final w = size.width * op.width * 2;
      final paint = Paint()
        ..color = erase ? Colors.black : pink.withValues(alpha: 0.5)
        ..blendMode = erase ? BlendMode.clear : BlendMode.src
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (pts.length == 1) {
        canvas.drawCircle(pts.first, w / 2, paint..style = PaintingStyle.fill);
      } else {
        canvas.drawPath(Path()..addPolygon(pts, false), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MaskOpsPainter old) => old._sig != _sig || !identical(old.ops, ops);
}
