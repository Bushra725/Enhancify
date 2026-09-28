import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// How a marked area is filled.
enum FillMode {
  /// Photoshop-style content-aware fill: rebuilds the area from real patches
  /// of the photo, so grass, walls, skin, fabric keep their texture.
  texture,

  /// Soft, seamless blend of the surrounding colors (best for scratches,
  /// dust, spots and plain backgrounds).
  smooth,
}

/// Fills the white area of [mask] in [photo]. Pure Dart, so it runs the same
/// on Android and iOS. Call it inside an isolate (it's CPU heavy).
///
/// Only a box around the mask is processed, so big photos stay fast; the
/// rest of the photo is untouched and keeps full resolution.
img.Image fillMasked(img.Image photo, img.Image mask, FillMode mode, {int seed = 7}) {
  final w = photo.width, h = photo.height;
  // Mask bounding box.
  var x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mask.getPixel(x, y).r > 127) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return photo;

  // Context around the hole: texture fill needs real material to copy from.
  final bw = x1 - x0 + 1, bh = y1 - y0 + 1;
  final margin = mode == FillMode.texture
      ? math.max(32, (math.max(bw, bh) * 1.2).round())
      : math.max(12, (math.max(bw, bh) * 0.35).round());
  final rx0 = math.max(0, x0 - margin), ry0 = math.max(0, y0 - margin);
  final rx1 = math.min(w - 1, x1 + margin), ry1 = math.min(h - 1, y1 + margin);
  final rw = rx1 - rx0 + 1, rh = ry1 - ry0 + 1;

  // Work size: texture synthesis is O(pixels × patch), so cap it.
  final cap = mode == FillMode.texture ? 640 : 1400;
  final scale = math.min(1.0, cap / math.max(rw, rh));
  final ww = math.max(8, (rw * scale).round()), wh = math.max(8, (rh * scale).round());

  var roi = img.copyCrop(photo, x: rx0, y: ry0, width: rw, height: rh);
  if (roi.numChannels != 3 || roi.format != img.Format.uint8) {
    roi = roi.convert(format: img.Format.uint8, numChannels: 3);
  }
  final small = scale < 1
      ? img.copyResize(roi, width: ww, height: wh, interpolation: img.Interpolation.average)
      : roi;
  final rgb = Float32List(ww * wh * 3);
  final hole = Uint8List(ww * wh);
  for (var y = 0; y < wh; y++) {
    for (var x = 0; x < ww; x++) {
      final i = y * ww + x;
      final p = small.getPixel(x, y);
      rgb[i * 3] = p.r.toDouble();
      rgb[i * 3 + 1] = p.g.toDouble();
      rgb[i * 3 + 2] = p.b.toDouble();
      // A work pixel is a hole if any photo pixel under it is marked.
      final mx0 = rx0 + (x / scale).floor(), my0 = ry0 + (y / scale).floor();
      final mx1 = math.min(w - 1, rx0 + ((x + 1) / scale).ceil() - 1);
      final my1 = math.min(h - 1, ry0 + ((y + 1) / scale).ceil() - 1);
      var hit = false;
      for (var my = my0; my <= my1 && !hit; my++) {
        for (var mx = mx0; mx <= mx1; mx++) {
          if (mask.getPixel(mx, my).r > 127) {
            hit = true;
            break;
          }
        }
      }
      if (hit) hole[i] = 1;
    }
  }

  final filled = mode == FillMode.texture
      ? _PatchFill(ww, wh, rgb, hole, seed).run()
      : _smoothFill(ww, wh, rgb, hole);

  // Back to an image at ROI size.
  var outSmall = img.Image(width: ww, height: wh);
  for (var y = 0; y < wh; y++) {
    for (var x = 0; x < ww; x++) {
      final i = (y * ww + x) * 3;
      outSmall.setPixelRgb(x, y, filled[i].round().clamp(0, 255), filled[i + 1].round().clamp(0, 255),
          filled[i + 2].round().clamp(0, 255));
    }
  }
  final outRoi = scale < 1
      ? img.copyResize(outSmall, width: rw, height: rh, interpolation: img.Interpolation.cubic)
      : outSmall;

  // Grain: match the photo's own noise so the fill doesn't look plastic.
  final noise = _noiseLevel(roi, mask, rx0, ry0);
  final grain = mode == FillMode.smooth ? noise : (scale < 0.8 ? noise * 0.7 : 0.0);

  // Feathered paste (1–2 px soft edge) inside the marked area.
  final feather = math.max(1, (math.min(w, h) / 900).round());
  final alpha = _softMask(mask, rx0, ry0, rw, rh, feather);
  final out = img.Image.from(photo);
  final rnd = math.Random(seed);
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      final a = alpha[y * rw + x];
      if (a <= 0.003) continue;
      final src = out.getPixel(rx0 + x, ry0 + y);
      final f = outRoi.getPixel(x, y);
      final n = grain > 0 ? (rnd.nextDouble() + rnd.nextDouble() - 1) * grain * 1.7 : 0.0;
      out.setPixelRgb(
        rx0 + x,
        ry0 + y,
        (src.r * (1 - a) + (f.r + n) * a).round().clamp(0, 255),
        (src.g * (1 - a) + (f.g + n) * a).round().clamp(0, 255),
        (src.b * (1 - a) + (f.b + n) * a).round().clamp(0, 255),
      );
    }
  }
  return out;
}

