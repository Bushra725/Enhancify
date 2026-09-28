import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'collage_templates.dart';

/// Cream paper with a few soft speckles.
class PaperPainter extends CustomPainter {
  PaperPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final r = math.Random(11);
    final dot = Paint();
    final n = (size.width * size.height / 900).clamp(80, 900).toInt();
    for (var i = 0; i < n; i++) {
      dot.color = (r.nextBool() ? Colors.white : const Color(0xFF8A6A4C))
          .withValues(alpha: 0.05 + r.nextDouble() * 0.07);
      canvas.drawCircle(
          Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
          0.6 + r.nextDouble() * 1.4,
          dot);
    }
  }

  @override
  bool shouldRepaint(covariant PaperPainter old) => old.color != color;
}

/// Soft pink grid, like a notebook / the "pink bows" inspiration.
class GridPainter extends CustomPainter {
  GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final step = size.width / 12;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter old) => old.color != color;
}

/// Torn paper strips, wavy bands, "•••" dots, lines and blocks.
class DecoPainter extends CustomPainter {
  DecoPainter(this.decos);
  final List<Deco> decos;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in decos) {
      final rect = Rect.fromLTWH(
          d.x * size.width, d.y * size.height, d.w * size.width, d.h * size.height);
      final paint = Paint()..color = d.color;
      switch (d.kind) {
        case DecoKind.rect:
          canvas.drawRect(rect, paint);
        case DecoKind.line:
          canvas.drawLine(
            rect.topLeft,
            rect.bottomRight,
            paint
              ..strokeWidth = d.stroke
              ..style = PaintingStyle.stroke,
          );
        case DecoKind.dots:
          final r = math.max(1.6, size.width * 0.006);
          for (var i = 0; i < 3; i++) {
            canvas.drawCircle(
                Offset(rect.left + i * r * 3.2, rect.center.dy), r, paint);
          }
        case DecoKind.tornBand:
          canvas.drawShadow(_torn(rect, 7), Colors.black, 3, false);
          canvas.drawPath(_torn(rect, 7), paint);
          canvas.drawPath(
            _torn(rect.deflate(rect.height * 0.18), 13),
            Paint()..color = const Color(0xFFF2EEEA),
          );
        case DecoKind.wavyBand:
          canvas.drawPath(_wavy(rect), paint);
      }
    }
  }

  /// A strip with jagged top and bottom edges.
  Path _torn(Rect r, int seed) {
    final rnd = math.Random(seed);
    final p = Path()..moveTo(r.left - 2, r.top + r.height * 0.3);
    final step = math.max(6.0, r.width / 60);
    for (var x = r.left; x <= r.right + step; x += step) {
      p.lineTo(x, r.top + rnd.nextDouble() * r.height * 0.35);
    }
    p.lineTo(r.right + 2, r.bottom - r.height * 0.3);
    for (var x = r.right; x >= r.left - step; x -= step) {
      p.lineTo(x, r.bottom - rnd.nextDouble() * r.height * 0.35);
    }
    p.close();
    return p;
  }

  /// A band with gentle waves top and bottom.
  Path _wavy(Rect r) {
    final p = Path();
    const waves = 5;
    final amp = r.height * 0.12;
    final seg = r.width / waves;
    p.moveTo(r.left, r.top + amp);
    for (var i = 0; i < waves; i++) {
      final x = r.left + i * seg;
      p.quadraticBezierTo(x + seg / 4, r.top - amp * 0.2, x + seg / 2, r.top + amp);
      p.quadraticBezierTo(x + seg * 3 / 4, r.top + amp * 2.2, x + seg, r.top + amp);
    }
    p.lineTo(r.right, r.bottom - amp);
    for (var i = waves - 1; i >= 0; i--) {
      final x = r.left + i * seg;
      p.quadraticBezierTo(x + seg * 3 / 4, r.bottom + amp * 0.2, x + seg / 2, r.bottom - amp);
      p.quadraticBezierTo(x + seg / 4, r.bottom - amp * 2.2, x, r.bottom - amp);
    }
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant DecoPainter old) => old.decos != decos;
}

/// Cloud-like scalloped edge (bumps pointing out).
Path scallopPath(Size size) {
  final bump = math.max(6.0, math.min(size.width, size.height) * 0.07);
  final r = Rect.fromLTWH(bump, bump, size.width - 2 * bump, size.height - 2 * bump);
  final p = Path()..moveTo(r.left, r.top);
  void edge(Offset a, Offset b) {
    final len = (b - a).distance;
    final n = math.max(2, (len / (bump * 1.6)).ceil());
    for (var i = 1; i <= n; i++) {
      final t = i / n;
      p.arcToPoint(Offset.lerp(a, b, t)!,
          radius: Radius.circular(len / n / 2), clockwise: true);
    }
  }

  edge(r.topLeft, r.topRight);
  edge(r.topRight, r.bottomRight);
  edge(r.bottomRight, r.bottomLeft);
  edge(r.bottomLeft, r.topLeft);
  p.close();
  return p;
}

/// Rectangle with a round top.
Path archPath(Size s) {
  final rad = s.width / 2;
  return Path()
    ..moveTo(0, s.height)
    ..lineTo(0, math.min(rad, s.height))
    ..arcToPoint(Offset(s.width, math.min(rad, s.height)),
        radius: Radius.circular(rad), clockwise: true)
    ..lineTo(s.width, s.height)
    ..close();
}

class PathClipper extends CustomClipper<Path> {
  PathClipper(this.build);
  final Path Function(Size) build;

  @override
  Path getClip(Size size) => build(size);

  @override
  bool shouldReclip(covariant PathClipper oldClipper) => true;
}

class PathBorderPainter extends CustomPainter {
  PathBorderPainter(this.build, {this.color = Colors.white, this.width = 3});
  final Path Function(Size) build;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      build(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant PathBorderPainter old) => true;
}
