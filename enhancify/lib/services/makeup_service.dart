import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Contours for one face, in the full-resolution photo's pixel space.
class FaceContourResult {
  FaceContourResult.ok(this.contours) : message = null;

  FaceContourResult.fail(this.message) : contours = const {};

  final String? message;
  final Map<FaceContourType, List<Offset>> contours;

  bool get ok => message == null;

  List<Offset> pts(FaceContourType type) => contours[type] ?? const [];
}

/// On-device face contours. Detection uses a smaller copy; points are scaled
/// back to the full photo.
Future<FaceContourResult> detectFaceContours(Uint8List bytes) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return FaceContourResult.fail('Could not read this photo.');
  }
  final long = math.max(decoded.width, decoded.height);
  final scale = long > 1024 ? 1024 / long : 1.0;
  final small = scale < 1
      ? img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
        )
      : decoded;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/makeup_detect.jpg');
  await file.writeAsBytes(img.encodeJpg(small, quality: 85), flush: true);

  final detector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.12,
    ),
  );
  try {
    final faces = await detector.processImage(InputImage.fromFilePath(file.path));
    if (faces.isEmpty) {
      return FaceContourResult.fail('No face detected — try a clearer, front-facing photo');
    }
    if (faces.length > 1) {
      return FaceContourResult.fail('Please use a photo with one face');
    }
    final sx = decoded.width / small.width;
    final sy = decoded.height / small.height;
    final raw = faces.first.contours;
    final mapped = <FaceContourType, List<Offset>>{};
    for (final type in FaceContourType.values) {
      final contour = raw[type];
      if (contour == null || contour.points.isEmpty) continue;
      mapped[type] = [
        for (final p in contour.points) Offset(p.x * sx, p.y * sy),
      ];
    }
    const needed = [
      FaceContourType.upperLipTop,
      FaceContourType.lowerLipBottom,
      FaceContourType.leftEye,
      FaceContourType.rightEye,
      FaceContourType.face,
    ];
    if (needed.any((t) => (mapped[t] ?? const []).length < 3)) {
      return FaceContourResult.fail('No face detected — try a clearer, front-facing photo');
    }
    return FaceContourResult.ok(mapped);
  } finally {
    await detector.close();
  }
}

/// Draws makeup that follows the detected face contours. Everything is
/// scaled to the size of the face, so it looks the same on a selfie and on
/// a 12 MP photo. All effects are drawn in one pass.
class MakeupRenderer {
  Future<Uint8List> compose(
    Uint8List src,
    FaceContourResult face, {
    required Color lipstick,
    required double lipstickAmount,
    required Color blush,
    required double blushAmount,
    required Color eyeshadow,
    required double eyeshadowAmount,
    required Color eyeliner,
    required double eyelinerAmount,
    required Color brow,
    required double browAmount,
  }) async {
    final codec = await ui.instantiateImageCodec(src);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    codec.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());

    final faceBox = _bounds(face.pts(FaceContourType.face));
    // 1.0 for a face ~300 px wide.
    final s = math.max(0.4, faceBox.width / 300);
    final faceC = faceBox.center;

    if (lipstickAmount > 0) _lips(canvas, face, lipstick, lipstickAmount, s);
    if (blushAmount > 0) {
      for (final eye in [FaceContourType.leftEye, FaceContourType.rightEye]) {
        _blush(canvas, face.pts(eye), faceC, blush, blushAmount, s);
      }
    }
    if (eyeshadowAmount > 0) {
      _eyeshadow(canvas, face.pts(FaceContourType.leftEye), face.pts(FaceContourType.leftEyebrowBottom),
          eyeshadow, eyeshadowAmount, s);
      _eyeshadow(canvas, face.pts(FaceContourType.rightEye), face.pts(FaceContourType.rightEyebrowBottom),
          eyeshadow, eyeshadowAmount, s);
    }
    if (eyelinerAmount > 0) {
      _eyeliner(canvas, face.pts(FaceContourType.leftEye), faceC, eyeliner, eyelinerAmount, s);
      _eyeliner(canvas, face.pts(FaceContourType.rightEye), faceC, eyeliner, eyelinerAmount, s);
    }
    if (browAmount > 0) {
      _brow(canvas, face.pts(FaceContourType.leftEyebrowTop), face.pts(FaceContourType.leftEyebrowBottom), brow,
          browAmount, s);
      _brow(canvas, face.pts(FaceContourType.rightEyebrowTop), face.pts(FaceContourType.rightEyebrowBottom), brow,
          browAmount, s);
    }

