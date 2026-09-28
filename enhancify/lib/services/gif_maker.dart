import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Animation styles for the GIF maker.
enum GifStyle {
  pulse('Zoom pulse'),
  kenBurns('Pan & zoom'),
  shake('Shake'),
  glitch('Glitch'),
  sparkle('Sparkle'),
  slideshow('Slideshow');

  const GifStyle(this.label);
  final String label;
}

/// Makes looping GIFs from one or more photos. Runs in a background isolate
/// so the app never freezes.
class GifMaker {
  GifMaker._();

  /// [frameMs] is the delay per frame (40–200). [size] is the long side.
  static Future<Uint8List> make(
    List<Uint8List> photos, {
    GifStyle style = GifStyle.pulse,
    int frameMs = 80,
    int size = 480,
  }) {
    if (photos.isEmpty) throw ArgumentError('Pick at least one photo.');
    return Isolate.run(() => _make(photos, style, frameMs, size));
  }
}

Uint8List _make(List<Uint8List> photos, GifStyle style, int frameMs, int size) {
  final decoded = <img.Image>[];
  for (final p in photos) {
    final d = img.decodeImage(p);
    if (d == null) continue;
    var im = img.bakeOrientation(d);
    // Palette PNG/GIF or RGBA input: work in plain RGB so the pixel edits
    // (glitch, mix) and GIF quantisation behave the same for every photo.
    if (im.numFrames > 1) im = img.Image.from(im, noAnimation: true);
    if (im.hasPalette || im.numChannels != 3 || im.format != img.Format.uint8) {
      im = im.convert(format: img.Format.uint8, numChannels: 3, noAnimation: true);
    }
    decoded.add(_fit(im, size));
  }
  if (decoded.isEmpty) throw StateError('Could not read this photo.');
  // Everything shares the first photo's canvas size.
  final w = decoded.first.width, h = decoded.first.height;
  final frames = <img.Image>[];

  switch (style) {
    case GifStyle.pulse:
      const n = 16;
      for (var i = 0; i < n; i++) {
        final t = (1 - math.cos(2 * math.pi * i / n)) / 2; // 0→1→0
        frames.add(_zoomCrop(decoded.first, 1 + 0.14 * t, 0.5, 0.5));
      }
    case GifStyle.kenBurns:
      const n = 24;
      for (var i = 0; i < n; i++) {
        // Glide there and back so the loop is seamless.
        final t = (1 - math.cos(2 * math.pi * i / n)) / 2;
        frames.add(_zoomCrop(decoded.first, 1.12 + 0.1 * t, 0.35 + 0.3 * t, 0.45 + 0.1 * t));
      }
    case GifStyle.shake:
      const offs = [(0.0, 0.0), (-0.02, 0.01), (0.02, -0.01), (-0.015, -0.015), (0.015, 0.015), (0.0, 0.0)];
      for (final (dx, dy) in offs) {
        frames.add(_zoomCrop(decoded.first, 1.08, 0.5 + dx * 3, 0.5 + dy * 3));
      }
    case GifStyle.glitch:
      final r = math.Random(7);
      for (var i = 0; i < 10; i++) {
        final base = img.Image.from(decoded.first);
        if (i % 3 != 0) _glitch(base, r);
        frames.add(base);
      }
    case GifStyle.sparkle:
      final r = math.Random(5);
      final stars = List.generate(
          28, (_) => (r.nextDouble() * w, r.nextDouble() * h, 3 + r.nextDouble() * (w / 60), r.nextDouble()));
      const n = 12;
      for (var i = 0; i < n; i++) {
        final f = img.Image.from(decoded.first);
        for (final (x, y, s, phase) in stars) {
          final a = (math.sin(2 * math.pi * (i / n + phase)) + 1) / 2;
          if (a < 0.25) continue;
          _star(f, x, y, s * a, (255 * a).round());
        }
        frames.add(f);
      }
    case GifStyle.slideshow:
      final slides = [for (final d in decoded) _cover(d, w, h)];
      if (slides.length == 1) {
        // One photo: fade in from blush pink.
        final blank = img.Image(width: w, height: h);
        img.fill(blank, color: img.ColorRgb8(255, 227, 239));
        slides.insert(0, blank);
      }
      const hold = 8, fade = 5;
      for (var s = 0; s < slides.length; s++) {
        final a = slides[s], b = slides[(s + 1) % slides.length];
        for (var i = 0; i < hold; i++) {
          frames.add(a);
        }
        for (var i = 1; i <= fade; i++) {
          frames.add(_mix(a, b, i / (fade + 1)));
        }
      }
  }

  // Collapse runs of identical frames into one longer frame (smaller file).
  img.Image? anim;
  img.Image? last;
  for (final f in frames) {
    if (identical(f, last) && anim != null) {
      final prev = anim.frames.last;
      prev.frameDuration += frameMs;
      continue;
    }
    final frame = f.numChannels == 3 ? img.Image.from(f) : f.convert(numChannels: 3);
    frame.frameDuration = frameMs;
    if (anim == null) {
      anim = frame;
    } else {
      anim.addFrame(frame);
    }
    last = f;
  }
  return img.encodeGif(anim!, repeat: 0, samplingFactor: 10);
}

