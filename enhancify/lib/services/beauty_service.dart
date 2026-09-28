import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Beauty settings, all 0..1.
class BeautySettings {
  BeautySettings({
    this.smooth = 0,
    this.brighten = 0,
    this.even = 0,
    this.eyes = 0,
    this.teeth = 0,
    this.bigEyes = 0,
    this.slim = 0,
    this.nose = 0,
    this.lips = 0,
  });

  double smooth; // skin smoothing (keeps pores at low values)
  double brighten; // skin glow
  double even; // reduce redness / blotches
  double eyes; // brighten eyes
  double teeth; // whiten teeth
  double bigEyes; // enlarge eyes
  double slim; // slim cheeks & jaw
  double nose; // narrow nose
  double lips; // fuller lips color pop

  BeautySettings copy() => BeautySettings(
      smooth: smooth, brighten: brighten, even: even, eyes: eyes, teeth: teeth,
      bigEyes: bigEyes, slim: slim, nose: nose, lips: lips);

  bool get isNeutral =>
      [smooth, brighten, even, eyes, teeth, bigEyes, slim, nose, lips].every((v) => v < 0.01);

  static final presets = <String, BeautySettings>{
    'Natural': BeautySettings(smooth: 0.35, brighten: 0.2, even: 0.3, eyes: 0.2, teeth: 0.2),
    'Glow': BeautySettings(smooth: 0.5, brighten: 0.5, even: 0.4, eyes: 0.35, teeth: 0.35, lips: 0.2),
    'Snap': BeautySettings(smooth: 0.6, brighten: 0.35, even: 0.45, eyes: 0.4, teeth: 0.4, bigEyes: 0.3, slim: 0.35, nose: 0.2),
    'Doll': BeautySettings(smooth: 0.7, brighten: 0.35, even: 0.5, eyes: 0.45, teeth: 0.3, bigEyes: 0.55, slim: 0.45, nose: 0.3, lips: 0.3),
    'Soft': BeautySettings(smooth: 0.8, brighten: 0.25, even: 0.6, eyes: 0.15),
    'Sculpt': BeautySettings(smooth: 0.3, slim: 0.6, nose: 0.4, eyes: 0.25),
  };
}

/// One face as plain point lists (photo pixels), sendable to isolates.
class BeautyFace {
  BeautyFace(this.pts);
  final Map<String, List<(double, double)>> pts;
  List<(double, double)> operator [](String k) => pts[k] ?? const [];
}

class BeautyService {
  BeautyService._();

  /// Upright photo (≤ 2400 px) + all faces found in it.
  static Future<(Uint8List, List<BeautyFace>)> analyze(Uint8List bytes) async {
    final up = await Isolate.run(() => _upright(bytes));
    if (up == null) throw StateError('Could not read this photo.');
    final (jpg, small, sx, sy) = up;
    final tmp = File('${Directory.systemTemp.path}/beauty_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tmp.writeAsBytes(small, flush: true);
    final detector = FaceDetector(
      options: FaceDetectorOptions(enableContours: true, performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.08),
    );
    final faces = <BeautyFace>[];
    try {
      final found = await detector.processImage(InputImage.fromFilePath(tmp.path));
      for (final f in found) {
        final m = <String, List<(double, double)>>{};
        for (final t in FaceContourType.values) {
          final c = f.contours[t];
          if (c == null || c.points.isEmpty) continue;
          m[t.name] = [for (final p in c.points) (p.x * sx, p.y * sy)];
        }
        if ((m['face'] ?? const []).length >= 10) faces.add(BeautyFace(m));
      }
    } finally {
      await detector.close();
      try {
        await tmp.delete();
      } catch (_) {}
    }
    return (jpg, faces);
  }

  /// Applies [s] to every face. [maxSide] < photo size gives a fast preview.
  static Future<Uint8List> apply(Uint8List jpg, List<BeautyFace> faces, BeautySettings s, {int? maxSide}) {
    final settings = s.copy();
    return Isolate.run(() => _apply(jpg, faces, settings, maxSide));
  }
}

(Uint8List, Uint8List, double, double)? _upright(Uint8List bytes) {
  final d = img.decodeImage(bytes);
  if (d == null) return null;
  var im = img.bakeOrientation(d);
  const maxSide = 2400;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
  }
  if (im.numChannels != 3) im = im.convert(numChannels: 3);
  final long = math.max(im.width, im.height);
  final sc = long > 1280 ? 1280 / long : 1.0;
  final small = sc < 1
      ? img.copyResize(im, width: (im.width * sc).round(), height: (im.height * sc).round())
      : im;
  return (img.encodeJpg(im, quality: 95), img.encodeJpg(small, quality: 90), im.width / small.width,
      im.height / small.height);
}