/// Mask → 0..1 alpha: 1 inside the mark, a short linear fade just outside.
Float32List _softMask(img.Image mask, int ox, int oy, int rw, int rh, int feather) {
  final inside = Uint8List(rw * rh);
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      if (mask.getPixel(ox + x, oy + y).r > 127) inside[y * rw + x] = 1;
    }
  }
  final a = Float32List(rw * rh);
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      final i = y * rw + x;
      if (inside[i] == 1) {
        a[i] = 1;
        continue;
      }
      var best = feather + 1.0;
      for (var dy = -feather; dy <= feather; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= rh) continue;
        for (var dx = -feather; dx <= feather; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= rw) continue;
          if (inside[yy * rw + xx] == 1) {
            final d = math.sqrt((dx * dx + dy * dy).toDouble());
            if (d < best) best = d;
          }
        }
      }
      if (best <= feather) a[i] = (1 - best / (feather + 1)) * 0.9;
    }
  }
  return a;
}

/// Rough noise level (std-dev) of the photo just around the mark.
double _noiseLevel(img.Image roi, img.Image mask, int ox, int oy) {
  var sum = 0.0, n = 0;
  final step = math.max(1, math.max(roi.width, roi.height) ~/ 200);
  for (var y = 1; y < roi.height - 1; y += step) {
    for (var x = 1; x < roi.width - 1; x += step) {
      if (mask.getPixel(ox + x, oy + y).r > 127) continue;
      final c = roi.getPixel(x, y).luminance;
      final m = (roi.getPixel(x - 1, y).luminance +
              roi.getPixel(x + 1, y).luminance +
              roi.getPixel(x, y - 1).luminance +
              roi.getPixel(x, y + 1).luminance) /
          4;
      final d = (c - m).toDouble();
      sum += d * d;
      n++;
    }
  }
  if (n == 0) return 0;
  // Laplacian residual overestimates flat-area noise a bit; keep it subtle.
  return math.min(10.0, math.sqrt(sum / n) * 0.6);
}

// ---------------------------------------------------------------- smooth

