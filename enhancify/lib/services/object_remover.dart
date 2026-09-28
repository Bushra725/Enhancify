import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../config/app_config.dart';
import 'cloudflare_service.dart';
import 'inpaint_engine.dart';

export 'inpaint_engine.dart' show FillMode;

/// One user mark on the photo. Points are 0–1 fractions of the photo.
enum MaskOpKind { brush, erase, lasso }

class MaskOp {
  MaskOp(this.kind, this.width, [List<Offset>? points]) : points = points ?? [];
  final MaskOpKind kind;

  /// Brush radius as a fraction of the photo width.
  final double width;
  final List<Offset> points;
}

/// Paints the mask from the finger strokes, then fills that region.
/// Used by the Restore tool (brush strokes only).
Future<Uint8List> removePaintedObject(
  Uint8List photo,
  List<List<Offset>> strokes, {
  required double brushFraction,
  FillMode mode = FillMode.smooth,
}) {
  return removeMarked(
    photo,
    [for (final s in strokes) MaskOp(MaskOpKind.brush, brushFraction, s)],
    mode: mode,
  );
}

/// Removes everything covered by [ops] (brush, lasso, minus erase).
///
/// [FillMode.texture] rebuilds the area from real patches of the photo
/// (content-aware fill); [FillMode.smooth] blends the surrounding colors
/// seamlessly. Both run on-device in pure Dart, identical on Android and iOS.
Future<Uint8List> removeMarked(
  Uint8List photo,
  List<MaskOp> ops, {
  FillMode mode = FillMode.texture,
}) async {
  final prepared = await Isolate.run(() => _prepare(photo, ops));
  if (prepared == null) throw StateError('Could not read this photo.');
  final (jpg, maskPng, _, _) = prepared;
  return Isolate.run(() => _fillJob(jpg, maskPng, mode));
}

Uint8List _fillJob(Uint8List jpg, Uint8List maskPng, FillMode mode) {
  final photo = img.decodeImage(jpg)!;
  final mask = img.decodeImage(maskPng)!;
  final out = fillMasked(photo, mask, mode);
  return img.encodeJpg(out, quality: 95);
}

/// Cloud AI removal (free Cloudflare provider). The AI fills a magenta-marked
/// area; only that area is pasted back, so the rest keeps full resolution.
Future<Uint8List> removeMarkedWithAi(Uint8List photo, List<MaskOp> ops) async {
  if (!AppConfig.useCloudflare) {
    throw StateError('AI remove needs the free AI server (CF_WORKER_URL).');
  }
  final prepared = await Isolate.run(() => _prepare(photo, ops));
  if (prepared == null) throw StateError('Could not read this photo.');
  final (jpg, maskPng, _, _) = prepared;
  final marked = await Isolate.run(() => _paintMagenta(jpg, maskPng));
  final input = await CloudflareService.shrink(marked);
  final ai = await CloudflareService().edit(
    [input],
    'Remove everything painted in solid magenta and realistically fill that '
    'area with the surrounding background, matching texture, lighting and '
    'perspective. Do not change anything else in the photo. No magenta.',
  );
  return Isolate.run(() => _pasteBack(jpg, maskPng, ai));
}

const _channel = MethodChannel('enhancify/inpaint');

/// Classical OpenCV inpainting on Android. [telea] uses Telea; otherwise
/// Navier-Stokes. White pixels in [maskPng] are removed.
Future<Uint8List> removeObject(
  Uint8List photo,
  Uint8List maskPng, {
  bool telea = true,
  double radius = 4,
}) async {
  final bytes = await _channel.invokeMethod<Uint8List>('removeObject', {
    'photo': photo,
    'mask': maskPng,
    'telea': telea,
    'radius': radius,
  });
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Inpaint did not return an image.');
  }
  return bytes;
}