// ------------------------------------------------------------------ core

Uint8List _apply(Uint8List jpg, List<BeautyFace> faces, BeautySettings s, int? maxSide) {
  var im = img.decodeImage(jpg)!;
  var k = 1.0;
  if (maxSide != null && math.max(im.width, im.height) > maxSide) {
    k = maxSide / math.max(im.width, im.height);
    im = img.copyResize(im, width: (im.width * k).round(), height: (im.height * k).round(),
        interpolation: img.Interpolation.average);
  }
  if (im.numChannels != 3) im = im.convert(numChannels: 3);
  for (final f in faces) {
    final face = _Face.from(f, k);
    if (face == null) continue;
    // Shape first (warps), then color work on the warped face.
    if (s.slim > 0.01 || s.bigEyes > 0.01 || s.nose > 0.01) {
      im = _warp(im, face, s);
    }
    _retouch(im, face, s);
  }
  return img.encodeJpg(im, quality: 94);
}

typedef _P = (double, double);

class _Face {
  _Face(this.oval, this.leftEye, this.rightEye, this.leftBrow, this.rightBrow, this.lipsOuter, this.mouthInner,
      this.noseBridge, this.noseBottom);

  final List<_P> oval, leftEye, rightEye, leftBrow, rightBrow, lipsOuter, mouthInner, noseBridge, noseBottom;

  static _Face? from(BeautyFace f, double k) {
    List<_P> g(String n) => [for (final (x, y) in f[n]) (x * k, y * k)];
    final oval = g('face');
    if (oval.length < 10) return null;
    List<_P> byX(List<_P> l) => List.of(l)..sort((a, b) => a.$1.compareTo(b.$1));
    final upTop = byX(g('upperLipTop')), loBot = byX(g('lowerLipBottom'));
    final upBot = byX(g('upperLipBottom')), loTop = byX(g('lowerLipTop'));
    return _Face(
      oval,
      g('leftEye'),
      g('rightEye'),
      [...byX(g('leftEyebrowTop')), ...byX(g('leftEyebrowBottom')).reversed],
      [...byX(g('rightEyebrowTop')), ...byX(g('rightEyebrowBottom')).reversed],
      [...upTop, ...loBot.reversed],
      [...upBot, ...loTop.reversed],
      g('noseBridge'),
      g('noseBottom'),
    );
  }

  (double, double, double, double) get box {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final (x, y) in oval) {
      l = math.min(l, x);
      r = math.max(r, x);
      t = math.min(t, y);
      b = math.max(b, y);
    }
    return (l, t, r, b);
  }

  static _P center(List<_P> p) {
    var x = 0.0, y = 0.0;
    for (final q in p) {
      x += q.$1;
      y += q.$2;
    }
    return p.isEmpty ? (0, 0) : (x / p.length, y / p.length);
  }

  static double width(List<_P> p) {
    if (p.isEmpty) return 0;
    var l = double.infinity, r = -double.infinity;
    for (final q in p) {
      l = math.min(l, q.$1);
      r = math.max(r, q.$1);
    }
    return r - l;
  }
}

/// Fills [poly] into [mask] (value 255) using even-odd scanlines.
void _fillPoly(Uint8List mask, int w, int h, List<_P> poly, int value) {
  if (poly.length < 3) return;
  var minY = h.toDouble(), maxY = 0.0;
  for (final p in poly) {
    minY = math.min(minY, p.$2);
    maxY = math.max(maxY, p.$2);
  }
  final y0 = math.max(0, minY.floor()), y1 = math.min(h - 1, maxY.ceil());
  final xs = <double>[];
  for (var y = y0; y <= y1; y++) {
    final fy = y + 0.5;
    xs.clear();
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      if ((a.$2 <= fy && b.$2 > fy) || (b.$2 <= fy && a.$2 > fy)) {
        xs.add(a.$1 + (fy - a.$2) / (b.$2 - a.$2) * (b.$1 - a.$1));
      }
    }
    xs.sort();
    for (var i = 0; i + 1 < xs.length; i += 2) {
      final xa = math.max(0, xs[i].round()), xb = math.min(w - 1, xs[i + 1].round());
      for (var x = xa; x <= xb; x++) {
        mask[y * w + x] = value;
      }
    }
  }
}