/// Seamless membrane fill: a push-pull pyramid gives a first guess, then
/// Gauss-Seidel relaxation (Laplace equation) at every level makes the fill
/// blend smoothly into every edge of the hole, with no streaks.
Float32List _smoothFill(int w, int h, Float32List rgb, Uint8List hole) {
  final levels = <_Lvl>[];
  var cur = _Lvl(w, h, Float32List.fromList(rgb), Uint8List.fromList(hole));
  levels.add(cur);
  while (cur.w > 8 && cur.h > 8 && cur.holeCount > 0) {
    final next = cur.down();
    levels.add(next);
    cur = next;
    if (next.knownCount == next.w * next.h) break;
  }
  // Coarsest: fill any remaining unknowns with the mean of known pixels.
  final top = levels.last;
  _fillWithMean(top);
  _relax(top, 60);
  for (var li = levels.length - 2; li >= 0; li--) {
    final fine = levels[li], coarse = levels[li + 1];
    fine.pullFrom(coarse);
    _relax(fine, li == 0 ? 40 : 30);
  }
  return levels.first.rgb;
}

void _fillWithMean(_Lvl l) {
  double r = 0, g = 0, b = 0;
  var n = 0;
  for (var i = 0; i < l.w * l.h; i++) {
    if (l.hole[i] == 0) {
      r += l.rgb[i * 3];
      g += l.rgb[i * 3 + 1];
      b += l.rgb[i * 3 + 2];
      n++;
    }
  }
  if (n == 0) {
    r = g = b = 128;
    n = 1;
  }
  for (var i = 0; i < l.w * l.h; i++) {
    if (l.hole[i] == 1) {
      l.rgb[i * 3] = r / n;
      l.rgb[i * 3 + 1] = g / n;
      l.rgb[i * 3 + 2] = b / n;
    }
  }
}

/// Hole pixels ← average of their 4 neighbours, repeated.
void _relax(_Lvl l, int iterations) {
  final w = l.w, h = l.h;
  final idx = <int>[];
  for (var i = 0; i < w * h; i++) {
    if (l.hole[i] == 1) idx.add(i);
  }
  if (idx.isEmpty) return;
  final rgb = l.rgb;
  for (var it = 0; it < iterations; it++) {
    for (final i in idx) {
      final x = i % w, y = i ~/ w;
      var n = 0;
      double r = 0, g = 0, b = 0;
      if (x > 0) {
        final j = (i - 1) * 3;
        r += rgb[j];
        g += rgb[j + 1];
        b += rgb[j + 2];
        n++;
      }
      if (x < w - 1) {
        final j = (i + 1) * 3;
        r += rgb[j];
        g += rgb[j + 1];
        b += rgb[j + 2];
        n++;
      }
      if (y > 0) {
        final j = (i - w) * 3;
        r += rgb[j];
        g += rgb[j + 1];
        b += rgb[j + 2];
        n++;
      }
      if (y < h - 1) {
        final j = (i + w) * 3;
        r += rgb[j];
        g += rgb[j + 1];
        b += rgb[j + 2];
        n++;
      }
      final k = i * 3;
      rgb[k] = r / n;
      rgb[k + 1] = g / n;
      rgb[k + 2] = b / n;
    }
  }
}

class _Lvl {
  _Lvl(this.w, this.h, this.rgb, this.hole);
  final int w, h;
  final Float32List rgb;
  final Uint8List hole;

  int get holeCount => hole.where((v) => v == 1).length;
  int get knownCount => w * h - holeCount;