/// Builds a black mask with white marks (brush and lasso), erase subtracts.
Uint8List buildRemovalMask(int width, int height, List<MaskOp> ops) {
  final mask = img.Image(width: width, height: height, numChannels: 1);
  img.fill(mask, color: img.ColorRgb8(0, 0, 0));
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  for (final op in ops) {
    if (op.points.isEmpty) continue;
    final pts = [
      for (final p in op.points)
        (
          (p.dx * (width - 1)).round().clamp(0, width - 1),
          (p.dy * (height - 1)).round().clamp(0, height - 1),
        )
    ];
    if (op.kind == MaskOpKind.lasso) {
      if (pts.length >= 3) {
        img.fillPolygon(mask,
            vertices: [for (final (x, y) in pts) img.Point(x, y)], color: white);
      }
      continue;
    }
    final color = op.kind == MaskOpKind.erase ? black : white;
    final radius = (width * op.width).round().clamp(3, math.max(3, width ~/ 4)).toInt();
    var prev = pts.first;
    img.fillCircle(mask, x: prev.$1, y: prev.$2, radius: radius, color: color);
    for (final p in pts.skip(1)) {
      img.drawLine(mask,
          x1: prev.$1, y1: prev.$2, x2: p.$1, y2: p.$2, color: color, thickness: radius * 2);
      img.fillCircle(mask, x: p.$1, y: p.$2, radius: radius, color: color);
      prev = p;
    }
  }
  return img.encodePng(mask);
}

/// Upright photo (max 2400 px) as JPEG + matching mask PNG.
(Uint8List, Uint8List, int, int)? _prepare(Uint8List photo, List<MaskOp> ops) {
  final decoded = img.decodeImage(photo);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  const maxSide = 2400;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide)
        : img.copyResize(im, height: maxSide);
  }
  final mask = buildRemovalMask(im.width, im.height, ops);
  return (img.encodeJpg(im, quality: 95), mask, im.width, im.height);
}

Uint8List _paintMagenta(Uint8List jpg, Uint8List maskPng) {
  final im = img.decodeImage(jpg)!;
  final m = img.decodeImage(maskPng)!;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (m.getPixel(x, y).r > 127) im.setPixelRgb(x, y, 255, 0, 255);
    }
  }
  return img.encodeJpg(im, quality: 95);
}

/// Pastes the AI result into the masked area with a soft edge.
Uint8List _pasteBack(Uint8List jpg, Uint8List maskPng, Uint8List aiBytes) {
  final base = img.decodeImage(jpg)!;
  var ai = img.decodeImage(aiBytes)!;
  ai = img.copyResize(ai,
      width: base.width, height: base.height, interpolation: img.Interpolation.cubic);
  var m = img.decodeImage(maskPng)!;
  final feather = math.max(3, (base.width * 0.006).round());
  // Grow then blur so the paste covers the edge and fades in.
  final grown = img.Image(width: m.width, height: m.height, numChannels: 1);
  img.fill(grown, color: img.ColorRgb8(0, 0, 0));
  bool on(int x, int y) =>
      x >= 0 && y >= 0 && x < m.width && y < m.height && m.getPixel(x, y).r > 127;
  final white = img.ColorRgb8(255, 255, 255);
  // Copy the mask, then stamp circles only along its edge (stamping every
  // interior pixel too gives the same result but takes many seconds).
  for (var y = 0; y < m.height; y++) {
    for (var x = 0; x < m.width; x++) {
      if (on(x, y)) grown.setPixelR(x, y, 255);
    }
  }
  for (var y = 0; y < m.height; y += 2) {
    for (var x = 0; x < m.width; x += 2) {
      if (!on(x, y)) continue;
      if (on(x - 2, y) && on(x + 2, y) && on(x, y - 2) && on(x, y + 2)) continue;
      img.fillCircle(grown, x: x, y: y, radius: feather, color: white);
    }
  }
  m = img.gaussianBlur(grown, radius: feather);
  for (var y = 0; y < base.height; y++) {
    for (var x = 0; x < base.width; x++) {
      final a = m.getPixel(x, y).r / 255.0;
      if (a <= 0.01) continue;
      final b = base.getPixel(x, y);
      final c = ai.getPixel(x, y);
      base.setPixelRgb(
        x,
        y,
        (b.r * (1 - a) + c.r * a).round(),
        (b.g * (1 - a) + c.g * a).round(),
        (b.b * (1 - a) + c.b * a).round(),
      );
    }
  }
  return img.encodeJpg(base, quality: 94);
}
