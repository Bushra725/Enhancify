import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'app_state.dart';
import 'replicate_service.dart';

/// Improves the photo the person picked. Enhance, Natural, and Ultra HD
/// each change the same picture in a different way.
class LocalEnhance {
  List<int> apply(
    List<int> bytes, {
    required String variant,
    required EnhancerPrefs prefs,
  }) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw AiException('Could not read this photo.');
    }
    var image = _fit(decoded, 1600);
    switch (variant) {
      case 'natural':
        image = img.adjustColor(
          image,
          brightness: 1.03,
          contrast: 1.04,
          saturation: 1.02,
        );
      case 'base':
        image = img.adjustColor(
          image,
          brightness: 1.05,
          contrast: 1.12,
          saturation: 1.08,
        );
        image = _sharpen(image);
      case 'ultra':
        final scale = prefs.upscale >= 4 ? 2 : 1;
        if (scale > 1) {
          image = img.copyResize(
            image,
            width: image.width * scale,
            height: image.height * scale,
            interpolation: img.Interpolation.cubic,
          );
        }
        image = img.adjustColor(
          image,
          brightness: 1.06,
          contrast: 1.16,
          saturation: 1.1,
        );
        image = _sharpen(image);
      default:
        image = _sharpen(image);
    }
    return img.encodeJpg(image, quality: 92);
  }

  /// On-device edit. No network. [look] is `none`, `enhance`, or `restore`.
  /// Crop edges are fractions of the current image, from 0 to 1.
  List<int> bake(
    List<int> bytes, {
    String look = 'none',
    double brightness = 1,
    double contrast = 1,
    double exposure = 0,
    double lightness = 0,
    double highlight = 0,
    double saturation = 1,
    double vibrance = 0,
    double tint = 0,
    double fade = 0,
    double grain = 0,
    double warmth = 0,
    String filter = 'none',
    String frame = 'none',
    String text = '',
    String sticker = '',
    bool watermark = false,
    bool meme = false,
    int quarterTurns = 0,
    double cropLeft = 0,
    double cropTop = 0,
    double cropRight = 1,
    double cropBottom = 1,
    int maxSide = 900,
  }) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) throw AiException('Could not read this photo.');
    var image = _fit(img.bakeOrientation(decoded), maxSide);
    final turns = quarterTurns % 4;
    if (turns != 0) image = img.copyRotate(image, angle: turns * 90);
    final l = cropLeft.clamp(0.0, 0.95);
    final t = cropTop.clamp(0.0, 0.95);
    final r = cropRight.clamp(l + 0.05, 1.0);
    final b = cropBottom.clamp(t + 0.05, 1.0);
    final x = (image.width * l).round();
    final y = (image.height * t).round();
    final w = (image.width * (r - l)).round().clamp(1, image.width - x);
    final h = (image.height * (b - t)).round().clamp(1, image.height - y);
    if (w < image.width || h < image.height) {
      image = img.copyCrop(image, x: x, y: y, width: w, height: h);
    }
    if (look == 'enhance') {
      image = img.adjustColor(image, brightness: 1.05, contrast: 1.12, saturation: 1.08);
      image = _sharpen(image);
    } else if (look == 'restore') {
      image = img.adjustColor(image, brightness: 1.08, contrast: 1.2, saturation: 1.05);
      image = _sharpen(image);
    }
    image = _grade(
      image,
      brightness: brightness,
      contrast: contrast,
      exposure: exposure,
      lightness: lightness,
      highlight: highlight,
      saturation: saturation,
      vibrance: vibrance,
      tint: tint,
      fade: fade,
      warmth: warmth,
    );
    image = _applyFilter(image, filter);
    image = _frame(image, frame);
    if (meme && text.trim().isNotEmpty) _memeBars(image, text.trim());
    if (grain > 0) {
      image = img.noise(image, grain.clamp(1, 40));
    }
    if (watermark) drawWatermark(image);
    if (!meme && text.trim().isNotEmpty) _drawLabel(image, text.trim(), bottom: false);
    if (sticker.isNotEmpty) _drawLabel(image, sticker, bottom: false, yFraction: 0.18);
    return img.encodeJpg(image, quality: 100);
  }

  /// Same edit as [bake], on a background isolate so the UI stays responsive.
  Future<List<int>> bakeOffUi(
    List<int> bytes, {
    String look = 'none',
    double brightness = 1,
    double contrast = 1,
    double exposure = 0,
    double lightness = 0,
    double highlight = 0,
    double saturation = 1,
    double vibrance = 0,
    double tint = 0,
    double fade = 0,
    double grain = 0,
    double warmth = 0,
    String filter = 'none',
    String frame = 'none',
    String text = '',
    String sticker = '',
    bool watermark = false,
    bool meme = false,
    int quarterTurns = 0,
    double cropLeft = 0,
    double cropTop = 0,
    double cropRight = 1,
    double cropBottom = 1,
    int maxSide = 900,
  }) {
    final job = _BakeJob(
      bytes: Uint8List.fromList(bytes),
      look: look,
      brightness: brightness,
      contrast: contrast,
      exposure: exposure,
      lightness: lightness,
      highlight: highlight,
      saturation: saturation,
      vibrance: vibrance,
      tint: tint,
      fade: fade,
      grain: grain,
      warmth: warmth,
      filter: filter,
      frame: frame,
      text: text,
      sticker: sticker,
      watermark: watermark,
      meme: meme,
      quarterTurns: quarterTurns,
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropRight: cropRight,
      cropBottom: cropBottom,
      maxSide: maxSide,
    );
    return Isolate.run(() => _runBake(job));
  }

  img.Image _grade(
    img.Image image, {
    required double brightness,
    required double contrast,
    required double exposure,
    required double lightness,
    required double highlight,
    required double saturation,
    required double vibrance,
    required double tint,
    required double fade,
    required double warmth,
  }) {
    final sat = saturation * (1 + vibrance * 0.45);
    final bright = brightness * (1 + lightness * 0.35);
    final exp = exposure + highlight * 0.55;
    final con = contrast * (1 - fade * 0.35);
    var graded = img.adjustColor(
      image,
      brightness: bright + fade * 0.08,
      contrast: con < 0.2 ? 0.2 : con,
      saturation: sat < 0 ? 0 : sat,
      exposure: exp,
      hue: tint,
    );
    if (warmth != 0) {
      graded = img.colorOffset(graded, red: warmth * 30, blue: -warmth * 30);
    }
    return graded;
  }

  img.Image _applyFilter(img.Image image, String filter) {
    switch (filter) {
      case 'vivid':
        return img.adjustColor(image, saturation: 1.45, contrast: 1.12);
      case 'warm':
        return img.colorOffset(image, red: 18, blue: -12);
      case 'cool':
        return img.colorOffset(image, red: -12, blue: 22);
      case 'mono':
      case 'bw':
        return img.grayscale(image);
      case 'sepia':
        return img.sepia(image, amount: 0.9);
      case 'vintage':
        return img.sepia(img.adjustColor(image, saturation: 0.75), amount: 0.55);
      case 'noir':
        return img.adjustColor(img.grayscale(image), contrast: 1.35);
      case 'avatar3d':
        return img.adjustColor(img.gaussianBlur(image, radius: 1), saturation: 1.4, contrast: 1.2);
      case 'pixel':
        final small = img.copyResize(image, width: 72, interpolation: img.Interpolation.average);
        return img.copyResize(small, width: image.width, height: image.height, interpolation: img.Interpolation.nearest);
      case 'clay':
        return img.adjustColor(img.gaussianBlur(image, radius: 2), saturation: 1.15, brightness: 1.06);
      case 'sketch':
      case 'pencil':
        return _pencil(image);
      case 'cartoon':
      case 'comic':
        return _cartoon(image);
      default:
        return image;
    }
  }

  img.Image _pencil(img.Image src) {
    final gray = img.grayscale(src);
    final inv = img.invert(img.Image.from(gray));
    final blur = img.gaussianBlur(inv, radius: 6);
    return img.compositeImage(gray, blur, blend: img.BlendMode.dodge);
  }

  img.Image _cartoon(img.Image src) {
    final flat = img.quantize(img.Image.from(src), numberOfColors: 10);
    final edges = img.sobel(img.grayscale(src));
    for (var y = 0; y < flat.height; y++) {
      for (var x = 0; x < flat.width; x++) {
        final e = edges.getPixel(x, y);
        if (e.r > 48) flat.setPixelRgb(x, y, 15, 15, 15);
      }
    }
    return flat;
  }

  img.Image _frame(img.Image image, String frame) {
    if (frame == 'vignette') return _vignette(image);
    if (frame == 'none') return image;
    final margin = frame == 'polaroid' ? (image.width * 0.06).round() : (image.width * 0.025).round();
    final color = frame == 'white' || frame == 'polaroid' ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(10, 10, 10);
    final canvas = img.Image(
      width: image.width + margin * 2,
      height: image.height + margin * (frame == 'polaroid' ? 3 : 2),
      numChannels: 3,
    );
    img.fill(canvas, color: color);
    img.compositeImage(canvas, image, dstX: margin, dstY: margin);
    return canvas;
  }

  img.Image _vignette(img.Image image) {
    final cx = image.width / 2;
    final cy = image.height / 2;
    final maxD = (cx * cx + cy * cy);
    for (var y = 0; y < image.height; y += 1) {
      for (var x = 0; x < image.width; x += 1) {
        final dx = x - cx;
        final dy = y - cy;
        final t = ((dx * dx + dy * dy) / maxD).clamp(0.0, 1.0);
        if (t < 0.35) continue;
        final shade = 1 - ((t - 0.35) / 0.65) * 0.72;
        final p = image.getPixel(x, y);
        image.setPixelRgb(x, y, p.r * shade, p.g * shade, p.b * shade);
      }
    }
    return image;
  }

  void _memeBars(img.Image image, String caption) {
    final bar = (image.height * 0.12).round();
    img.fillRect(image, x1: 0, y1: 0, x2: image.width - 1, y2: bar, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(image, x1: 0, y1: image.height - bar, x2: image.width - 1, y2: image.height - 1, color: img.ColorRgb8(0, 0, 0));
    final parts = caption.split('\n');
    img.drawString(image, parts.first, font: img.arial48, y: (bar * 0.25).round(), color: img.ColorRgb8(255, 255, 255));
    if (parts.length > 1) {
      img.drawString(image, parts[1], font: img.arial48, y: image.height - bar + (bar * 0.25).round(), color: img.ColorRgb8(255, 255, 255));
    }
  }

  /// Desaturates strongly red pixels in the upper half, where eyes usually sit.
  List<int> redEye(List<int> bytes) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) throw AiException('Could not read this photo.');
    final image = _fit(decoded, 1400);
    final limitY = (image.height * 0.55).round();
    for (var y = (image.height * 0.18).round(); y < limitY; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        if (p.r > 140 && p.r > p.g * 1.5 && p.r > p.b * 1.5) {
          final gray = (p.r * 0.3 + p.g * 0.59 + p.b * 0.11);
          image.setPixelRgb(x, y, gray, gray, gray);
        }
      }
    }
    return img.encodeJpg(image, quality: 92);
  }

  Future<List<int>> redEyeOffUi(Uint8List bytes) {
    return Isolate.run(() => LocalEnhance().redEye(bytes));
  }

  (int, int, int) sampleColor(List<int> bytes, double fx, double fy) {
    final image = img.decodeImage(Uint8List.fromList(bytes));
    if (image == null) return (128, 128, 128);
    final x = (fx.clamp(0.0, 1.0) * (image.width - 1)).round();
    final y = (fy.clamp(0.0, 1.0) * (image.height - 1)).round();
    final p = image.getPixel(x, y);
    return (p.r.toInt(), p.g.toInt(), p.b.toInt());
  }

  /// Keeps pixels near [r],[g],[b] in color. Everything else becomes gray.
  List<int> colorSplash(List<int> bytes, {required int r, required int g, required int b}) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) throw AiException('Could not read this photo.');
    final image = _fit(decoded, 1400);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final d = (p.r - r).abs() + (p.g - g).abs() + (p.b - b).abs();
        if (d > 120) {
          final gray = p.r * 0.3 + p.g * 0.59 + p.b * 0.11;
          image.setPixelRgb(x, y, gray, gray, gray);
        }
      }
    }
    return img.encodeJpg(image, quality: 92);
  }

  Future<List<int>> colorSplashOffUi(Uint8List bytes, {required int r, required int g, required int b}) {
    return Isolate.run(() => LocalEnhance().colorSplash(bytes, r: r, g: g, b: b));
  }

  /// Layers a second photo with multiply or screen.
  List<int> doubleExposure(List<int> baseBytes, List<int> topBytes, {String mode = 'screen'}) {
    final a = img.decodeImage(Uint8List.fromList(baseBytes));
    final b = img.decodeImage(Uint8List.fromList(topBytes));
    if (a == null || b == null) throw AiException('Could not read these photos.');
    final base = _fit(a, 1200);
    final top = img.copyResize(b, width: base.width, height: base.height);
    final blend = mode == 'multiply' ? img.BlendMode.multiply : img.BlendMode.screen;
    img.compositeImage(base, top, blend: blend);
    return img.encodeJpg(base, quality: 92);
  }

  /// Passport-style portrait: white background, 35:45 frame.
  List<int> passport(List<int> bytes) {
    final png = removeBackground(bytes);
    final cut = img.decodeImage(Uint8List.fromList(png));
    if (cut == null) throw AiException('Could not read this photo.');
    const w = 413;
    const h = 531;
    final canvas = img.Image(width: w, height: h, numChannels: 4);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    final fitted = img.copyResize(cut, height: (h * 0.86).round());
    img.compositeImage(canvas, fitted, center: true, dstY: (h * 0.08).round());
    return img.encodeJpg(canvas, quality: 92);
  }

  Map<String, String> readExif(List<int> bytes) {
    final image = img.decodeImage(Uint8List.fromList(bytes));
    if (image == null) return {};
    final out = <String, String>{};
    for (final dir in image.exif.directories.entries) {
      for (final tag in dir.value.data.entries) {
        final value = tag.value.toString();
        if (value.isEmpty) continue;
        out['${dir.key}:${tag.key}'] = value.length > 80 ? value.substring(0, 80) : value;
      }
    }
    return out;
  }

  Future<Map<String, String>> readExifOffUi(Uint8List bytes) {
    return Isolate.run(() => LocalEnhance().readExif(bytes));
  }

  /// Re-encodes without the original metadata and at a smaller size.
  List<int> stripAndCompress(List<int> bytes, {int maxSide = 1600, int quality = 72}) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) throw AiException('Could not read this photo.');
    final image = _fit(decoded, maxSide);
    image.exif = img.ExifData();
    return img.encodeJpg(image, quality: quality);
  }

  void _drawLabel(img.Image image, String label, {required bool bottom, double yFraction = 0.82}) {
    final y = bottom ? (image.height * 0.9).round() : (image.height * yFraction).round();
    img.drawString(
      image,
      label,
      font: img.arial48,
      x: (image.width * 0.08).round(),
      y: y,
      color: img.ColorRgb8(255, 255, 255),
    );
  }

  /// Brand watermark: pink (#EA026A) "Enhancify" with a thin white outline,
  /// sized to the photo and placed bottom-right.
  static void drawWatermark(img.Image image, {String label = 'Enhancify'}) {
    final tmp = img.Image(width: label.length * 40 + 24, height: 64, numChannels: 4);
    final white = img.ColorRgba8(255, 255, 255, 235);
    for (final (dx, dy) in const [(-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (1, 1), (-1, 1), (1, -1)]) {
      img.drawString(tmp, label, font: img.arial48, x: 10 + dx, y: 6 + dy, color: white);
    }
    img.drawString(tmp, label, font: img.arial48, x: 10, y: 6, color: img.ColorRgba8(234, 2, 106, 255));
    var mark = img.trim(tmp, mode: img.TrimMode.transparent);
    final targetH = (image.height * 0.035).clamp(14, 160).round();
    mark = img.copyResize(mark, height: targetH, interpolation: img.Interpolation.average);
    final margin = (image.width * 0.03).round();
    img.compositeImage(image, mark,
        dstX: math.max(0, image.width - mark.width - margin),
        dstY: math.max(0, image.height - mark.height - margin));
  }

  /// Removes a plain background by clearing pixels close to the corner color.
  List<int> removeBackground(List<int> bytes) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) throw AiException('Could not read this photo.');
    final src = _fit(decoded, 900);
    final out = img.Image(width: src.width, height: src.height, numChannels: 4);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        out.setPixel(x, y, src.getPixel(x, y));
      }
    }
    final bg = src.getPixel(0, 0);
    bool close(img.Pixel p) {
      final d = (p.r - bg.r).abs() + (p.g - bg.g).abs() + (p.b - bg.b).abs();
      return d < 90;
    }
    final seen = List<bool>.filled(src.width * src.height, false);
    final queue = <int>[0, src.width - 1, (src.height - 1) * src.width, src.width * src.height - 1];
    var head = 0;
    while (head < queue.length) {
      final i = queue[head++];
      if (i < 0 || i >= seen.length || seen[i]) continue;
      seen[i] = true;
      final x = i % src.width;
      final y = i ~/ src.width;
      if (!close(out.getPixel(x, y))) continue;
      out.setPixelRgba(x, y, 0, 0, 0, 0);
      if (x > 0) queue.add(i - 1);
      if (x + 1 < src.width) queue.add(i + 1);
      if (y > 0) queue.add(i - src.width);
      if (y + 1 < src.height) queue.add(i + src.width);
    }
    return img.encodePng(out);
  }

  /// A short looping GIF made from one photo.
  List<int> makeGif(List<int> bytes) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) throw AiException('Could not read this photo.');
    final base = _fit(decoded, 480);
    img.Image? anim;
    for (var i = 0; i < 8; i++) {
      final z = 1 + (i < 4 ? i : 7 - i) * 0.03;
      final w = (base.width / z).round();
      final h = (base.height / z).round();
      final x = ((base.width - w) / 2).round();
      final y = ((base.height - h) / 2).round();
      var frame = img.copyResize(
        img.copyCrop(base, x: x, y: y, width: w, height: h),
        width: base.width,
        height: base.height,
      );
      frame.frameDuration = 120;
      if (anim == null) {
        anim = frame;
      } else {
        anim.addFrame(frame);
      }
    }
    return img.encodeGif(anim!);
  }

  /// Side-by-side or grid collage of 2 to 4 photos.
  List<int> collage(List<List<int>> photos, {String layout = 'grid'}) {
    final images = <img.Image>[];
    for (final bytes in photos.take(6)) {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded != null) images.add(_fit(decoded, 800));
    }
    if (images.isEmpty) throw AiException('Could not read these photos.');
    if (layout == 'story') {
      final canvas = img.Image(width: 720, height: 1280, numChannels: 3);
      img.fill(canvas, color: img.ColorRgb8(12, 10, 12));
      final cellH = 1280 ~/ images.length;
      for (var i = 0; i < images.length; i++) {
        final fitted = img.copyResize(images[i], width: 720, height: cellH);
        img.compositeImage(canvas, fitted, dstY: i * cellH);
      }
      return img.encodeJpg(canvas, quality: 90);
    }
    if (layout == 'polaroid') {
      final canvas = img.Image(width: 900, height: 1100, numChannels: 3);
      img.fill(canvas, color: img.ColorRgb8(245, 242, 236));
      final shot = img.copyResizeCropSquare(images.first, size: 760);
      img.compositeImage(canvas, shot, dstX: 70, dstY: 70);
      return img.encodeJpg(canvas, quality: 90);
    }
    if (layout == 'mosaic' && images.length >= 3) {
      final canvas = img.Image(width: 1200, height: 800, numChannels: 3);
      img.fill(canvas, color: img.ColorRgb8(20, 16, 18));
      img.compositeImage(canvas, img.copyResize(images[0], width: 800, height: 800), dstX: 0, dstY: 0);
      img.compositeImage(canvas, img.copyResize(images[1], width: 400, height: 400), dstX: 800, dstY: 0);
      img.compositeImage(canvas, img.copyResize(images[2], width: 400, height: 400), dstX: 800, dstY: 400);
      return img.encodeJpg(canvas, quality: 90);
    }
    const cell = 600;
    final cols = images.length == 3 ? 3 : (images.length <= 2 ? images.length : 2);
    final rows = (images.length / cols).ceil();
    final canvas = img.Image(width: cols * cell, height: rows * cell, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(20, 16, 18));
    for (var i = 0; i < images.length; i++) {
      final fitted = img.copyResizeCropSquare(images[i], size: cell);
      img.compositeImage(canvas, fitted, dstX: (i % cols) * cell, dstY: (i ~/ cols) * cell);
    }
    return img.encodeJpg(canvas, quality: 90);
  }

  /// Restyles the selected photo. Each style changes that same picture.
  List<int> style(List<int> bytes, String prompt) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) throw AiException('Could not read this photo.');
    var image = _fit(decoded, 1280);
    final p = prompt.toLowerCase();
    if (p.contains('sketch') || p.contains('pencil') || p.contains('graphite')) {
      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 1.35);
      image = img.convolution(image, filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0]);
    } else if (p.contains('black and white') || p.contains('b&w') || p.contains('studio')) {
      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 1.2, brightness: 1.04);
    } else if (p.contains('pixel')) {
      final small = img.copyResize(image, width: 96, interpolation: img.Interpolation.average);
      image = img.copyResize(small, width: image.width, interpolation: img.Interpolation.nearest);
    } else if (p.contains('oil') || p.contains('royal') || p.contains('renaissance')) {
      image = img.adjustColor(image, saturation: 1.25, contrast: 1.15);
      image = img.gaussianBlur(image, radius: 2);
    } else if (p.contains('watercolor')) {
      image = img.adjustColor(image, saturation: 0.85, brightness: 1.08);
      image = img.gaussianBlur(image, radius: 3);
    } else if (p.contains('comic')) {
      image = img.adjustColor(image, saturation: 1.4, contrast: 1.45);
      image = img.quantize(image, numberOfColors: 16);
    } else if (p.contains('cyber') || p.contains('neon')) {
      image = img.adjustColor(image, saturation: 1.5, contrast: 1.2);
      image = img.colorOffset(image, red: 20, green: -10, blue: 40);
    } else if (p.contains('vintage') || p.contains('1970')) {
      image = img.adjustColor(image, saturation: 0.7, contrast: 1.05);
      image = img.sepia(image, amount: 0.45);
    } else if (p.contains('clay')) {
      image = img.adjustColor(image, saturation: 1.1, brightness: 1.08);
      image = img.gaussianBlur(image, radius: 2);
    } else if (p.contains('colorize')) {
      image = img.adjustColor(image, saturation: 1.35, contrast: 1.08, brightness: 1.04);
      image = _sharpen(image);
    } else {
      image = img.adjustColor(image, saturation: 1.35, contrast: 1.12, brightness: 1.03);
      image = _sharpen(image);
    }
    return img.encodeJpg(image, quality: 92);
  }

  img.Image _fit(img.Image source, int maxSide) {
    final long = source.width > source.height ? source.width : source.height;
    if (long <= maxSide) return source;
    final scale = maxSide / long;
    return img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  img.Image _sharpen(img.Image source) => img.convolution(
        source,
        filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
      );
}

