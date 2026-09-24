import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// Paints the mask from the finger strokes, then inpaints that region.
Future<Uint8List> removePaintedObject(
  Uint8List photo,
  List<List<Offset>> strokes, {
  required double brushFraction,
  required bool telea,
}) {
  final decoded = img.decodeImage(photo);
  if (decoded == null) {
    throw StateError('Could not read this photo.');
  }
  final mask = buildRemovalMask(
    decoded.width,
    decoded.height,
    strokes,
    brushFraction: brushFraction,
  );
  final jpg = img.encodeJpg(decoded, quality: 95);
  return removeObject(Uint8List.fromList(jpg), mask, telea: telea);
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

/// Builds a black mask with white strokes. Strokes are 0–1 fractions of the photo.
Uint8List buildRemovalMask(
  int width,
  int height,
  List<List<Offset>> strokes, {
  required double brushFraction,
}) {
  final mask = img.Image(width: width, height: height, numChannels: 1);
  img.fill(mask, color: img.ColorRgb8(0, 0, 0));
  final radius = (width * brushFraction).round().clamp(4, width ~/ 4);
  final white = img.ColorRgb8(255, 255, 255);
  for (final stroke in strokes) {
    var previousX = -1;
    var previousY = -1;
    for (final p in stroke) {
      final x = (p.dx * (width - 1)).round().clamp(0, width - 1);
      final y = (p.dy * (height - 1)).round().clamp(0, height - 1);
      img.fillCircle(mask, x: x, y: y, radius: radius, color: white);
      if (previousX >= 0) {
        img.drawLine(
          mask,
          x1: previousX,
          y1: previousY,
          x2: x,
          y2: y,
          color: white,
          thickness: radius * 2,
        );
      }
      previousX = x;
      previousY = y;
    }
  }
  return img.encodePng(mask);
}