/// Box blur of a byte mask (3 passes ≈ gaussian), radius in pixels.
Float32List _blurMask(Uint8List m, int w, int h, int r) {
  var a = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    a[i] = m[i] / 255.0;
  }
  if (r < 1) return a;
  for (var pass = 0; pass < 3; pass++) {
    final b = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      var acc = 0.0;
      for (var x = -r; x <= r; x++) {
        acc += a[y * w + x.clamp(0, w - 1)];
      }
      for (var x = 0; x < w; x++) {
        b[y * w + x] = acc / (2 * r + 1);
        acc += a[y * w + (x + r + 1).clamp(0, w - 1)] - a[y * w + (x - r).clamp(0, w - 1)];
      }
    }
    final c = Float32List(w * h);
    for (var x = 0; x < w; x++) {
      var acc = 0.0;
      for (var y = -r; y <= r; y++) {
        acc += b[y.clamp(0, h - 1) * w + x];
      }
      for (var y = 0; y < h; y++) {
        c[y * w + x] = acc / (2 * r + 1);
        acc += b[(y + r + 1).clamp(0, h - 1) * w + x] - b[(y - r).clamp(0, h - 1) * w + x];
      }
    }
    a = c;
  }
  return a;
}

/// Color retouch inside the face box: smoothing, glow, tone, eyes, teeth.
void _retouch(img.Image im, _Face f, BeautySettings s) {
  final (fl, ft, fr, fb) = f.box;
  final faceW = fr - fl;
  if (faceW < 20) return;
  // Work box: face + a margin (forehead above the contour, too).
  final pad = faceW * 0.12;
  final x0 = math.max(0, (fl - pad).floor()), y0 = math.max(0, (ft - faceW * 0.25).floor());
  final x1 = math.min(im.width - 1, (fr + pad).ceil()), y1 = math.min(im.height - 1, (fb + pad).ceil());
  final w = x1 - x0 + 1, h = y1 - y0 + 1;
  if (w < 8 || h < 8) return;
  List<_P> local(List<_P> p) => [for (final (x, y) in p) (x - x0, y - y0)];

  // Skin = face oval (+ forehead) minus eyes, brows, mouth.
  final skin = Uint8List(w * h);
  final oval = local(f.oval);
  _fillPoly(skin, w, h, oval, 255);
  for (final part in [f.leftEye, f.rightEye, f.leftBrow, f.rightBrow, f.lipsOuter]) {
    final c = _Face.center(part);
    // Slightly enlarged so edges of eyes/lips stay crisp.
    final grown = [for (final (x, y) in part) (c.$1 + (x - c.$1) * 1.25, c.$2 + (y - c.$2) * 1.35)];
    _fillPoly(skin, w, h, local(grown), 0);
  }
  final feather = math.max(2, (faceW * 0.03).round());
  final skinA = _blurMask(skin, w, h, feather);

  // Read the box into float RGB.
  final rgb = Float32List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x0 + x, y0 + y);
      final i = (y * w + x) * 3;
      rgb[i] = p.r.toDouble();
      rgb[i + 1] = p.g.toDouble();
      rgb[i + 2] = p.b.toDouble();
    }
  }
  // Skin-color gate: skips hair, glasses, beard shadows, background.
  double skinLike(int i) {
    final r = rgb[i], g = rgb[i + 1], b = rgb[i + 2];
    final cb = 128 - 0.1687 * r - 0.3313 * g + 0.5 * b;
    final cr = 128 + 0.5 * r - 0.4187 * g - 0.0813 * b;
    final dcb = (cb - 110).abs() / 28, dcr = (cr - 150).abs() / 26;
    return (1.5 - math.sqrt(dcb * dcb + dcr * dcr)).clamp(0.0, 1.0);
  }

  final out = Float32List.fromList(rgb);

  if (s.smooth > 0.01 || s.even > 0.01) {
    // Edge-aware smoothing: a bilateral filter on a small copy, then only
    // the low-frequency change is added back (pores/texture are kept).
    final sc = math.min(1.0, 360 / math.max(w, h));
    final sw = math.max(4, (w * sc).round()), sh = math.max(4, (h * sc).round());
    final small = Float32List(sw * sh * 3);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final sx = math.min(w - 1, (x / sc).floor()), sy = math.min(h - 1, (y / sc).floor());
        final si = (sy * w + sx) * 3, di = (y * sw + x) * 3;
        small[di] = rgb[si];
        small[di + 1] = rgb[si + 1];
        small[di + 2] = rgb[si + 2];
      }
    }
    final rad = math.max(2, (faceW * sc * 0.035).round());
    final sigmaR = 14.0 + 26.0 * s.smooth;
    final bil = _bilateral(small, sw, sh, rad, rad * 0.6, sigmaR);
    // A plain blur for "even tone" (evens out color blotches).
    final even = s.even > 0.01 ? _boxBlurRgb(small, sw, sh, math.max(2, rad * 2)) : null;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final a = skinA[i];
        if (a <= 0.01) continue;
        final gate = skinLike(i * 3);
        if (gate <= 0.01) continue;
        // Bilinear sample of the small results.
        final fx = math.min(sw - 1.001, x * sc), fy = math.min(sh - 1.001, y * sc);
        final ix = fx.floor(), iy = fy.floor(), tx = fx - ix, ty = fy - iy;
        double sample(Float32List src, int c) {
          final a00 = src[(iy * sw + ix) * 3 + c], a10 = src[(iy * sw + ix + 1) * 3 + c];
          final a01 = src[((iy + 1) * sw + ix) * 3 + c], a11 = src[((iy + 1) * sw + ix + 1) * 3 + c];
          return (a00 * (1 - tx) + a10 * tx) * (1 - ty) + (a01 * (1 - tx) + a11 * tx) * ty;
        }

        final wS = a * gate * (0.35 + 0.6 * s.smooth) * (s.smooth > 0.01 ? 1 : 0);
        final wE = a * gate * s.even * 0.5;
        for (var c = 0; c < 3; c++) {
          final o = rgb[i * 3 + c];
          var v = o;
          v += (sample(bil, c) - o) * wS;
          if (even != null) {
            // Keep luminance detail, pull the color toward the local average.
            final lumO = 0.299 * rgb[i * 3] + 0.587 * rgb[i * 3 + 1] + 0.114 * rgb[i * 3 + 2];
            final e = sample(even, c);
            final lumE = 0.299 * sample(even, 0) + 0.587 * sample(even, 1) + 0.114 * sample(even, 2);
            v += ((e - lumE + lumO) - v) * wE;
          }
          out[i * 3 + c] = v;
        }
      }
    }
  }

  if (s.brighten > 0.01) {
    for (var i = 0; i < w * h; i++) {
      final a = skinA[i] * skinLike(i * 3) * s.brighten;
      if (a <= 0.01) continue;
      for (var c = 0; c < 3; c++) {
        final v = out[i * 3 + c];
        // Screen-like lift, a touch warmer (glow).
        final lift = (255 - v) * (c == 2 ? 0.2 : 0.26);
        out[i * 3 + c] = v + lift * a;
      }
    }
  }

  // Eyes: brighten whites & iris a little, add contrast.
  if (s.eyes > 0.01) {
    for (final eye in [f.leftEye, f.rightEye]) {
      final m = Uint8List(w * h);
      _fillPoly(m, w, h, local(eye), 255);
      final a = _blurMask(m, w, h, math.max(1, (_Face.width(eye) * 0.08).round()));
      for (var i = 0; i < w * h; i++) {
        final k = a[i] * s.eyes;
        if (k <= 0.01) continue;
        final l = 0.299 * out[i * 3] + 0.587 * out[i * 3 + 1] + 0.114 * out[i * 3 + 2];
        for (var c = 0; c < 3; c++) {
          final v = out[i * 3 + c];
          final contrasted = (v - 128) * 1.18 + 128 + (l > 120 ? 22 : 8);
          out[i * 3 + c] = v + (contrasted - v) * k;
        }
      }
    }
  }

  // Teeth: inside the open mouth, desaturate yellow and lift brightness.
  if (s.teeth > 0.01 && f.mouthInner.length >= 6) {
    final m = Uint8List(w * h);
    _fillPoly(m, w, h, local(f.mouthInner), 255);
    final a = _blurMask(m, w, h, 1);
    for (var i = 0; i < w * h; i++) {
      final k = a[i] * s.teeth;
      if (k <= 0.01) continue;
      final r = out[i * 3], g = out[i * 3 + 1], b = out[i * 3 + 2];
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      // Only bright, low-saturation pixels are teeth (not tongue/lips).
      final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
      final sat = mx <= 0 ? 0.0 : (mx - mn) / mx;
      if (l < 70 || sat > 0.55) continue;
      final kk = k * (1 - sat);
      final target = math.min(255.0, l * 1.12 + 14);
      out[i * 3] = r + (target - r) * kk;
      out[i * 3 + 1] = g + (target - g) * kk;
      out[i * 3 + 2] = b + (target + 4 - b) * kk;
    }
  }

  // Lips: richer color.
  if (s.lips > 0.01 && f.lipsOuter.length >= 6) {
    final m = Uint8List(w * h);
    _fillPoly(m, w, h, local(f.lipsOuter), 255);
    if (f.mouthInner.length >= 6) _fillPoly(m, w, h, local(f.mouthInner), 0);
    final a = _blurMask(m, w, h, math.max(1, (faceW * 0.006).round()));
    for (var i = 0; i < w * h; i++) {
      final k = a[i] * s.lips * 0.6;
      if (k <= 0.01) continue;
      final r = out[i * 3], g = out[i * 3 + 1], b = out[i * 3 + 2];
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      // Increase saturation toward rose.
      out[i * 3] = r + ((l + (r - l) * 1.5 + 10) - r) * k;
      out[i * 3 + 1] = g + ((l + (g - l) * 1.5 - 6) - g) * k;
      out[i * 3 + 2] = b + ((l + (b - l) * 1.5 + 2) - b) * k;
    }
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      im.setPixelRgb(x0 + x, y0 + y, out[i].round().clamp(0, 255), out[i + 1].round().clamp(0, 255),
          out[i + 2].round().clamp(0, 255));
    }
  }
}