    final picture = recorder.endRecording();
    final out = await picture.toImage(image.width, image.height);
    image.dispose();
    picture.dispose();
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    return data!.buffer.asUint8List();
  }

  // ------------------------------------------------------------- lips
  void _lips(Canvas canvas, FaceContourResult f, Color color, double k, double s) {
    final upTop = _byX(f.pts(FaceContourType.upperLipTop));
    final upBot = _byX(f.pts(FaceContourType.upperLipBottom));
    final loTop = _byX(f.pts(FaceContourType.lowerLipTop));
    final loBot = _byX(f.pts(FaceContourType.lowerLipBottom));
    if (upTop.length < 3 || loBot.length < 3) return;
    // Outer outline: top edge left→right, bottom edge right→left, sharing
    // the mouth corners so the shape can't twist.
    final left = upTop.first.dx < loBot.first.dx ? upTop.first : loBot.first;
    final right = upTop.last.dx > loBot.last.dx ? upTop.last : loBot.last;
    final outer = _smoothClosed([left, ...upTop.sublist(1, upTop.length - 1), right,
      ...loBot.reversed.toList().sublist(1, loBot.length - 1)]);
    var lips = outer;
    // Cut out the open mouth (teeth / tongue stay natural).
    if (upBot.length >= 3 && loTop.length >= 3) {
      final inner = _smoothClosed([left, ...upBot, right, ...loTop.reversed]);
      final gap = _avgGap(upBot, loTop);
      if (gap > 1.5 * s) lips = Path.combine(PathOperation.difference, outer, inner);
    }
    // Drawn straight onto the photo (no saveLayer): the color / multiply
    // blend modes must blend against the lips' pixels, not an empty layer.
    // Tint: take the lipstick's hue & saturation, keep the lips' own
    // light and shadow (like real lipstick), then deepen a little.
    canvas.drawPath(
      lips,
      Paint()
        ..color = color.withValues(alpha: (0.35 + 0.55 * k).clamp(0.0, 0.92))
        ..blendMode = BlendMode.color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.1 * s),
    );
    canvas.drawPath(
      lips,
      Paint()
        ..color = color.withValues(alpha: (0.12 + 0.38 * k).clamp(0.0, 0.6))
        ..blendMode = BlendMode.multiply
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.1 * s),
    );
  }

  double _avgGap(List<Offset> upper, List<Offset> lower) {
    // Vertical gap between the inner lip lines, around the middle.
    final uc = _center(upper), lc = _center(lower);
    return (lc.dy - uc.dy).abs();
  }

  // ------------------------------------------------------------- eyes
  /// Upper lid points (left→right) from a 16-point eye loop.
  List<Offset> _upperLid(List<Offset> eye) {
    if (eye.length < 4) return const [];
    final sorted = _byX(eye);
    final l = sorted.first, r = sorted.last;
    final lid = eye.where((p) {
      // Above the corner-to-corner line.
      final t = (p.dx - l.dx) / math.max(1e-3, r.dx - l.dx);
      final lineY = l.dy + (r.dy - l.dy) * t;
      return p.dy <= lineY + 0.5;
    }).toList();
    final out = _byX(lid);
    if (out.isEmpty || out.first != l) out.insert(0, l);
    if (out.last != r) out.add(r);
    return out;
  }

  void _eyeliner(Canvas canvas, List<Offset> eye, Offset faceC, Color color, double k, double s) {
    final lid = _upperLid(eye);
    if (lid.length < 3) return;
    final eyeW = lid.last.dx - lid.first.dx;
    // Sit just on the lash line.
    final c = _center(eye);
    final line = [
      for (final p in lid)
        p + Offset(0, -0.9 * s) + ((p - c).distance > 0 ? (p - c) / (p - c).distance * 0.6 * s : Offset.zero)
    ];
    final path = _smoothOpen(line);
    // Small wing at the outer corner (the one farther from the face center).
    final outerIsRight = (lid.last.dx - faceC.dx).abs() > (lid.first.dx - faceC.dx).abs();
    final corner = outerIsRight ? line.last : line.first;
    final dir = outerIsRight ? 1.0 : -1.0;
    final wing = Path()
      ..moveTo(corner.dx - dir * eyeW * 0.12, corner.dy - eyeW * 0.02)
      ..quadraticBezierTo(corner.dx + dir * eyeW * 0.08, corner.dy - eyeW * 0.03,
          corner.dx + dir * eyeW * (0.12 + 0.1 * k), corner.dy - eyeW * (0.08 + 0.06 * k));
    final paint = Paint()
      ..color = color.withValues(alpha: (0.55 + 0.4 * k).clamp(0.0, 0.95))
      ..style = PaintingStyle.stroke
      ..strokeWidth = eyeW * (0.035 + 0.035 * k)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.5 * s);
    canvas.drawPath(path, paint);
    canvas.drawPath(wing, paint..strokeWidth = eyeW * (0.03 + 0.025 * k));
  }

  void _eyeshadow(Canvas canvas, List<Offset> eye, List<Offset> browBottom, Color color, double k, double s) {
    final lid = _upperLid(eye);
    if (lid.length < 3) return;
    final brow = _byX(browBottom);
    final eyeW = lid.last.dx - lid.first.dx;
    // Upper edge: ~45% of the way from lid to brow (the crease area).
    double browY(double x) {
      if (brow.length < 2) return lid.map((p) => p.dy).reduce(math.min) - eyeW * 0.45;
      for (var i = 0; i < brow.length - 1; i++) {
        final a = brow[i], b = brow[i + 1];
        if (x >= a.dx && x <= b.dx) return a.dy + (b.dy - a.dy) * ((x - a.dx) / math.max(1e-3, b.dx - a.dx));
      }
      return x < brow.first.dx ? brow.first.dy : brow.last.dy;
    }

    final top = [for (final p in lid) Offset(p.dx, p.dy + (browY(p.dx) - p.dy) * 0.5)];
    final path = _smoothClosed([...lid, ...top.reversed]);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: (0.18 + 0.4 * k).clamp(0.0, 0.6))
        ..blendMode = BlendMode.multiply
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, eyeW * 0.09),
    );
  }

  void _brow(Canvas canvas, List<Offset> top, List<Offset> bottom, Color color, double k, double s) {
    final t = _byX(top), b = _byX(bottom);
    if (t.length < 2 || b.length < 2) return;
    final path = _smoothClosed([...t, ...b.reversed]);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: (0.25 + 0.4 * k).clamp(0.0, 0.65))
        ..blendMode = BlendMode.multiply
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.4 * s),
    );
  }

  // ------------------------------------------------------------- cheeks
  void _blush(Canvas canvas, List<Offset> eye, Offset faceC, Color color, double k, double s) {
    if (eye.length < 4) return;
    final sorted = _byX(eye);
    final eyeW = sorted.last.dx - sorted.first.dx;
    final eyeC = _center(eye);
    final outward = eyeC.dx >= faceC.dx ? 1.0 : -1.0;
    // Apples of the cheeks: below the eye, slightly toward the ear.
    final cheek = Offset(eyeC.dx + outward * eyeW * 0.35, eyeC.dy + eyeW * 1.15);
    final radius = eyeW * 0.95;
    final rect = Rect.fromCenter(center: cheek, width: radius * 2.1, height: radius * 1.5);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(cheek, radius, [
          color.withValues(alpha: (0.45 * k).clamp(0.0, 0.5)),
          color.withValues(alpha: 0),
        ])
        ..blendMode = BlendMode.multiply,
    );
  }

  // ------------------------------------------------------------ helpers
  List<Offset> _byX(List<Offset> pts) => List<Offset>.of(pts)..sort((a, b) => a.dx.compareTo(b.dx));

  Rect _bounds(List<Offset> pts) {
    if (pts.isEmpty) return const Rect.fromLTWH(0, 0, 300, 300);
    var l = pts.first.dx, t = pts.first.dy, r = l, b = t;
    for (final p in pts) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Closed Catmull-Rom spline through the points (soft, natural outline).
  Path _smoothClosed(List<Offset> p) {
    final n = p.length;
    final path = Path();
    if (n < 3) return path;
    path.moveTo(p[0].dx, p[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  Path _smoothOpen(List<Offset> p) {
    final n = p.length;
    final path = Path()..moveTo(p[0].dx, p[0].dy);
    for (var i = 0; i < n - 1; i++) {
      final p0 = p[math.max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[math.min(n - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  Offset _center(List<Offset> pts) {
    var x = 0.0, y = 0.0;
    for (final p in pts) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / pts.length, y / pts.length);
  }
}
