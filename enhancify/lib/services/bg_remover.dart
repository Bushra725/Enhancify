import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

/// A photo split into subject + transparent background.
class BgCutout {
  BgCutout({required this.photo, required this.width, required this.height, required this.maskPng, required this.method});

  /// Upright photo (JPEG, ≤ 2048 px).
  final Uint8List photo;
  final int width;
  final int height;

  /// Gray PNG, same size: white = keep, black = remove, soft edges.
  final Uint8List maskPng;

  /// 'person', 'object' or 'color' (which detector found the subject).
  final String method;
}

/// One refine stroke. Points are 0–1 fractions of the photo.
class RefineStroke {
  RefineStroke({required this.keep, required this.width, List<Offset>? points}) : points = points ?? [];
  final bool keep;

  /// Radius as a fraction of the photo width.
  final double width;
  final List<Offset> points;
}

/// Background remover in the style of Canva: people via ML Kit selfie
/// segmentation, objects via GrabCut (Android) or a color model (iOS).
class BgRemover {
  BgRemover._();

  static const _channel = MethodChannel('enhancify/inpaint');

  static Future<BgCutout> cutout(Uint8List bytes) async {
    final prepared = await Isolate.run(() => _upright(bytes));
    if (prepared == null) throw StateError('Could not read this photo.');
    final (jpg, w, h) = prepared;

    // 1) People: ML Kit selfie segmentation (on-device, both platforms).
    List<double>? conf;
    var mw = 0, mh = 0;
    final tmp = File('${Directory.systemTemp.path}/bg_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tmp.writeAsBytes(jpg, flush: true);
    final segmenter = SelfieSegmenter(mode: SegmenterMode.single, enableRawSizeMask: false);
    try {
      final m = await segmenter.processImage(InputImage.fromFilePath(tmp.path));
      if (m != null && m.confidences.isNotEmpty) {
        conf = List<double>.from(m.confidences);
        mw = m.width;
        mh = m.height;
      }
    } catch (_) {
      conf = null;
    } finally {
      await segmenter.close();
      try {
        await tmp.delete();
      } catch (_) {}
    }
    final c = conf;
    if (c != null) {
      final people = c.where((v) => v > 0.6).length;
      if (people > c.length * 0.04) {
        final mask = await Isolate.run(() => _personMask(jpg, c, mw, mh, w, h));
        return BgCutout(photo: jpg, width: w, height: h, maskPng: mask, method: 'person');
      }
    }

    // 2) Objects on Android: OpenCV GrabCut.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final png = await _channel.invokeMethod<Uint8List>('grabCut', {'photo': jpg});
        if (png != null && png.isNotEmpty) {
          return BgCutout(photo: jpg, width: w, height: h, maskPng: png, method: 'object');
        }
      } on MissingPluginException {
        // fall through
      } on PlatformException {
        // fall through
      }
    }

    // 3) Everywhere else: color model (border = background).
    final mask = await Isolate.run(() => _colorMask(jpg));
    return BgCutout(photo: jpg, width: w, height: h, maskPng: mask, method: 'color');
  }

  /// Transparent PNG of the subject with the user's refine strokes applied.
  static Future<Uint8List> cutoutPng(BgCutout c, List<RefineStroke> strokes) =>
      Isolate.run(() => _compose(c.photo, c.maskPng, strokes, null, null));

  /// Subject over a solid color ([argb]) or over [background] image bytes
  /// (cover-fit), as JPEG. If [blur] is set the original photo is blurred.
  static Future<Uint8List> composite(BgCutout c, List<RefineStroke> strokes,
      {int? argb, Uint8List? background, bool blur = false}) {
    final bgBytes = blur ? c.photo : background;
    return Isolate.run(() => _compose(c.photo, c.maskPng, strokes, argb, bgBytes, blurBg: blur));
  }
}

(Uint8List, int, int)? _upright(Uint8List bytes) {
  final d = img.decodeImage(bytes);
  if (d == null) return null;
  var im = img.bakeOrientation(d);
  const maxSide = 2048;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
  }
  if (im.numChannels != 3) im = im.convert(numChannels: 3);
  return (img.encodeJpg(im, quality: 95), im.width, im.height);
}

