import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

/// An official photo size. Head ratio = chin-to-crown height / photo height.
class PassportSpec {
  const PassportSpec(this.id, this.label, this.widthMm, this.heightMm, this.headRatio, this.topRatio,
      {this.widthPx, this.heightPx});
  final String id;
  final String label;
  final double widthMm;
  final double heightMm;
  final double headRatio;
  final double topRatio;
  final int? widthPx;
  final int? heightPx;

  /// Pixels at 300 dpi (print quality).
  int get pxW => widthPx ?? (widthMm / 25.4 * 300).round();
  int get pxH => heightPx ?? (heightMm / 25.4 * 300).round();
  double get aspect => pxW / pxH;
  String get sizeText => id == 'us' || id == 'india_visa'
      ? '2 × 2 in'
      : '${_mm(widthMm)} × ${_mm(heightMm)} mm';

  static String _mm(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  static const all = [
    PassportSpec('std', 'UK / EU / Schengen', 35, 45, 0.72, 0.08),
    PassportSpec('pk', 'Pakistan', 35, 45, 0.72, 0.08),
    PassportSpec('in', 'India passport', 35, 45, 0.72, 0.08),
    PassportSpec('us', 'USA passport & visa', 50.8, 50.8, 0.6, 0.1, widthPx: 600, heightPx: 600),
    PassportSpec('india_visa', 'India visa', 50.8, 50.8, 0.6, 0.1, widthPx: 600, heightPx: 600),
    PassportSpec('ca', 'Canada', 50, 70, 0.5, 0.12),
    PassportSpec('cn', 'China', 33, 48, 0.64, 0.08),
    PassportSpec('au', 'Australia', 35, 45, 0.72, 0.08),
    PassportSpec('sa', 'Saudi Arabia / UAE', 40, 60, 0.62, 0.1),
    PassportSpec('id', 'ID card 25 × 35', 25, 35, 0.68, 0.08),
  ];
}

/// The analysed photo: upright JPEG, person cut-out and face box.
class PassportSource {
  PassportSource({
    required this.photo,
    required this.cutout,
    required this.width,
    required this.height,
    required this.face,
    required this.hasPerson,
    required this.faceFound,
  });

  /// Upright photo (JPEG).
  final Uint8List photo;

  /// Person on a transparent background (PNG), or the photo if no person.
  final Uint8List cutout;
  final int width;
  final int height;

  /// Face box in [photo] pixels (may be a guess when no face is found).
  final Rect face;
  final bool hasPerson;
  final bool faceFound;
}

/// Where the photo sits in the output frame (all in output pixels).
class PassportLayout {
  const PassportLayout(this.scale, this.left, this.top);
  final double scale;
  final double left;
  final double top;
}

class PassportMaker {
  PassportMaker._();

  static Future<PassportSource> analyze(Uint8List bytes) async {
    final photo = await Isolate.run(() => _upright(bytes));
    if (photo == null) throw StateError('Could not read this photo.');
    final (jpg, w, h) = photo;
    final tmp = File('${Directory.systemTemp.path}/passport_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tmp.writeAsBytes(jpg, flush: true);

    Rect? face;
    List<double>? mask;
    var mw = 0, mh = 0;
    final detector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate));
    final segmenter = SelfieSegmenter(mode: SegmenterMode.single, enableRawSizeMask: false);
    try {
      final input = InputImage.fromFilePath(tmp.path);
      try {
        final faces = await detector.processImage(input);
        if (faces.isNotEmpty) {
          faces.sort((a, b) =>
              (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
          face = faces.first.boundingBox;
        }
      } catch (_) {}
      try {
        final m = await segmenter.processImage(input);
        if (m != null && m.confidences.isNotEmpty) {
          mask = List<double>.from(m.confidences);
          mw = m.width;
          mh = m.height;
        }
      } catch (_) {}
    } finally {
      await detector.close();
      await segmenter.close();
      try {
        await tmp.delete();
      } catch (_) {}
    }

    final hasPerson = mask != null && mask.where((c) => c > 0.5).length > mask.length * 0.03;
    final m = hasPerson ? mask : null;
    final cutout = m == null ? jpg : await Isolate.run(() => _cutout(jpg, m, mw, mh));
    final guess = Rect.fromLTWH(w * 0.33, h * 0.18, w * 0.34, h * 0.3);
    final src = PassportSource(
      photo: jpg,
      cutout: cutout,
      width: w,
      height: h,
      face: face ?? guess,
      hasPerson: hasPerson,
      faceFound: face != null,
    );
    return src;
  }

  /// Auto framing from the face box, then the user's zoom and nudge.
  /// [dx]/[dy] are fractions of the output size.
  static PassportLayout layout(PassportSource s, PassportSpec spec,
      {double zoom = 1, double dx = 0, double dy = 0, int? outW, int? outH}) {
    final w = (outW ?? spec.pxW).toDouble(), h = (outH ?? spec.pxH).toDouble();
    final f = s.face;
    // ML Kit's box runs roughly brow-to-chin; the crown sits ~45% higher.
    final headTop = f.top - f.height * 0.45;
    final headH = f.bottom - headTop;
    final base = spec.headRatio * h / headH;
    final scale = base * zoom;
    final cx = f.center.dx, cy = f.center.dy;
    // Where the face centre lands in the output.
    final anchorX = w / 2 + dx * w;
    final anchorY = spec.topRatio * h + (cy - headTop) * base + dy * h;
    return PassportLayout(scale, anchorX - cx * scale, anchorY - cy * scale);
  }

  /// Final photo at exact size (JPEG, 300 dpi).
  static Future<Uint8List> render(PassportSource s, PassportSpec spec,
      {required int bg, bool keepBackground = false, double zoom = 1, double dx = 0, double dy = 0}) {
    final l = layout(s, spec, zoom: zoom, dx: dx, dy: dy);
    final source = keepBackground || !s.hasPerson ? s.photo : s.cutout;
    final w = spec.pxW, h = spec.pxH;
    return Isolate.run(() => _render(source, w, h, l.scale, l.left, l.top, bg));
  }

  /// 6 × 4 in print sheet (1800 × 1200 px) tiled with as many copies as fit.
  static Future<Uint8List> printSheet(Uint8List single, PassportSpec spec) {
    return Isolate.run(() => _sheet(single, spec.pxW, spec.pxH));
  }
}

(Uint8List, int, int)? _upright(Uint8List bytes) {
  final d = img.decodeImage(bytes);
  if (d == null) return null;
  var im = img.bakeOrientation(d);
  const maxSide = 1600;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
  }
  return (img.encodeJpg(im, quality: 95), im.width, im.height);
}

Uint8List _cutout(Uint8List jpg, List<double> mask, int mw, int mh) {
  final src = img.decodeImage(jpg)!.convert(numChannels: 4);
  // Mask → image, blur a little for a soft hair edge.
  var m = img.Image(width: mw, height: mh, numChannels: 1);
  for (var y = 0; y < mh; y++) {
    for (var x = 0; x < mw; x++) {
      final c = mask[y * mw + x];
      final a = ((c - 0.3) / 0.4).clamp(0.0, 1.0);
      m.setPixelR(x, y, (a * 255).round());
    }
  }
  m = img.copyResize(m, width: src.width, height: src.height, interpolation: img.Interpolation.linear);
  m = img.gaussianBlur(m, radius: math.max(1, src.width ~/ 500));
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      src.getPixel(x, y).a = m.getPixel(x, y).r;
    }
  }
  return img.encodePng(src);
}

