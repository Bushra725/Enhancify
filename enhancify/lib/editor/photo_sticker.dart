import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/local_enhance.dart';
import '../services/media_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'layers.dart';

/// Lets the user turn one of their photos into a sticker: an AI cut-out of
/// the person (Snapchat-style, with a white outline) or a shaped sticker.
/// Returns transparent PNG bytes, or null if cancelled.
Future<Uint8List?> createPhotoSticker(BuildContext context) async {
  final file = await MediaService.pickImage();
  if (file == null || !context.mounted) return null;
  final choice = await showModalBottomSheet<(PhotoShape, bool)>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ShapeSheet(file: file),
  );
  if (choice == null || !context.mounted) return null;

  final done = ValueNotifier<String>('Making your sticker...');
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 16),
                ValueListenableBuilder<String>(
                  valueListenable: done,
                  builder: (_, s, __) => Text(s),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Uint8List? result;
  String? error;
  try {
    result = await buildPhotoSticker(file, choice.$1, outline: choice.$2);
  } catch (e) {
    error = e is StickerException ? e.message : 'Could not make a sticker from this photo.';
  }
  if (nav.mounted) nav.pop();
  Future<void>.delayed(const Duration(milliseconds: 400), done.dispose);
  if (error != null && context.mounted) showSnack(context, error);
  return result;
}

class StickerException implements Exception {
  StickerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Full pipeline, usable without UI.
Future<Uint8List> buildPhotoSticker(File file, PhotoShape shape, {bool outline = true}) async {
  final raw = await file.readAsBytes();
  // 1. Upright + downscale (off the UI thread).
  final jpg = await Isolate.run(() => _normalize(raw));
  if (jpg == null) throw StickerException('This photo format is not supported.');

  List<double>? mask;
  int maskW = 0, maskH = 0;
  if (shape == PhotoShape.cutout) {
    final tmp = File(p.join((await getTemporaryDirectory()).path,
        'sticker_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await tmp.writeAsBytes(jpg, flush: true);
    final segmenter = SelfieSegmenter(mode: SegmenterMode.single, enableRawSizeMask: false);
    try {
      final m = await segmenter.processImage(InputImage.fromFilePath(tmp.path));
      if (m != null) {
        mask = List<double>.from(m.confidences);
        maskW = m.width;
        maskH = m.height;
      }
    } catch (_) {
      mask = null;
    } finally {
      await segmenter.close();
      try {
        await tmp.delete();
      } catch (_) {}
    }
    final fg = mask == null ? 0 : mask.where((c) => c > 0.5).length;
    if (mask == null || fg < mask.length * 0.02) {
      // No person found: fall back to the on-device background remover.
      try {
        final png = await Isolate.run(() => LocalEnhance().removeBackground(jpg));
        final bytes = Uint8List.fromList(png);
        return outline
            ? await Isolate.run(() => _compose(bytes, PhotoShape.original, null, 0, 0, true, alphaFromImage: true))
            : bytes;
      } catch (_) {
        throw StickerException('No person found. Try a clear photo or pick a shape.');
      }
    }
  }
  final m = mask;
  return Isolate.run(() => _compose(jpg, shape, m, maskW, maskH, outline));
}

Uint8List? _normalize(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  const maxSide = 1024;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide)
        : img.copyResize(im, height: maxSide);
  }
  return img.encodeJpg(im, quality: 92);
}

/// Builds the RGBA sticker: applies the mask/shape, crops, adds the outline.
Uint8List _compose(Uint8List bytes, PhotoShape shape, List<double>? mask, int mw,
    int mh, bool outline,
    {bool alphaFromImage = false}) {
  var im = img.decodeImage(bytes)!;
  if (!alphaFromImage &&
      shape != PhotoShape.cutout &&
      shape != PhotoShape.original) {
    final s = math.min(im.width, im.height);
    im = img.copyCrop(im,
        x: (im.width - s) ~/ 2, y: (im.height - s) ~/ 2, width: s, height: s);
  }
  final w = im.width, h = im.height;
  final src = im.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);