  /// Half size; a coarse pixel is known if any child is known (average of
  /// the known children).
  _Lvl down() {
    final nw = (w + 1) ~/ 2, nh = (h + 1) ~/ 2;
    final nrgb = Float32List(nw * nh * 3);
    final nh2 = Uint8List(nw * nh);
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        double r = 0, g = 0, b = 0;
        var n = 0;
        for (var dy = 0; dy < 2; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            final sx = x * 2 + dx, sy = y * 2 + dy;
            if (sx >= w || sy >= h) continue;
            final j = sy * w + sx;
            if (hole[j] == 1) continue;
            r += rgb[j * 3];
            g += rgb[j * 3 + 1];
            b += rgb[j * 3 + 2];
            n++;
          }
        }
        final k = y * nw + x;
        if (n == 0) {
          nh2[k] = 1;
        } else {
          nrgb[k * 3] = r / n;
          nrgb[k * 3 + 1] = g / n;
          nrgb[k * 3 + 2] = b / n;
        }
      }
    }
    return _Lvl(nw, nh, nrgb, nh2);
  }

  /// Hole pixels ← bilinear sample of the coarse level.
  void pullFrom(_Lvl c) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (hole[i] == 0) continue;
        final fx = math.max(0.0, math.min(c.w - 1.0, x / 2 - 0.25));
        final fy = math.max(0.0, math.min(c.h - 1.0, y / 2 - 0.25));
        final ix = fx.floor(), iy = fy.floor();
        final ix1 = math.min(c.w - 1, ix + 1), iy1 = math.min(c.h - 1, iy + 1);
        final tx = fx - ix, ty = fy - iy;
        for (var ch = 0; ch < 3; ch++) {
          final v00 = c.rgb[(iy * c.w + ix) * 3 + ch];
          final v10 = c.rgb[(iy * c.w + ix1) * 3 + ch];
          final v01 = c.rgb[(iy1 * c.w + ix) * 3 + ch];
          final v11 = c.rgb[(iy1 * c.w + ix1) * 3 + ch];
          rgb[i * 3 + ch] = (v00 * (1 - tx) + v10 * tx) * (1 - ty) + (v01 * (1 - tx) + v11 * tx) * ty;
        }
      }
    }
  }
}

// --------------------------------------------------------------- texture

/// Multi-scale PatchMatch + voting (Wexler et al. / Barnes et al.), the same
/// idea behind Photoshop's content-aware fill.
class _PatchFill {
  _PatchFill(this.w, this.h, this.rgb, this.hole, int seed) : _rnd = math.Random(seed);

  final int w, h;
  final Float32List rgb;
  final Uint8List hole;
  final math.Random _rnd;

  static const r = 3; // 7×7 patches

  Float32List run() {
    // Pyramid of (image, hole). Stop when the hole is only a few patches
    // wide or when there'd be too little material left to copy from.
    final pyr = <_Lvl>[_Lvl(w, h, Float32List.fromList(rgb), Uint8List.fromList(hole))];
    while (true) {
      final l = pyr.last;
      if (math.min(l.w, l.h) < 48) break;
      final next = _downHole(l);
      if (_validCount(next) < 64) break;
      pyr.add(next);
      if (math.max(next.w, next.h) <= 64) break;
    }

    Int32List? nnf; // per pixel: source center index, or -1
    for (var li = pyr.length - 1; li >= 0; li--) {
      final l = pyr[li];
      final valid = _validSources(l);
      final validList = <int>[];
      for (var i = 0; i < l.w * l.h; i++) {
        if (valid[i] == 1) validList.add(i);
      }
      if (validList.isEmpty) {
        // Nothing to copy from (hole covers everything): smooth fallback.
        return _smoothFill(w, h, rgb, hole);
      }
      final targets = _targets(l);
      final hd = _holeDistance(l);
      final dist = Float32List(l.w * l.h);
      if (nnf == null) {
        // Coarsest: smooth first guess, random correspondences.
        final guess = _smoothFill(l.w, l.h, l.rgb, l.hole);
        l.rgb.setAll(0, guess);
        nnf = Int32List(l.w * l.h)..fillRange(0, l.w * l.h, -1);
        for (final p in targets) {
          nnf[p] = validList[_rnd.nextInt(validList.length)];
        }
      } else {
        nnf = _upsample(nnf, pyr[li + 1], l, valid, validList, targets);
        _vote(l, nnf, targets, hd);
      }
      for (final p in targets) {
        dist[p] = _d(l, p, nnf[p], double.infinity);
      }
      final coarsest = li == pyr.length - 1;
      final em = coarsest ? 6 : (li == 0 ? 3 : 4);
      final passes = coarsest ? 4 : (li == 0 ? 2 : 3);
      for (var e = 0; e < em; e++) {
        for (var pass = 0; pass < passes; pass++) {
          _patchMatch(l, nnf, dist, targets, valid, reverse: pass.isOdd);
        }
        _vote(l, nnf, targets, hd);
        // Distances changed with the image; refresh them.
        for (final p in targets) {
          dist[p] = _d(l, p, nnf[p], double.infinity);
        }
      }
    }
    return _seamFix(w, h, rgb, hole, pyr.first.rgb);
  }