Uint8List _personMask(Uint8List jpg, List<double> conf, int mw, int mh, int w, int h) {
  var m = img.Image(width: mw, height: mh, numChannels: 1);
  for (var y = 0; y < mh; y++) {
    for (var x = 0; x < mw; x++) {
      // Sharpen the confidence ramp a bit so hair edges stay soft but the
      // background doesn't glow.
      final v = ((conf[y * mw + x] - 0.35) / 0.35).clamp(0.0, 1.0);
      m.setPixelR(x, y, (v * 255).round());
    }
  }
  if (mw != w || mh != h) {
    m = img.copyResize(m, width: w, height: h, interpolation: img.Interpolation.linear);
  }
  m = img.gaussianBlur(m, radius: math.max(1, w ~/ 600));
  return img.encodePng(m);
}

/// Border pixels teach a background color model, the center teaches a
/// subject model; each pixel goes to the closer one, then the mask is
/// cleaned and only the main blob touching the center is kept.
Uint8List _colorMask(Uint8List jpg) {
  final full = img.decodeImage(jpg)!;
  const work = 400;
  final s = math.min(1.0, work / math.max(full.width, full.height));
  final im = s < 1
      ? img.copyResize(full,
          width: (full.width * s).round(), height: (full.height * s).round(), interpolation: img.Interpolation.average)
      : full;
  final w = im.width, h = im.height;
  final lab = Float32List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      final i = (y * w + x) * 3;
      lab[i] = p.r.toDouble();
      lab[i + 1] = p.g.toDouble();
      lab[i + 2] = p.b.toDouble();
    }
  }
  final border = <int>[];
  final bw = math.max(2, (math.min(w, h) * 0.04).round());
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (x < bw || y < bw || x >= w - bw || y >= h - bw) border.add(y * w + x);
    }
  }
  final center = <int>[];
  for (var y = (h * 0.3).round(); y < (h * 0.7).round(); y++) {
    for (var x = (w * 0.3).round(); x < (w * 0.7).round(); x++) {
      center.add(y * w + x);
    }
  }
  final bgC = _kmeans(lab, border, 6);
  final fgC = _kmeans(lab, center, 6);
  double nearest(List<List<double>> cs, int i) {
    var best = double.infinity;
    for (final c in cs) {
      final a = lab[i * 3] - c[0], b = lab[i * 3 + 1] - c[1], d = lab[i * 3 + 2] - c[2];
      final v = a * a + b * b + d * d;
      if (v < best) best = v;
    }
    return best;
  }

  var fg = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    final db = nearest(bgC, i), df = nearest(fgC, i);
    // Background must be clearly closer to count as background.
    fg[i] = db < df * 0.8 && db < 55 * 55 ? 0 : 1;
  }
  // Background = only what's connected to the border (flood fill), so
  // subject pixels that share a color with the background survive.
  final bgMask = Uint8List(w * h);
  final queue = <int>[];
  for (final i in border) {
    if (fg[i] == 0) {
      bgMask[i] = 1;
      queue.add(i);
    }
  }
  var head = 0;
  while (head < queue.length) {
    final i = queue[head++];
    final x = i % w, y = i ~/ w;
    for (final j in [if (x > 0) i - 1, if (x < w - 1) i + 1, if (y > 0) i - w, if (y < h - 1) i + w]) {
      if (bgMask[j] == 0 && fg[j] == 0) {
        bgMask[j] = 1;
        queue.add(j);
      }
    }
  }
  fg = Uint8List.fromList([for (var i = 0; i < w * h; i++) bgMask[i] == 1 ? 0 : 1]);
  // Majority smoothing (removes speckles on both sides).
  for (var it = 0; it < 2; it++) {
    final next = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var n = 0, t = 0;
        for (var dy = -2; dy <= 2; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -2; dx <= 2; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            n += fg[yy * w + xx];
            t++;
          }
        }
        next[y * w + x] = n * 2 > t ? 1 : 0;
      }
    }
    fg = next;
  }
  var m = img.Image(width: w, height: h, numChannels: 1);
  for (var i = 0; i < w * h; i++) {
    m.setPixelR(i % w, i ~/ w, fg[i] * 255);
  }
  m = img.copyResize(m, width: full.width, height: full.height, interpolation: img.Interpolation.linear);
  m = img.gaussianBlur(m, radius: math.max(1, full.width ~/ 500));
  return img.encodePng(m);
}

