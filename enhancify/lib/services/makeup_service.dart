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
  final scale = long > 640 ? 640 / long : 1.0;
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

/// Draws one makeup pass and returns a new image. Input is not changed.
class MakeupRenderer {
  Future<Uint8List> applyLipstick(
    Uint8List src,
    List<Offset> upperLipTop,
    List<Offset> lowerLipBottom,
    Color color,
    double intensity,
  ) {
    return _once(src, (canvas, _) {
      _lipstick(canvas, upperLipTop, lowerLipBottom, color, intensity);
    });
  }

  Future<Uint8List> applyEyeliner(
    Uint8List src,
    List<Offset> eye,
    Color color,
    double intensity,
  ) {
    return _once(src, (canvas, _) => _eyeliner(canvas, eye, color, intensity));
  }

  Future<Uint8List> applyEyeshadow(
    Uint8List src,
    List<Offset> eye,
    List<Offset> browBottom,
    Color color,
    double intensity,
  ) {
    return _once(src, (canvas, _) => _eyeshadow(canvas, eye, browBottom, color, intensity));
  }

  Future<Uint8List> applyBlush(
    Uint8List src,
    List<Offset> eye,
    List<Offset> faceOval,
    Color color,
    double intensity,
  ) {
    return _once(src, (canvas, _) => _blush(canvas, eye, faceOval, color, intensity));
  }

  Future<Uint8List> applyEyebrowTint(
    Uint8List src,
    List<Offset> browTop,
    List<Offset> browBottom,
    Color color,
    double intensity,
  ) {
    return _once(src, (canvas, _) => _brow(canvas, browTop, browBottom, color, intensity));
  }

  /// Lipstick, blush, eyeshadow, eyeliner, then brows. Each pass uses the
  /// previous bitmap, so the effects stack.
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
    var current = src;
    if (lipstickAmount > 0) {
      current = await applyLipstick(
        current,
        face.pts(FaceContourType.upperLipTop),
        face.pts(FaceContourType.lowerLipBottom),
        lipstick,
        lipstickAmount,
      );
    }
    if (blushAmount > 0) {
      current = await applyBlush(current, face.pts(FaceContourType.leftEye), face.pts(FaceContourType.face), blush, blushAmount);
      current = await applyBlush(current, face.pts(FaceContourType.rightEye), face.pts(FaceContourType.face), blush, blushAmount);
    }
    if (eyeshadowAmount > 0) {
      current = await applyEyeshadow(current, face.pts(FaceContourType.leftEye), face.pts(FaceContourType.leftEyebrowBottom), eyeshadow, eyeshadowAmount);
      current = await applyEyeshadow(current, face.pts(FaceContourType.rightEye), face.pts(FaceContourType.rightEyebrowBottom), eyeshadow, eyeshadowAmount);
    }
    if (eyelinerAmount > 0) {
      current = await applyEyeliner(current, face.pts(FaceContourType.leftEye), eyeliner, eyelinerAmount);
      current = await applyEyeliner(current, face.pts(FaceContourType.rightEye), eyeliner, eyelinerAmount);
    }
    if (browAmount > 0) {
      current = await applyEyebrowTint(current, face.pts(FaceContourType.leftEyebrowTop), face.pts(FaceContourType.leftEyebrowBottom), brow, browAmount);
      current = await applyEyebrowTint(current, face.pts(FaceContourType.rightEyebrowTop), face.pts(FaceContourType.rightEyebrowBottom), brow, browAmount);
    }
    return current;
  }

  Future<Uint8List> _once(Uint8List src, void Function(Canvas canvas, Size size) draw) async {
    final codec = await ui.instantiateImageCodec(src);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    canvas.drawImage(image, Offset.zero, Paint());
    draw(canvas, size);
    final picture = recorder.endRecording();
    final out = await picture.toImage(image.width, image.height);
    image.dispose();
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    return data!.buffer.asUint8List();
  }

  void _lipstick(Canvas canvas, List<Offset> top, List<Offset> bottom, Color color, double intensity) {
    final path = _closed(top, bottom);
    if (path == null) return;
    canvas.saveLayer(path.getBounds().inflate(12), Paint());
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: (0.35 + 0.6 * intensity).clamp(0, 1))
        ..blendMode = BlendMode.multiply
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.restore();
  }

  void _eyeliner(Canvas canvas, List<Offset> eye, Color color, double intensity) {
    final upper = _offsetOut(_upper(eye), 3.5);
    if (upper.length < 2) return;
    final path = Path()..moveTo(upper.first.dx, upper.first.dy);
    for (final p in upper.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: intensity.clamp(0, 1))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 + intensity * 2.2
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  void _eyeshadow(Canvas canvas, List<Offset> eye, List<Offset> brow, Color color, double intensity) {
    final path = _closed(brow, _upper(eye));
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: (0.25 * intensity).clamp(0, 0.45))
        ..blendMode = BlendMode.multiply
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  void _blush(Canvas canvas, List<Offset> eye, List<Offset> face, Color color, double intensity) {
    if (eye.length < 3 || face.length < 4) return;
    final eyeC = _center(eye);
    final faceC = _center(face);
    final outward = eyeC - faceC;
    final cheek = eyeC + outward * 0.85 + const Offset(0, 18);
    final radius = outward.distance.clamp(28, 90).toDouble();
    final rect = Rect.fromCenter(center: cheek, width: radius * 1.7, height: radius * 1.15);
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        cheek,
        radius,
        [
          color.withValues(alpha: 0.40 * intensity.clamp(0, 1)),
          color.withValues(alpha: 0),
        ],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(rect, paint);
  }

  void _brow(Canvas canvas, List<Offset> top, List<Offset> bottom, Color color, double intensity) {
    final path = _closed(top, bottom);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: (0.35 * intensity).clamp(0, 0.55))
        ..blendMode = BlendMode.multiply
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  Path? _closed(List<Offset> a, List<Offset> b) {
    if (a.length < 2 || b.length < 2) return null;
    final path = Path()..moveTo(a.first.dx, a.first.dy);
    for (final p in a.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in b.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  List<Offset> _upper(List<Offset> eye) {
    if (eye.length < 4) return eye;
    final cy = _center(eye).dy;
    final upper = eye.where((p) => p.dy <= cy + 1).toList();
    return upper.length >= 2 ? upper : eye;
  }

  List<Offset> _offsetOut(List<Offset> pts, double px) {
    if (pts.length < 2) return pts;
    final c = _center(pts);
    return [
      for (final p in pts)
        () {
          final d = p - c;
          final len = d.distance;
          if (len < 0.1) return p;
          return p + d / len * px;
        }(),
    ];
  }

  Offset _center(List<Offset> pts) {
    var x = 0.0;
    var y = 0.0;
    for (final p in pts) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / pts.length, y / pts.length);
  }
}