  // Alpha 0..1 per pixel.
  final alpha = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      double a;
      if (alphaFromImage) {
        a = src[i * 4 + 3] / 255.0;
      } else if (shape == PhotoShape.cutout && mask != null && mw > 0 && mh > 0) {
        final mx = (x * mw / w).floor().clamp(0, mw - 1);
        final my = (y * mh / h).floor().clamp(0, mh - 1);
        final c = mask[my * mw + mx];
        a = ((c - 0.35) / 0.3).clamp(0.0, 1.0); // soften the edge
      } else {
        a = _shapeAlpha(shape, (x + 0.5) / w, (y + 0.5) / h, w);
      }
      alpha[i] = a;
    }
  }

  // Crop to content (+ room for the outline).
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (alpha[y * w + x] > 0.05) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) throw StickerException('Nothing to cut out in this photo.');
  final r = outline ? math.max(4, (math.max(w, h) * 0.022).round()) : 0;
  final pad = r + 3;
  final cw = maxX - minX + 1 + pad * 2;
  final ch = maxY - minY + 1 + pad * 2;

  // Distance (in px) from each canvas pixel to the nearest solid pixel.
  final dist = Float32List(cw * ch);
  const inf = 1e9;
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final sx = x - pad + minX, sy = y - pad + minY;
      final solid = sx >= 0 && sy >= 0 && sx < w && sy < h && alpha[sy * w + sx] > 0.5;
      dist[y * cw + x] = solid ? 0 : inf;
    }
  }
  if (outline) {
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        final i = y * cw + x;
        var d = dist[i];
        if (x > 0) d = math.min(d, dist[i - 1] + 1);
        if (y > 0) {
          d = math.min(d, dist[i - cw] + 1);
          if (x > 0) d = math.min(d, dist[i - cw - 1] + 1.414);
          if (x < cw - 1) d = math.min(d, dist[i - cw + 1] + 1.414);
        }
        dist[i] = d;
      }
    }
    for (var y = ch - 1; y >= 0; y--) {
      for (var x = cw - 1; x >= 0; x--) {
        final i = y * cw + x;
        var d = dist[i];
        if (x < cw - 1) d = math.min(d, dist[i + 1] + 1);
        if (y < ch - 1) {
          d = math.min(d, dist[i + cw] + 1);
          if (x < cw - 1) d = math.min(d, dist[i + cw + 1] + 1.414);
          if (x > 0) d = math.min(d, dist[i + cw - 1] + 1.414);
        }
        dist[i] = d;
      }
    }
  }

  final out = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final sx = x - pad + minX, sy = y - pad + minY;
      final inside = sx >= 0 && sy >= 0 && sx < w && sy < h;
      final a = inside ? alpha[sy * w + sx] : 0.0;
      double o = 0;
      if (outline) {
        final d = dist[y * cw + x];
        o = d <= r ? 1.0 : (d <= r + 1.5 ? (r + 1.5 - d) / 1.5 : 0.0);
      }
      final aa = a + o * (1 - a);
      final j = (y * cw + x) * 4;
      if (aa <= 0) continue;
      final si = inside ? (sy * w + sx) * 4 : 0;
      for (var c = 0; c < 3; c++) {
        final sv = inside ? src[si + c].toDouble() : 255.0;
        out[j + c] = ((sv * a + 255 * o * (1 - a)) / aa).round().clamp(0, 255);
      }
      out[j + 3] = (aa * 255).round().clamp(0, 255);
    }
  }
  final result = img.Image.fromBytes(
    width: cw,
    height: ch,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodePng(result);
}

/// Coverage of a shape at normalized coords (u, v) in a square image.
double _shapeAlpha(PhotoShape shape, double u, double v, int size) {
  final px = 1.5 / size; // ~1.5 px of anti-aliasing
  double edge(double signed) => (0.5 - signed / px).clamp(0.0, 1.0);
  switch (shape) {
    case PhotoShape.circle:
      final d = math.sqrt((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5));
      return edge(d - 0.48);
    case PhotoShape.rounded:
      const rr = 0.16, half = 0.47;
      final qx = (u - 0.5).abs() - (half - rr);
      final qy = (v - 0.5).abs() - (half - rr);
      final outside = math.sqrt(math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2));
      final sd = outside + math.min(math.max(qx, qy), 0) - rr;
      return edge(sd);
    case PhotoShape.heart:
      // Classic implicit heart, flipped so the point is at the bottom.
      final x = (u - 0.5) * 2.6;
      final y = -(v - 0.54) * 2.6;
      final f = math.pow(x * x + y * y - 1, 3) - x * x * y * y * y;
      return f <= 0 ? 1.0 : 0.0;
    case PhotoShape.star:
      return _inStar(u, v) ? 1.0 : 0.0;
    case PhotoShape.original:
    case PhotoShape.cutout:
      return 1.0;
  }
}

bool _inStar(double u, double v) {
  final pts = <Offset>[];
  for (var i = 0; i < 10; i++) {
    final ang = -math.pi / 2 + i * math.pi / 5;
    final rad = i.isEven ? 0.48 : 0.2;
    pts.add(Offset(0.5 + rad * math.cos(ang), 0.52 + rad * math.sin(ang)));
  }
  var inside = false;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final a = pts[i], b = pts[j];
    if ((a.dy > v) != (b.dy > v) &&
        u < (b.dx - a.dx) * (v - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

class _ShapeSheet extends StatefulWidget {
  const _ShapeSheet({required this.file});
  final File file;

  @override
  State<_ShapeSheet> createState() => _ShapeSheetState();
}

class _ShapeSheetState extends State<_ShapeSheet> {
  PhotoShape _shape = PhotoShape.cutout;
  bool _outline = true;

  static const _items = [
    (PhotoShape.cutout, Icons.person_outline, 'Cut out'),
    (PhotoShape.circle, Icons.circle_outlined, 'Circle'),
    (PhotoShape.heart, Icons.favorite_border, 'Heart'),
    (PhotoShape.star, Icons.star_border, 'Star'),
    (PhotoShape.rounded, Icons.crop_square, 'Rounded'),
    (PhotoShape.original, Icons.crop_original, 'Full photo'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Make a sticker',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Cut out keeps just the person, with a white outline like '
              'Snapchat stickers. Or pick a shape.',
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(widget.file,
                    height: 150, fit: BoxFit.cover, cacheHeight: 400),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final it in _items)
                  ChoiceChip(
                    avatar: Icon(it.$2,
                        size: 18,
                        color: _shape == it.$1 ? Colors.white : AppColors.primary),
                    label: Text(it.$3),
                    selected: _shape == it.$1,
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                        color: _shape == it.$1 ? Colors.white : palette.textPrimary),
                    onSelected: (_) => setState(() => _shape = it.$1),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('White outline'),
              value: _outline,
              onChanged: (v) => setState(() => _outline = v),
            ),
            PillButton(
              label: 'Create sticker',
              kind: ButtonStyleKind.brand,
              onPressed: () => Navigator.of(context).pop((_shape, _outline)),
            ),
          ],
        ),
      ),
    );
  }
}