  /// Distance (in pixels) from each hole pixel to the nearest known pixel.
  Float32List _holeDistance(_Lvl l) {
    final w = l.w, h = l.h;
    final d = Float32List(w * h);
    for (var i = 0; i < w * h; i++) {
      d[i] = l.hole[i] == 1 ? 1e9 : 0;
    }
    const diag = 1.414;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        var v = d[i];
        if (x > 0) v = math.min(v, d[i - 1] + 1);
        if (y > 0) {
          v = math.min(v, d[i - w] + 1);
          if (x > 0) v = math.min(v, d[i - w - 1] + diag);
          if (x < w - 1) v = math.min(v, d[i - w + 1] + diag);
        }
        d[i] = v;
      }
    }
    for (var y = h - 1; y >= 0; y--) {
      for (var x = w - 1; x >= 0; x--) {
        final i = y * w + x;
        var v = d[i];
        if (x < w - 1) v = math.min(v, d[i + 1] + 1);
        if (y < h - 1) {
          v = math.min(v, d[i + w] + 1);
          if (x < w - 1) v = math.min(v, d[i + w + 1] + diag);
          if (x > 0) v = math.min(v, d[i + w - 1] + diag);
        }
        d[i] = v;
      }
    }
    return d;
  }

  /// Gradient-domain touch-up: adds a smooth correction so the synthesized
  /// area meets the untouched photo with no visible seam (Poisson blend).
  static Float32List _seamFix(int w, int h, Float32List orig, Uint8List hole, Float32List fill) {
    final diff = Float32List(w * h * 3);
    final unknown = Uint8List(w * h)..fillRange(0, w * h, 1);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (hole[i] == 1) continue;
        double r = 0, g = 0, b = 0;
        var n = 0;
        void add(int xx, int yy) {
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) return;
          final j = yy * w + xx;
          if (hole[j] == 0) return;
          r += fill[j * 3];
          g += fill[j * 3 + 1];
          b += fill[j * 3 + 2];
          n++;
        }

        add(x - 1, y);
        add(x + 1, y);
        add(x, y - 1);
        add(x, y + 1);
        if (n > 0) {
          unknown[i] = 0;
          diff[i * 3] = orig[i * 3] - r / n;
          diff[i * 3 + 1] = orig[i * 3 + 1] - g / n;
          diff[i * 3 + 2] = orig[i * 3 + 2] - b / n;
        }
      }
    }
    final c = _smoothFill(w, h, diff, unknown);
    final out = Float32List.fromList(fill);
    for (var i = 0; i < w * h; i++) {
      if (hole[i] == 0) continue;
      out[i * 3] += c[i * 3];
      out[i * 3 + 1] += c[i * 3 + 1];
      out[i * 3 + 2] += c[i * 3 + 2];
    }
    return out;
  }

  _Lvl _downHole(_Lvl l) {
    // Like _Lvl.down, but a coarse pixel is a hole if ANY child is a hole,
    // so no hole color leaks into the coarse image.
    final nw = (l.w + 1) ~/ 2, nh = (l.h + 1) ~/ 2;
    final out = l.down();
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        var any = false;
        for (var dy = 0; dy < 2 && !any; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            final sx = x * 2 + dx, sy = y * 2 + dy;
            if (sx < l.w && sy < l.h && l.hole[sy * l.w + sx] == 1) {
              any = true;
              break;
            }
          }
        }
        if (any) out.hole[y * nw + x] = 1;
      }
    }
    return out;
  }

  int _validCount(_Lvl l) {
    final v = _validSources(l);
    var n = 0;
    for (final b in v) {
      n += b;
    }
    return n;
  }

  /// A source center is valid when its whole patch is inside the image and
  /// touches no hole pixel (integral image of the hole).
  Uint8List _validSources(_Lvl l) {
    final w = l.w, h = l.h;
    final integ = Int32List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0;
      for (var x = 0; x < w; x++) {
        row += l.hole[y * w + x];
        integ[(y + 1) * (w + 1) + x + 1] = integ[y * (w + 1) + x + 1] + row;
      }
    }
    final out = Uint8List(w * h);
    for (var y = r; y < h - r; y++) {
      for (var x = r; x < w - r; x++) {
        final a = integ[(y - r) * (w + 1) + (x - r)];
        final b = integ[(y - r) * (w + 1) + (x + r + 1)];
        final c = integ[(y + r + 1) * (w + 1) + (x - r)];
        final d = integ[(y + r + 1) * (w + 1) + (x + r + 1)];
        if (d - b - c + a == 0) out[y * w + x] = 1;
      }
    }
    return out;
  }

  /// Every pixel whose patch overlaps the hole.
  List<int> _targets(_Lvl l) {
    final w = l.w, h = l.h;
    final mark = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (l.hole[y * w + x] == 0) continue;
        for (var dy = -r; dy <= r; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -r; dx <= r; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            mark[yy * w + xx] = 1;
          }
        }
      }
    }
    return [for (var i = 0; i < w * h; i++) if (mark[i] == 1) i];
  }

  /// Patch distance (SSD) between target p and source s, early exit at [cap].
  double _d(_Lvl l, int p, int s, double cap) {
    final w = l.w, h = l.h, rgb = l.rgb;
    final px = p % w, py = p ~/ w, sx = s % w, sy = s ~/ w;
    var sum = 0.0;
    var n = 0;
    for (var dy = -r; dy <= r; dy++) {
      final ty = py + dy;
      if (ty < 0 || ty >= h) continue;
      final trow = ty * w, srow = (sy + dy) * w;
      for (var dx = -r; dx <= r; dx++) {
        final tx = px + dx;
        if (tx < 0 || tx >= w) continue;
        final ti = (trow + tx) * 3, si = (srow + sx + dx) * 3;
        final a = rgb[ti] - rgb[si], b = rgb[ti + 1] - rgb[si + 1], c = rgb[ti + 2] - rgb[si + 2];
        sum += a * a + b * b + c * c;
        n++;
      }
      if (sum > cap) return double.infinity; // normalised value can only be larger
    }
    // Normalise so edge patches (fewer pixels) compare fairly.
    return n == 0 ? double.infinity : sum * 49 / n;
  }

  void _patchMatch(_Lvl l, Int32List nnf, Float32List dist, List<int> targets, Uint8List valid,
      {required bool reverse}) {
    final w = l.w, h = l.h;
    final count = targets.length;
    final maxR = math.max(w, h);
    for (var k = 0; k < count; k++) {
      final p = targets[reverse ? count - 1 - k : k];
      final px = p % w, py = p ~/ w;
      var best = nnf[p];
      var bestD = dist[p];
      // Propagation from the already-visited neighbours.
      final step = reverse ? 1 : -1;
      for (var axis = 0; axis < 2; axis++) {
        final nx = px + (axis == 0 ? step : 0), ny = py + (axis == 1 ? step : 0);
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final q = nnf[ny * w + nx];
        if (q < 0) continue;
        final cx = q % w - (axis == 0 ? step : 0), cy = q ~/ w - (axis == 1 ? step : 0);
        if (cx < 0 || cx >= w || cy < 0 || cy >= h) continue;
        final cand = cy * w + cx;
        if (cand == best || valid[cand] == 0) continue;
        final d = _d(l, p, cand, bestD);
        if (d < bestD) {
          bestD = d;
          best = cand;
        }
      }
      // Random search in shrinking windows around the current best.
      var rad = maxR.toDouble();
      final bx = best % w, by = best ~/ w;
      while (rad >= 1) {
        final ri = rad.round();
        final cx = (bx + _rnd.nextInt(2 * ri + 1) - ri).clamp(0, w - 1);
        final cy = (by + _rnd.nextInt(2 * ri + 1) - ri).clamp(0, h - 1);
        final cand = cy * w + cx;
        if (valid[cand] == 1 && cand != best) {
          final d = _d(l, p, cand, bestD);
          if (d < bestD) {
            bestD = d;
            best = cand;
          }
        }
        rad /= 2;
      }
      nnf[p] = best;
      dist[p] = bestD;
    }
  }

  /// Each hole pixel = weighted average of what the overlapping source
  /// patches say it should be. Better-matching patches count more.
  void _vote(_Lvl l, Int32List nnf, List<int> targets, Float32List hd) {
    final w = l.w, h = l.h, rgb = l.rgb;
    final acc = Float32List(w * h * 3);
    final wsum = Float32List(w * h);
    for (final p in targets) {
      final s = nnf[p];
      if (s < 0) continue;
      final px = p % w, py = p ~/ w, sx = s % w, sy = s ~/ w;
      // Patches near the known border count more (Wexler et al.), which
      // keeps the fill coherent with its surroundings.
      // Exponent capped so deep-inside weights never underflow Float32
      // (a zero weight sum would leave the old object color in place).
      final wt = math.pow(1.3, -math.min(hd[p], 200.0)).toDouble();
      for (var dy = -r; dy <= r; dy++) {
        final ty = py + dy;
        if (ty < 0 || ty >= h) continue;
        for (var dx = -r; dx <= r; dx++) {
          final tx = px + dx;
          if (tx < 0 || tx >= w) continue;
          final t = ty * w + tx;
          if (l.hole[t] == 0) continue;
          final si = ((sy + dy) * w + sx + dx) * 3;
          acc[t * 3] += rgb[si] * wt;
          acc[t * 3 + 1] += rgb[si + 1] * wt;
          acc[t * 3 + 2] += rgb[si + 2] * wt;
          wsum[t] += wt;
        }
      }
    }
    for (var i = 0; i < w * h; i++) {
      if (l.hole[i] == 0 || wsum[i] <= 0) continue;
      rgb[i * 3] = acc[i * 3] / wsum[i];
      rgb[i * 3 + 1] = acc[i * 3 + 1] / wsum[i];
      rgb[i * 3 + 2] = acc[i * 3 + 2] / wsum[i];
    }
  }

  /// Coarse correspondences → fine: double the offsets, keep the sub-pixel.
  Int32List _upsample(Int32List coarseNnf, _Lvl coarse, _Lvl fine, Uint8List valid, List<int> validList,
      List<int> targets) {
    final out = Int32List(fine.w * fine.h)..fillRange(0, fine.w * fine.h, -1);
    for (final p in targets) {
      final x = p % fine.w, y = p ~/ fine.w;
      final cx = math.min(coarse.w - 1, x >> 1), cy = math.min(coarse.h - 1, y >> 1);
      final cs = coarseNnf[cy * coarse.w + cx];
      var cand = -1;
      if (cs >= 0) {
        final sx = (cs % coarse.w) * 2 + (x & 1), sy = (cs ~/ coarse.w) * 2 + (y & 1);
        if (sx < fine.w && sy < fine.h) {
          final c = sy * fine.w + sx;
          if (valid[c] == 1) cand = c;
        }
      }
      out[p] = cand >= 0 ? cand : validList[_rnd.nextInt(validList.length)];
    }
    return out;
  }
}