Float32List _bilateral(Float32List src, int w, int h, int r, double sigmaS, double sigmaR) {
  final out = Float32List(w * h * 3);
  final ws = List<double>.generate((2 * r + 1) * (2 * r + 1), (i) {
    final dx = i % (2 * r + 1) - r, dy = i ~/ (2 * r + 1) - r;
    return math.exp(-(dx * dx + dy * dy) / (2 * sigmaS * sigmaS));
  });
  final inv = 1 / (2 * sigmaR * sigmaR);
  // Range-weight lookup (squared color distance, bucketed).
  final lut = List<double>.generate(1024, (i) => math.exp(-(i * 16.0) * inv));
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      final r0 = src[i], g0 = src[i + 1], b0 = src[i + 2];
      var sr = 0.0, sg = 0.0, sb = 0.0, sw = 0.0;
      for (var dy = -r; dy <= r; dy++) {
        final yy = (y + dy).clamp(0, h - 1);
        for (var dx = -r; dx <= r; dx++) {
          final xx = (x + dx).clamp(0, w - 1);
          final j = (yy * w + xx) * 3;
          final dr = src[j] - r0, dg = src[j + 1] - g0, db = src[j + 2] - b0;
          final d2 = (dr * dr + dg * dg + db * db) / 16;
          final wr = d2 >= 1023 ? 0.0 : lut[d2.toInt()];
          final wt = ws[(dy + r) * (2 * r + 1) + dx + r] * wr;
          sr += src[j] * wt;
          sg += src[j + 1] * wt;
          sb += src[j + 2] * wt;
          sw += wt;
        }
      }
      out[i] = sr / sw;
      out[i + 1] = sg / sw;
      out[i + 2] = sb / sw;
    }
  }
  return out;
}