List<List<double>> _kmeans(Float32List px, List<int> idx, int k) {
  if (idx.isEmpty) return [
    [0, 0, 0]
  ];
  final rnd = math.Random(3);
  final step = math.max(1, idx.length ~/ 4000);
  final sample = [for (var i = 0; i < idx.length; i += step) idx[i]];
  final cs = [
    for (var i = 0; i < k; i++)
      () {
        final j = sample[rnd.nextInt(sample.length)];
        return [px[j * 3].toDouble(), px[j * 3 + 1].toDouble(), px[j * 3 + 2].toDouble()];
      }()
  ];
  for (var it = 0; it < 8; it++) {
    final sum = List.generate(k, (_) => [0.0, 0.0, 0.0, 0.0]);
    for (final j in sample) {
      var best = 0;
      var bd = double.infinity;
      for (var c = 0; c < k; c++) {
        final a = px[j * 3] - cs[c][0], b = px[j * 3 + 1] - cs[c][1], d = px[j * 3 + 2] - cs[c][2];
        final v = a * a + b * b + d * d;
        if (v < bd) {
          bd = v;
          best = c;
        }
      }
      sum[best][0] += px[j * 3];
      sum[best][1] += px[j * 3 + 1];
      sum[best][2] += px[j * 3 + 2];
      sum[best][3] += 1;
    }
    for (var c = 0; c < k; c++) {
      if (sum[c][3] > 0) cs[c] = [sum[c][0] / sum[c][3], sum[c][1] / sum[c][3], sum[c][2] / sum[c][3]];
    }
  }
  return cs;
}

/// Applies refine strokes to the mask, then renders the subject over the
/// chosen background (or transparent PNG when there's none).
Uint8List _compose(Uint8List jpg, Uint8List maskPng, List<RefineStroke> strokes, int? argb, Uint8List? bgBytes,
    {bool blurBg = false}) {
  final photo = img.decodeImage(jpg)!;
  var mask = img.decodeImage(maskPng)!;
  if (mask.width != photo.width || mask.height != photo.height) {
    mask = img.copyResize(mask, width: photo.width, height: photo.height);
  }
  if (mask.numChannels != 1) mask = mask.convert(numChannels: 1);
  final w = photo.width, h = photo.height;
  for (final s in strokes) {
    if (s.points.isEmpty) continue;
    final color = s.keep ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0);
    final r = math.max(2, (w * s.width).round());
    (int, int) px(Offset o) => ((o.dx * (w - 1)).round(), (o.dy * (h - 1)).round());
    var (px0, py0) = px(s.points.first);
    img.fillCircle(mask, x: px0, y: py0, radius: r, color: color, antialias: true);
    for (final p in s.points.skip(1)) {
      final (x1, y1) = px(p);
      img.drawLine(mask, x1: px0, y1: py0, x2: x1, y2: y1, color: color, thickness: r * 2);
      img.fillCircle(mask, x: x1, y: y1, radius: r, color: color, antialias: true);
      px0 = x1;
      py0 = y1;
    }
  }

  if (argb == null && bgBytes == null) {
    final out = img.Image(width: w, height: h, numChannels: 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = photo.getPixel(x, y);
        out.setPixelRgba(x, y, p.r, p.g, p.b, mask.getPixel(x, y).r);
      }
    }
    return img.encodePng(out);
  }

  img.Image bg;
  if (bgBytes != null) {
    final d = img.decodeImage(bgBytes);
    if (d == null) {
      bg = img.Image(width: w, height: h);
      img.fill(bg, color: img.ColorRgb8(255, 255, 255));
    } else {
      final u = img.bakeOrientation(d);
      final sc = math.max(w / u.width, h / u.height);
      final r = img.copyResize(u,
          width: (u.width * sc).ceil(), height: (u.height * sc).ceil(), interpolation: img.Interpolation.average);
      bg = img.copyCrop(r, x: (r.width - w) ~/ 2, y: (r.height - h) ~/ 2, width: w, height: h);
      if (blurBg) {
        // Fast strong blur: shrink, blur, grow.
        final small = img.copyResize(bg, width: math.max(8, w ~/ 8), interpolation: img.Interpolation.average);
        bg = img.copyResize(img.gaussianBlur(small, radius: 4), width: w, height: h,
            interpolation: img.Interpolation.linear);
      }
    }
  } else {
    bg = img.Image(width: w, height: h);
    img.fill(bg, color: img.ColorRgb8((argb! >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF));
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = mask.getPixel(x, y).r / 255.0;
      if (a <= 0) continue;
      final p = photo.getPixel(x, y);
      final b = bg.getPixel(x, y);
      bg.setPixelRgb(x, y, (p.r * a + b.r * (1 - a)).round(), (p.g * a + b.g * (1 - a)).round(),
          (p.b * a + b.b * (1 - a)).round());
    }
  }
  return img.encodeJpg(bg, quality: 95);
}