Uint8List _render(Uint8List source, int w, int h, double scale, double left, double top, int bg) {
  final src = img.decodeImage(source)!;
  final sw = math.max(1, (src.width * scale).round());
  final sh = math.max(1, (src.height * scale).round());
  final scaled = img.copyResize(src,
      width: sw, height: sh, interpolation: scale < 1 ? img.Interpolation.average : img.Interpolation.cubic);
  final br = (bg >> 16) & 0xFF, bgc = (bg >> 8) & 0xFF, bb = bg & 0xFF;
  final out = img.Image(width: w, height: h);
  img.fill(out, color: img.ColorRgb8(br, bgc, bb));
  final ox = left.round(), oy = top.round();
  final hasAlpha = scaled.numChannels == 4;
  for (var y = 0; y < h; y++) {
    final sy = y - oy;
    if (sy < 0 || sy >= sh) continue;
    for (var x = 0; x < w; x++) {
      final sx = x - ox;
      if (sx < 0 || sx >= sw) continue;
      final p = scaled.getPixel(sx, sy);
      final a = hasAlpha ? p.a / 255.0 : 1.0;
      if (a <= 0) continue;
      out.setPixelRgb(x, y, (p.r * a + br * (1 - a)).round(), (p.g * a + bgc * (1 - a)).round(),
          (p.b * a + bb * (1 - a)).round());
    }
  }
  final jpg = img.encodeJpg(out, quality: 96);
  return jpg;
}

Uint8List _sheet(Uint8List single, int pw, int ph) {
  final photo = img.decodeImage(single)!;
  // Pick the orientation that fits more copies.
  const gap = 24, margin = 36;
  int fit(int sheetW, int sheetH) =>
      ((sheetW - 2 * margin + gap) ~/ (pw + gap)) * ((sheetH - 2 * margin + gap) ~/ (ph + gap));
  final landscape = fit(1800, 1200) >= fit(1200, 1800);
  final sw = landscape ? 1800 : 1200, sh = landscape ? 1200 : 1800;
  final sheet = img.Image(width: sw, height: sh);
  img.fill(sheet, color: img.ColorRgb8(255, 255, 255));
  final cols = math.max(1, (sw - 2 * margin + gap) ~/ (pw + gap));
  final rows = math.max(1, (sh - 2 * margin + gap) ~/ (ph + gap));
  final totalW = cols * pw + (cols - 1) * gap, totalH = rows * ph + (rows - 1) * gap;
  final x0 = (sw - totalW) ~/ 2, y0 = (sh - totalH) ~/ 2;
  final line = img.ColorRgb8(200, 200, 200);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final x = x0 + c * (pw + gap), y = y0 + r * (ph + gap);
      img.compositeImage(sheet, photo, dstX: x, dstY: y);
      img.drawRect(sheet, x1: x - 1, y1: y - 1, x2: x + pw, y2: y + ph, color: line);
    }
  }
  return img.encodeJpg(sheet, quality: 95);
}