Float32List _boxBlurRgb(Float32List src, int w, int h, int r) {
  var a = Float32List.fromList(src);
  for (var pass = 0; pass < 2; pass++) {
    final b = Float32List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var c = 0; c < 3; c++) {
        var acc = 0.0;
        for (var x = -r; x <= r; x++) {
          acc += a[(y * w + x.clamp(0, w - 1)) * 3 + c];
        }
        for (var x = 0; x < w; x++) {
          b[(y * w + x) * 3 + c] = acc / (2 * r + 1);
          acc += a[(y * w + (x + r + 1).clamp(0, w - 1)) * 3 + c] - a[(y * w + (x - r).clamp(0, w - 1)) * 3 + c];
        }
      }
    }
    final d = Float32List(w * h * 3);
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var acc = 0.0;
        for (var y = -r; y <= r; y++) {
          acc += b[(y.clamp(0, h - 1) * w + x) * 3 + c];
        }
        for (var y = 0; y < h; y++) {
          d[(y * w + x) * 3 + c] = acc / (2 * r + 1);
          acc += b[((y + r + 1).clamp(0, h - 1) * w + x) * 3 + c] - b[((y - r).clamp(0, h - 1) * w + x) * 3 + c];
        }
      }
    }
    a = d;
  }
  return a;
}