img.Image _fit(img.Image im, int maxSide) {
  if (im.width <= maxSide && im.height <= maxSide) return im;
  return im.width >= im.height
      ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
}

/// Crop a 1/z window centered at (cx, cy) and scale back to full size.
img.Image _zoomCrop(img.Image base, double z, double cx, double cy) {
  final cw = (base.width / z).round(), ch = (base.height / z).round();
  final x = (cx * base.width - cw / 2).round().clamp(0, base.width - cw);
  final y = (cy * base.height - ch / 2).round().clamp(0, base.height - ch);
  return img.copyResize(img.copyCrop(base, x: x, y: y, width: cw, height: ch),
      width: base.width, height: base.height, interpolation: img.Interpolation.linear);
}

/// Center-crop [im] to fill w×h.
img.Image _cover(img.Image im, int w, int h) {
  final s = math.max(w / im.width, h / im.height);
  final r = img.copyResize(im,
      width: (im.width * s).ceil(), height: (im.height * s).ceil(), interpolation: img.Interpolation.average);
  return img.copyCrop(r, x: (r.width - w) ~/ 2, y: (r.height - h) ~/ 2, width: w, height: h);
}

img.Image _mix(img.Image a, img.Image b, double t) {
  final out = img.Image(width: a.width, height: a.height);
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final p = a.getPixel(x, y), q = b.getPixel(x, y);
      out.setPixelRgb(x, y, (p.r + (q.r - p.r) * t).round(), (p.g + (q.g - p.g) * t).round(),
          (p.b + (q.b - p.b) * t).round());
    }
  }
  return out;
}

void _glitch(img.Image im, math.Random r) {
  final src = img.Image.from(im);
  final shift = (im.width * (0.01 + r.nextDouble() * 0.02)).round();
  // RGB split.
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final rp = src.getPixel((x + shift).clamp(0, im.width - 1), y);
      final bp = src.getPixel((x - shift).clamp(0, im.width - 1), y);
      final p = src.getPixel(x, y);
      im.setPixelRgb(x, y, rp.r, p.g, bp.b);
    }
  }
  // A few displaced slices.
  for (var k = 0; k < 4; k++) {
    final y0 = r.nextInt(im.height);
    final hh = math.max(2, (im.height * r.nextDouble() * 0.05).round());
    final dx = ((r.nextDouble() - 0.5) * im.width * 0.12).round();
    for (var y = y0; y < math.min(im.height, y0 + hh); y++) {
      for (var x = 0; x < im.width; x++) {
        final p = src.getPixel((x - dx).clamp(0, im.width - 1), y);
        im.setPixelRgb(x, y, p.r, p.g, p.b);
      }
    }
  }
}

/// A soft four-point twinkle.
void _star(img.Image im, double cx, double cy, double s, int alpha) {
  final c = img.ColorRgba8(255, 255, 255, alpha);
  final pink = img.ColorRgba8(255, 180, 215, alpha);
  final x = cx.round(), y = cy.round(), len = math.max(2, s.round());
  img.drawLine(im, x1: x - len, y1: y, x2: x + len, y2: y, color: pink, thickness: 1);
  img.drawLine(im, x1: x, y1: y - len, x2: x, y2: y + len, color: pink, thickness: 1);
  img.fillCircle(im, x: x, y: y, radius: math.max(1, len ~/ 3), color: c);
}