class _BakeJob {
  const _BakeJob({
    required this.bytes,
    required this.look,
    required this.brightness,
    required this.contrast,
    required this.exposure,
    required this.lightness,
    required this.highlight,
    required this.saturation,
    required this.vibrance,
    required this.tint,
    required this.fade,
    required this.grain,
    required this.warmth,
    required this.filter,
    required this.frame,
    required this.text,
    required this.sticker,
    required this.watermark,
    required this.meme,
    required this.quarterTurns,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    this.maxSide = 900,
  });

  final Uint8List bytes;
  final String look;
  final double brightness;
  final double contrast;
  final double exposure;
  final double lightness;
  final double highlight;
  final double saturation;
  final double vibrance;
  final double tint;
  final double fade;
  final double grain;
  final double warmth;
  final String filter;
  final String frame;
  final String text;
  final String sticker;
  final bool watermark;
  final bool meme;
  final int quarterTurns;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final int maxSide;
}

List<int> _runBake(_BakeJob job) {
  return LocalEnhance().bake(
    job.bytes,
    look: job.look,
    brightness: job.brightness,
    contrast: job.contrast,
    exposure: job.exposure,
    lightness: job.lightness,
    highlight: job.highlight,
    saturation: job.saturation,
    vibrance: job.vibrance,
    tint: job.tint,
    fade: job.fade,
    grain: job.grain,
    warmth: job.warmth,
    filter: job.filter,
    frame: job.frame,
    text: job.text,
    sticker: job.sticker,
    watermark: job.watermark,
    meme: job.meme,
    quarterTurns: job.quarterTurns,
    cropLeft: job.cropLeft,
    cropTop: job.cropTop,
    cropRight: job.cropRight,
    cropBottom: job.cropBottom,
    maxSide: job.maxSide,
  );
}