/// Liquify: enlarge eyes, pull cheeks/jaw inward, narrow the nose.
/// Inverse mapping with bilinear sampling, limited to the face box.
img.Image _warp(img.Image im, _Face f, BeautySettings s) {
  final (fl, ft, fr, fb) = f.box;
  final faceW = fr - fl;
  final cx = (fl + fr) / 2;
  final pad = faceW * 0.25;
  final x0 = math.max(0, (fl - pad).floor()), y0 = math.max(0, (ft - pad).floor());
  final x1 = math.min(im.width - 1, (fr + pad).ceil()), y1 = math.min(im.height - 1, (fb + pad).ceil());

  // Eye magnifiers.
  final eyes = <(double, double, double, double)>[]; // cx, cy, radius, strength
  if (s.bigEyes > 0.01) {
    for (final e in [f.leftEye, f.rightEye]) {
      if (e.length < 4) continue;
      final c = _Face.center(e);
      eyes.add((c.$1, c.$2, _Face.width(e) * 1.25, s.bigEyes * 0.22));
    }
  }
  // Jaw/cheek pushes: lower half of the face contour moves toward the
  // vertical center line.
  final pushes = <(double, double, double, double, double)>[]; // px, py, dx, dy, radius
  if (s.slim > 0.01) {
    final midY = (ft + fb) / 2;
    for (final (x, y) in f.oval) {
      if (y < midY - (fb - ft) * 0.05) continue;
      final dx = (cx - x) * 0.09 * s.slim;
      final dy = (fb - y) < (fb - ft) * 0.08 ? -(fb - ft) * 0.012 * s.slim : 0.0;
      pushes.add((x, y, dx, dy, faceW * 0.22));
    }
  }
  if (s.nose > 0.01 && f.noseBottom.length >= 3) {
    final nb = List.of(f.noseBottom)..sort((a, b) => a.$1.compareTo(b.$1));
    final nc = _Face.center(nb);
    final nw = nb.last.$1 - nb.first.$1;
    for (final p in [nb.first, nb.last]) {
      pushes.add((p.$1, p.$2, (nc.$1 - p.$1) * 0.28 * s.nose, 0, nw * 0.7));
    }
  }
  if (eyes.isEmpty && pushes.isEmpty) return im;

  final src = img.Image.from(im);
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      var sx = x.toDouble(), sy = y.toDouble();
      for (final (px, py, dx, dy, r) in pushes) {
        final ddx = x - px, ddy = y - py;
        final d2 = ddx * ddx + ddy * ddy;
        final r2 = r * r;
        if (d2 >= r2) continue;
        final fall = (1 - d2 / r2);
        final w = fall * fall;
        // Inverse map: sample from where the content came from.
        sx -= dx * w;
        sy -= dy * w;
      }
      for (final (ex, ey, r, k) in eyes) {
        final ddx = sx - ex, ddy = sy - ey;
        final d = math.sqrt(ddx * ddx + ddy * ddy);
        if (d >= r) continue;
        final t = d / r;
        final scale = 1 - k * (1 - t * t);
        sx = ex + ddx * scale;
        sy = ey + ddy * scale;
      }
      if (sx == x && sy == y) continue;
      final c = src.getPixelInterpolate(sx.clamp(0, im.width - 1.0), sy.clamp(0, im.height - 1.0),
          interpolation: img.Interpolation.linear);
      im.setPixelRgb(x, y, c.r, c.g, c.b);
    }
  }
  return im;
}
